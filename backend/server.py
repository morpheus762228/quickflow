#!/usr/bin/env python3
"""
QuickFlow Orchestrator
======================
Master controller that coordinates:
  1. Streaming ASR with prebuffer
  2. Context injection from screen
  3. Two-stage LLM cleanup + transformation
  4. Correction learning
  5. Latency budget management

Usage:
  python3 server.py start    # Start recording
  python3 server.py stop     # Stop, transcribe, clean, transform, paste
  python3 server.py stats    # Show learning stats
  python3 server.py config   # Show current configuration
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from backend.budget import LatencyBudget, BudgetTier
from backend.asr.streamer import BatchASR
from backend.context.injector import ContextInjector
from backend.learning.adapter import LearningAdapter, CorrectionDB

# Try importing streaming ASR and LLM — fall back gracefully
try:
    from backend.asr.streamer import StreamingASR
    HAS_STREAMING_ASR = True
except ImportError:
    HAS_STREAMING_ASR = False

try:
    from backend.llm.pipeline import TwoStageLLM, LLMConfig, RuleBasedCleaner
    HAS_LOCAL_LLM = True
except ImportError:
    HAS_LOCAL_LLM = False
    from backend.llm.pipeline import RuleBasedCleaner


# ── Configuration ──

CONFIG = {
    "model_size": os.environ.get("QUICKFLOW_ASR_MODEL", "small"),
    "llm_model_path": os.environ.get("QUICKFLOW_LLM_MODEL", ""),
    "use_streaming": os.environ.get("QUICKFLOW_STREAMING", "0") == "1",
    "budget_tier": os.environ.get("QUICKFLOW_BUDGET", "normal"),
    "default_style": os.environ.get("QUICKFLOW_STYLE", "auto"),  # auto-detect from context
}

PIDFILE = Path("/tmp/quickflow-orchestrator.pid")
FFMPEG_PIDFILE = Path("/tmp/quickflow-ffmpeg.pid")
AUDIOFILE = Path("/tmp/quickflow-orchestrator.wav")


class Orchestrator:
    def __init__(self):
        self.batch_asr = BatchASR(model_size=CONFIG["model_size"])
        self.context = ContextInjector()
        self.learning = LearningAdapter()
        self.budget: LatencyBudget = None

        # Lazy-loaded
        self._streaming_asr = None
        self._llm = None

    @property
    def streaming_asr(self):
        if self._streaming_asr is None and HAS_STREAMING_ASR:
            self._streaming_asr = StreamingASR(model_size=CONFIG["model_size"])
        return self._streaming_asr

    @property
    def llm(self):
        if self._llm is None and HAS_LOCAL_LLM and CONFIG["llm_model_path"]:
            self._llm = TwoStageLLM(LLMConfig(model_path=CONFIG["llm_model_path"]))
            print(f"[LLM] Loaded in {self._llm._load_time:.0f}ms")
        return self._llm

    # ── Public API ──

    def start_recording(self):
        """Begin audio capture with prebuffer."""
        self.budget = LatencyBudget(
            tier=BudgetTier(CONFIG["budget_tier"])
        )
        self.budget.start_stage("prebuffer")

        # Kill any existing ffmpeg recording
        self._kill_ffmpeg()

        # Remove stale audio file
        AUDIOFILE.unlink(missing_ok=True)

        # Auto-detect microphone device index (avoids BlackHole/virtual devices)
        mic_input = self._find_mic_input()

        # Start recording
        proc = subprocess.Popen([
            "ffmpeg", "-y", "-loglevel", "quiet",
            "-f", "avfoundation", "-i", mic_input,
            "-ac", "1", "-ar", "16000",
            str(AUDIOFILE),
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # Save ffmpeg PID for reliable cleanup
        FFMPEG_PIDFILE.write_text(str(proc.pid))
        PIDFILE.write_text(str(os.getpid()))

        self.notify("QuickFlow 🎙️", "Recording started — speak now")
        print(json.dumps({"status": "recording", "pid": os.getpid(), "ffmpeg_pid": proc.pid}))

    def stop_and_process(self):
        """Stop recording, transcribe with full pipeline."""
        return self._process_audio(kill_recording=True)
    
    def transcribe_existing(self):
        """Transcribe an already-recorded WAV file (no recording step)."""
        return self._process_audio(kill_recording=False)
    
    def _process_audio(self, kill_recording: bool) -> str:
        if self.budget is None:
            self.budget = LatencyBudget(tier=BudgetTier(CONFIG["budget_tier"]))

        self.budget.end_stage("prebuffer")

        # ── Step 1: Stop recording (if applicable) ──
        if kill_recording:
            self._kill_ffmpeg()
            time.sleep(0.5)  # Wait for WAV flush

        if not AUDIOFILE.exists():
            self.notify("QuickFlow", "No audio captured — check microphone permission")
            print("[Orchestrator] ERROR: No audio file found", file=sys.stderr)
            return self._error("No audio file — grant mic permission in System Settings → Privacy → Microphone")

        file_size = AUDIOFILE.stat().st_size
        if file_size < 1000:  # Less than ~30ms of audio
            self.notify("QuickFlow", "Recording too short or empty")
            print(f"[Orchestrator] ERROR: Audio file too small ({file_size} bytes)", file=sys.stderr)
            AUDIOFILE.unlink(missing_ok=True)
            return self._error(f"Audio file too small: {file_size} bytes")

        duration_s = file_size / (16000 * 2)  # 16-bit mono
        print(f"[Orchestrator] Captured {duration_s:.1f}s audio ({file_size} bytes)", file=sys.stderr)

        # ── Step 2: Context Injection ──
        self.budget.start_stage("context_fetch")
        ctx = self.context.capture()
        self.budget.end_stage("context_fetch")

        print(f"[Orchestrator] Context: {ctx.active_app} — {ctx.window_title[:50]}", file=sys.stderr)

        # ── Step 3: ASR Transcription ──
        self.budget.start_stage("asr")
        asr_prompt = self.context.build_asr_prompt(ctx) if ctx.active_app else ""

        # Check if we should degrade (use smaller model)
        if self.budget.should_degrade("asr"):
            print("[Orchestrator] ⚠️ Degrading ASR to tiny model", file=sys.stderr)
            raw_text = BatchASR(model_size="tiny").transcribe_file(str(AUDIOFILE), asr_prompt)
        else:
            raw_text = self.batch_asr.transcribe_file(str(AUDIOFILE), asr_prompt)

        asr_latency = self.budget.end_stage("asr")
        print(f"[Orchestrator] Raw transcript: {raw_text[:100]}", file=sys.stderr)

        if not raw_text.strip():
            self.notify("QuickFlow", "No speech detected")
            return self._error("Empty transcript")

        # ── Step 4: LLM Cleanup (Stage 1) ──
        self.budget.start_stage("llm_clean")

        if self.llm and self.llm.is_loaded() and not self.budget.should_degrade("llm_clean"):
            # Enhance prompt with learned corrections
            style = ctx.detect_style(ctx) if CONFIG["default_style"] == "auto" else CONFIG["default_style"]
            few_shot = self.learning.db.build_few_shot(style=style, max_examples=3)

            if few_shot:
                cleaned = self.llm.clean(raw_text)  # TODO: inject few_shot into prompt
            else:
                cleaned = self.llm.clean(raw_text)
        else:
            # Fall back to rule-based cleaning
            print("[Orchestrator] ⚠️ Using rule-based cleaner", file=sys.stderr)
            cleaned = RuleBasedCleaner.clean(raw_text)

        clean_latency = self.budget.end_stage("llm_clean")

        # ── Step 5: LLM Transform (Stage 2) ──
        self.budget.start_stage("llm_transform")

        style = CONFIG["default_style"]
        if style == "auto":
            style = self.context.detect_style(ctx)

        if self.llm and self.llm.is_loaded() and style != "default" and not self.budget.should_degrade("llm_transform"):
            transformed = self.llm.transform(cleaned, style)
        else:
            transformed = cleaned

        transform_latency = self.budget.end_stage("llm_transform")

        # ── Step 6: Paste ──
        self.budget.start_stage("paste")
        self._copy_and_paste(transformed)
        paste_latency = self.budget.end_stage("paste")

        # ── Summary ──
        total_ms = self.budget.total_elapsed()
        print(self.budget.summary(), file=sys.stderr)

        # Notify
        self.notify(
            "QuickFlow ✅",
            f"Transcribed in {total_ms:.0f}ms"
        )

        # Cleanup
        AUDIOFILE.unlink(missing_ok=True)

        return json.dumps({
            "status": "ok",
            "raw": raw_text,
            "cleaned": cleaned,
            "transformed": transformed,
            "style": style,
            "context_app": ctx.active_app,
            "context_title": ctx.window_title,
            "latency_total_ms": total_ms,
            "latency_asr_ms": asr_latency,
            "latency_clean_ms": clean_latency,
            "latency_transform_ms": transform_latency,
            "latency_paste_ms": paste_latency,
            "budget_tier": CONFIG["budget_tier"],
            "degraded": any(s.degraded for s in self.budget.stages),
        })

    def stats(self):
        """Show correction learning statistics."""
        db = CorrectionDB()
        stats = db.stats()
        recent = db.get_recent(limit=5)
        return json.dumps({
            "stats": stats,
            "recent_corrections": [
                {"original": c.original_text[:80], "corrected": c.corrected_text[:80], "style": c.style}
                for c in recent
            ],
        }, indent=2)

    def config(self):
        """Show current configuration."""
        return json.dumps({
            "config": CONFIG,
            "has_streaming_asr": HAS_STREAMING_ASR,
            "has_local_llm": HAS_LOCAL_LLM,
            "python_version": sys.version,
        }, indent=2)

    # ── Helpers ──

    @staticmethod
    def _find_mic_input() -> str:
        """Find the best microphone input for ffmpeg avfoundation.
        Skips virtual audio devices (BlackHole, Loopback, etc.).
        Returns a string like ':1' or ':default'."""
        # Allow override via env var
        override = os.environ.get("QUICKFLOW_MIC_INDEX")
        if override:
            return f":{override}"
        try:
            result = subprocess.run(
                ["ffmpeg", "-list_devices", "true", "-f", "avfoundation", "-i", ""],
                capture_output=True, text=True, timeout=5
            )
            # ffmpeg prints device list to stderr
            lines = (result.stderr or "").split("\n")
            audio_devices = []
            in_audio = False
            for line in lines:
                if "AVFoundation audio devices" in line:
                    in_audio = True
                    continue
                if in_audio and line.strip().startswith("["):
                    # Parse: [1] MacBook Pro Microphone
                    parts = line.split("]", 1)
                    if len(parts) >= 2:
                        idx = parts[0].strip().lstrip("[")
                        name = parts[1].strip()
                        audio_devices.append((idx, name))
                elif in_audio and not line.strip().startswith("["):
                    if line.strip():
                        in_audio = False
            # Prefer physical mics, skip virtual devices
            virtual_names = {"blackhole", "loopback", "soundflower", "aggregate", "system"}
            for idx, name in audio_devices:
                if not any(v in name.lower() for v in virtual_names):
                    return f":{idx}"
            # Fallback: first audio device
            if audio_devices:
                return f":{audio_devices[0][0]}"
        except Exception:
            pass
        return ":1"  # Safe default on most Macs

    def _kill_ffmpeg(self):
        """Kill the ffmpeg recording process using the PID file."""
        if FFMPEG_PIDFILE.exists():
            try:
                pid = int(FFMPEG_PIDFILE.read_text().strip())
                os.kill(pid, 2)  # SIGINT for clean WAV flush
                time.sleep(0.3)
                try:
                    os.kill(pid, 0)  # Check if still alive
                    os.kill(pid, 9)  # SIGKILL if needed
                except OSError:
                    pass  # Already dead
            except (ValueError, OSError, ProcessLookupError):
                pass
            FFMPEG_PIDFILE.unlink(missing_ok=True)
        # Fallback: pkill any remaining
        subprocess.run(["pkill", "-9", "-f", "ffmpeg.*avfoundation"], capture_output=True)

    def notify(self, title: str, body: str):
        subprocess.run([
            "osascript", "-e",
            f'display notification "{body}" with title "{title}"'
        ], capture_output=True, timeout=2)

    def _copy_and_paste(self, text: str):
        """Copy text to clipboard and attempt paste."""
        subprocess.run(["pbcopy"], input=text, text=True, timeout=1)
        # Try paste
        subprocess.run([
            "osascript", "-e",
            'try\n'
            '  tell application "System Events" to keystroke "v" using command down\n'
            'end try'
        ], capture_output=True, timeout=2)

    def _error(self, msg: str) -> str:
        return json.dumps({"status": "error", "message": msg})


# ── CLI Entry Point ──

def main():
    if len(sys.argv) < 2:
        print("Usage: server.py <start|stop|stats|config>", file=sys.stderr)
        sys.exit(1)

    orch = Orchestrator()
    command = sys.argv[1]

    if command == "start":
        result = orch.start_recording()
    elif command == "stop":
        result = orch.stop_and_process()
    elif command == "transcribe-file":
        result = orch.transcribe_existing()
    elif command == "stats":
        result = orch.stats()
    elif command == "config":
        result = orch.config()
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)

    print(result)


if __name__ == "__main__":
    main()
