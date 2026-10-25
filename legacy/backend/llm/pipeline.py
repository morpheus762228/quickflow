"""
Two-Stage LLM Pipeline
======================
Stage 1 (Clean): Fix ASR artifacts, remove filler words, add punctuation.
Stage 2 (Transform): Apply style/format based on context and preferences.
"""

import time
from dataclasses import dataclass
from typing import Optional


@dataclass
class LLMConfig:
    model_path: str = ""          # Path to GGUF model
    n_ctx: int = 2048
    n_threads: int = 4
    temperature: float = 0.1
    top_p: float = 0.9
    # Stage-specific
    clean_max_tokens: int = 128
    transform_max_tokens: int = 256


class TwoStageLLM:
    """
    Local LLM pipeline for transcript cleanup and transformation.
    Uses llama-cpp-python for local inference.
    """

    CLEAN_PROMPT = """You are a transcript cleaner. Fix the following speech-to-text transcript:
- Remove filler words (um, uh, like, you know, I mean, sort of, kind of)
- Fix punctuation and capitalization
- Remove repeated words and stutters
- Keep the original meaning and tone exactly
- Output ONLY the cleaned text, no explanations

Transcript: {transcript}

Cleaned:"""

    TRANSFORM_PROMPTS = {
        "default": "Format the following text clearly with proper paragraphs:\n\n{text}",
        "email": "Convert this dictation into a professional email:\n\n{text}",
        "note": "Convert this dictation into a concise note with bullet points:\n\n{text}",
        "code_comment": "Convert this dictation into a code comment:\n\n{text}",
        "message": "Convert this dictation into a casual message:\n\n{text}",
    }

    def __init__(self, config: LLMConfig):
        self.config = config
        self._llm = None
        self._load_time: float = 0.0

    @property
    def llm(self):
        if self._llm is None:
            self._load()
        return self._llm

    def _load(self):
        t0 = time.time()
        from llama_cpp import Llama
        self._llm = Llama(
            model_path=self.config.model_path,
            n_ctx=self.config.n_ctx,
            n_threads=self.config.n_threads,
            verbose=False,
        )
        self._load_time = (time.time() - t0) * 1000

    def is_loaded(self) -> bool:
        return self._llm is not None

    def clean(self, transcript: str) -> str:
        """Stage 1: Clean up raw ASR transcript."""
        if not transcript.strip():
            return transcript

        prompt = self.CLEAN_PROMPT.format(transcript=transcript)
        t0 = time.time()

        output = self.llm(
            prompt,
            max_tokens=self.config.clean_max_tokens,
            temperature=self.config.temperature,
            top_p=self.config.top_p,
            stop=["\n\n", "Transcript:"],
            echo=False,
        )

        latency = (time.time() - t0) * 1000
        cleaned = output['choices'][0]['text'].strip() if output and 'choices' in output else transcript

        # If cleaning produced garbage, return original
        if len(cleaned) < len(transcript) * 0.3:
            return transcript

        return cleaned

    def transform(self, text: str, style: str = "default") -> str:
        """Stage 2: Transform text based on style/format."""
        if style not in self.TRANSFORM_PROMPTS:
            style = "default"

        template = self.TRANSFORM_PROMPTS[style]
        prompt = template.format(text=text)
        t0 = time.time()

        output = self.llm(
            prompt,
            max_tokens=self.config.transform_max_tokens,
            temperature=self.config.temperature * 1.5,  # slightly more creative
            top_p=self.config.top_p,
            stop=["\n\n\n"],
            echo=False,
        )

        latency = (time.time() - t0) * 1000
        transformed = output['choices'][0]['text'].strip() if output and 'choices' in output else text

        return transformed if transformed else text

    def pipeline(
        self, transcript: str, style: str = "default", skip_clean: bool = False
    ) -> dict:
        """Run the full two-stage pipeline and return results with latency info."""
        result = {
            "raw": transcript,
            "cleaned": transcript,
            "transformed": transcript,
            "clean_latency_ms": 0,
            "transform_latency_ms": 0,
        }

        if not skip_clean and transcript.strip():
            t0 = time.time()
            result["cleaned"] = self.clean(transcript)
            result["clean_latency_ms"] = (time.time() - t0) * 1000

        if style != "default" or not skip_clean:
            t0 = time.time()
            result["transformed"] = self.transform(result["cleaned"], style)
            result["transform_latency_ms"] = (time.time() - t0) * 1000

        return result


# ── No-LLM fallback (rule-based cleanup only) ──

class RuleBasedCleaner:
    """Simple rule-based transcript cleaner for when no LLM is available."""

    FILLER_WORDS = {
        "um", "uh", "er", "ah", "hmm", "like", "you know",
        "i mean", "sort of", "kind of", "basically", "literally",
        "actually", "just", "really", "very", "so", "well",
    }

    @staticmethod
    def clean(text: str) -> str:
        """Apply basic cleanup rules."""
        import re

        # Remove filler words
        for filler in sorted(RuleBasedCleaner.FILLER_WORDS, key=len, reverse=True):
            pattern = r'\b' + re.escape(filler) + r'\b'
            text = re.sub(pattern, '', text, flags=re.IGNORECASE)

        # Fix multiple spaces
        text = re.sub(r'\s+', ' ', text)

        # Capitalize first letter
        if text:
            text = text[0].upper() + text[1:]

        # Ensure ends with punctuation
        if text and text[-1] not in '.!?':
            text += '.'

        return text.strip()
