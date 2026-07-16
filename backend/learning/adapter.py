"""
Correction Learning System
==========================
SQLite-backed correction store that learns from user edits.
Builds few-shot examples for the LLM to improve over time.
"""

import json
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


DB_PATH = Path.home() / ".quickflow" / "corrections.db"


@dataclass
class Correction:
    id: Optional[int]
    original_text: str
    corrected_text: str
    context: str          # What app/window the user was in
    style: str            # Detected style at the time
    timestamp: float
    edit_distance: float  # Normalized Levenshtein distance


class CorrectionDB:
    """SQLite store for transcript corrections."""

    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self):
        with self._connect() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS corrections (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    original_text TEXT NOT NULL,
                    corrected_text TEXT NOT NULL,
                    context TEXT DEFAULT '',
                    style TEXT DEFAULT 'default',
                    timestamp REAL NOT NULL,
                    edit_distance REAL NOT NULL,
                    metadata TEXT DEFAULT '{}'
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_timestamp ON corrections(timestamp DESC)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_style ON corrections(style)
            """)
            conn.commit()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def record(
        self,
        original: str,
        corrected: str,
        context: str = "",
        style: str = "default",
    ) -> int:
        """Record a correction pair. Returns the row ID."""
        dist = self._normalized_edit_distance(original, corrected)

        with self._connect() as conn:
            cursor = conn.execute(
                """INSERT INTO corrections
                   (original_text, corrected_text, context, style, timestamp, edit_distance)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (original, corrected, context, style, time.time(), dist),
            )
            conn.commit()
            return cursor.lastrowid

    def get_recent(self, limit: int = 20, style: Optional[str] = None) -> list[Correction]:
        """Get most recent corrections, optionally filtered by style."""
        with self._connect() as conn:
            if style:
                rows = conn.execute(
                    "SELECT * FROM corrections WHERE style = ? ORDER BY timestamp DESC LIMIT ?",
                    (style, limit),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM corrections ORDER BY timestamp DESC LIMIT ?",
                    (limit,),
                ).fetchall()
        return [self._row_to_correction(r) for r in rows]

    def get_similar(self, text: str, limit: int = 5) -> list[Correction]:
        """Find similar past corrections using trigram overlap."""
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM corrections ORDER BY timestamp DESC LIMIT 200"
            ).fetchall()

        scored = []
        for row in rows:
            corr = self._row_to_correction(row)
            score = self._trigram_similarity(text, corr.original_text)
            scored.append((score, corr))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [c for s, c in scored[:limit] if s > 0.1]

    def build_few_shot(self, style: Optional[str] = None, max_examples: int = 3) -> str:
        """
        Build a few-shot prompt from recent corrections.
        Used to adapt the LLM to the user's preferences.
        """
        corrections = self.get_recent(limit=50, style=style)
        if not corrections:
            return ""

        # Pick diverse, high-quality examples
        examples = []
        seen = set()
        for corr in corrections:
            if len(examples) >= max_examples:
                break
            key = corr.original_text[:50]
            if key in seen:
                continue
            if corr.edit_distance > 0.05:  # Must be a meaningful correction
                seen.add(key)
                examples.append(corr)

        if not examples:
            return ""

        lines = ["Here are examples of how you prefer text to be corrected:"]
        for ex in examples:
            lines.append(f"Input: {ex.original_text}")
            lines.append(f"Output: {ex.corrected_text}")
            lines.append("")

        return "\n".join(lines)

    def stats(self) -> dict:
        """Return usage statistics."""
        with self._connect() as conn:
            total = conn.execute("SELECT COUNT(*) FROM corrections").fetchone()[0]
            recent_count = conn.execute(
                "SELECT COUNT(*) FROM corrections WHERE timestamp > ?",
                (time.time() - 86400 * 7,),
            ).fetchone()[0]
            styles = conn.execute(
                "SELECT style, COUNT(*) as cnt FROM corrections GROUP BY style ORDER BY cnt DESC"
            ).fetchall()
        return {
            "total_corrections": total,
            "corrections_this_week": recent_count,
            "by_style": {r["style"]: r["cnt"] for r in styles},
        }

    def prune(self, max_entries: int = 1000):
        """Keep only the most recent N entries."""
        with self._connect() as conn:
            count = conn.execute("SELECT COUNT(*) FROM corrections").fetchone()[0]
            if count > max_entries:
                conn.execute(
                    "DELETE FROM corrections WHERE id NOT IN (SELECT id FROM corrections ORDER BY timestamp DESC LIMIT ?)",
                    (max_entries,),
                )
                conn.commit()

    # ── Helpers ──

    @staticmethod
    def _normalized_edit_distance(a: str, b: str) -> float:
        if not a and not b:
            return 0.0
        if not a or not b:
            return 1.0

        # Simple Levenshtein
        m, n = len(a), len(b)
        dp = list(range(n + 1))
        for i in range(1, m + 1):
            prev = dp[0]
            dp[0] = i
            for j in range(1, n + 1):
                temp = dp[j]
                cost = 0 if a[i - 1] == b[j - 1] else 1
                dp[j] = min(dp[j] + 1, dp[j - 1] + 1, prev + cost)
                prev = temp
        return dp[n] / max(m, n)

    @staticmethod
    def _trigram_similarity(a: str, b: str) -> float:
        """Simple trigram overlap score."""
        def trigrams(s):
            return {s[i:i+3] for i in range(len(s) - 2)}
        ta = trigrams(a.lower())
        tb = trigrams(b.lower())
        if not ta or not tb:
            return 0.0
        return len(ta & tb) / len(ta | tb)

    @staticmethod
    def _row_to_correction(row) -> Correction:
        return Correction(
            id=row["id"],
            original_text=row["original_text"],
            corrected_text=row["corrected_text"],
            context=row["context"],
            style=row["style"],
            timestamp=row["timestamp"],
            edit_distance=row["edit_distance"],
        )


class LearningAdapter:
    """
    Integrates correction learning into the LLM pipeline.
    Builds adaptive prompts from learned corrections.
    """

    def __init__(self, db: Optional[CorrectionDB] = None):
        self.db = db or CorrectionDB()

    def enhance_clean_prompt(self, base_prompt: str, style: str = "default") -> str:
        """Enhance the cleaning prompt with learned corrections."""
        few_shot = self.db.build_few_shot(style=style, max_examples=3)
        if few_shot:
            # Insert few-shot examples before the instruction
            parts = base_prompt.split("Transcript:")
            if len(parts) >= 2:
                return parts[0] + "\n" + few_shot + "\nTranscript:" + parts[1]
        return base_prompt

    def suggest_correction(self, original: str, target: str) -> Optional[str]:
        """Check if we've seen a similar correction before and suggest the outcome."""
        similar = self.db.get_similar(original, limit=3)
        if similar and similar[0].edit_distance < 0.3:
            return similar[0].corrected_text
        return None

    def learn_from_edit(self, original: str, edited: str, context: str = "", style: str = "default"):
        """Record a user edit for future learning."""
        if original.strip() != edited.strip():
            self.db.record(original=original, corrected=edited, context=context, style=style)
            self.db.prune()
