"""
Screen Context Injection
========================
Grabs surrounding text from the active application to provide
context for better ASR accuracy and smarter LLM transformation.
"""

import subprocess
import time
from dataclasses import dataclass
from typing import Optional


@dataclass
class ScreenContext:
    """Context captured from the user's screen."""
    active_app: str
    window_title: str = ""
    selected_text: str = ""
    surrounding_text: str = ""  # Up to ~500 chars near cursor
    text_before_cursor: str = ""
    text_after_cursor: str = ""
    capture_latency_ms: float = 0.0


class ContextInjector:
    """
    Captures screen context for ASR and LLM stages.
    Uses AppleScript + Accessibility APIs (requires permissions).
    """

    MAX_CONTEXT_CHARS = 500
    MAX_SELECTION_CHARS = 2000

    def capture(self) -> ScreenContext:
        """Capture all available context from the active application."""
        t0 = time.time()

        active_app = self._get_active_app()
        window_title = self._get_window_title()
        selected_text = self._get_selected_text()
        surrounding = self._get_surrounding_text()

        ctx = ScreenContext(
            active_app=active_app,
            window_title=window_title or "",
            selected_text=selected_text or "",
            surrounding_text=surrounding or "",
            capture_latency_ms=(time.time() - t0) * 1000,
        )
        return ctx

    def build_asr_prompt(self, ctx: ScreenContext) -> str:
        """Build a whisper initial_prompt from screen context."""
        parts = []

        if ctx.window_title:
            parts.append(f"Context: user is in {ctx.active_app} — {ctx.window_title}")

        if ctx.selected_text:
            short = ctx.selected_text[:200]
            parts.append(f"Selected text: {short}")

        if ctx.surrounding_text:
            short = ctx.surrounding_text[:200]
            parts.append(f"Nearby text: {short}")

        return " | ".join(parts) if parts else ""

    def build_llm_prompt(self, ctx: ScreenContext, transcript: str) -> str:
        """Build a context-aware LLM prompt for cleanup/transformation."""
        parts = [f"Raw transcript: {transcript}"]

        if ctx.active_app:
            app_hint = self._app_style_hint(ctx.active_app)
            if app_hint:
                parts.append(f"Style hint: {app_hint}")

        if ctx.selected_text:
            parts.append(f"User has selected this text (use as reference): {ctx.selected_text[:300]}")

        if ctx.text_before_cursor:
            parts.append(f"Text before cursor: {ctx.text_before_cursor[:200]}")

        return "\n".join(parts)

    def detect_style(self, ctx: ScreenContext) -> str:
        """Infer the desired output style from screen context."""
        app = ctx.active_app.lower()
        title = ctx.window_title.lower()

        # Email
        if "mail" in app or "outlook" in app or "gmail" in title:
            return "email"

        # Code
        if any(ide in app for ide in ["xcode", "code", "terminal", "vim", "cursor", "zed"]):
            return "code_comment"

        # Messaging
        if any(msg in app for msg in ["messages", "slack", "discord", "telegram", "whatsapp", "signal"]):
            return "message"

        # Notes
        if any(note in app for note in ["notes", "notion", "obsidian", "bear", "craft", "apple notes"]):
            return "note"

        return "default"

    # ── Private helpers ──

    def _get_active_app(self) -> str:
        return self._osascript(
            'tell application "System Events" to get name of first application process whose frontmost is true'
        )

    def _get_window_title(self) -> str:
        return self._osascript(
            'tell application "System Events" to get title of front window of first application process whose frontmost is true'
        )

    def _get_selected_text(self) -> str:
        """Get currently selected text via clipboard trick."""
        # Save clipboard
        old_clip = subprocess.run(
            ["pbpaste"], capture_output=True, text=True
        ).stdout or ""

        # Copy selection
        subprocess.run([
            "osascript", "-e",
            'tell application "System Events" to keystroke "c" using command down'
        ], capture_output=True, timeout=2)

        time.sleep(0.1)

        # Read new clipboard
        selected = subprocess.run(
            ["pbpaste"], capture_output=True, text=True
        ).stdout or ""

        # Restore clipboard
        if old_clip != selected:
            subprocess.run(["pbcopy"], input=old_clip, text=True, timeout=1)

        return selected[:self.MAX_SELECTION_CHARS] if len(selected) < 50000 else ""

    def _get_surrounding_text(self) -> str:
        """Try to get text near cursor via accessibility."""
        return self._osascript("""
            tell application "System Events"
                try
                    set frontApp to first application process whose frontmost is true
                    set focusedElement to focused UI element of frontApp
                    if exists focusedElement then
                        try
                            return value of focusedElement
                        on error
                            try
                                return name of focusedElement
                            on error
                                return ""
                            end try
                        end try
                    end if
                on error
                    return ""
                end try
            end tell
        """)

    def _osascript(self, script: str) -> str:
        try:
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True, text=True, timeout=3
            )
            return result.stdout.strip()
        except Exception:
            return ""

    def _app_style_hint(self, app: str) -> str:
        hints = {
            "Mail": "This is an email — use formal language",
            "Messages": "This is a text message — use casual tone",
            "Slack": "This is a Slack message — use professional but casual tone",
            "Xcode": "This is a code comment — be technical and concise",
            "Visual Studio Code": "This is in a code editor — use appropriate formatting",
            "Terminal": "This is in the terminal — likely a command or note",
            "Notes": "This is a personal note — use natural language",
            "Obsidian": "This is a knowledge note — use clear, structured language",
        }
        return hints.get(app, "")
