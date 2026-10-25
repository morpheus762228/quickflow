"""
Voice Activity Detection
========================
Uses Silero VAD to segment audio into speech/non-speech chunks.
Runs on CPU, fast enough for real-time use.
"""

import time
from dataclasses import dataclass
from typing import Iterator, Optional

import numpy as np


@dataclass
class SpeechSegment:
    """A detected speech segment."""
    start_ms: float
    end_ms: float
    audio: np.ndarray  # float32, 16kHz mono
    confidence: float


class VAD:
    """Silero VAD wrapper with buffered streaming support."""

    SAMPLE_RATE = 16000
    WINDOW_SIZE_SAMPLES = 512  # 32ms at 16kHz
    SPEECH_THRESHOLD = 0.5
    SILENCE_THRESHOLD = 0.35
    MIN_SPEECH_DURATION_MS = 250
    MIN_SILENCE_DURATION_MS = 300
    PRE_SPEECH_PAD_MS = 100
    POST_SPEECH_PAD_MS = 100

    def __init__(self):
        self._model = None
        self._buffer = np.array([], dtype=np.float32)
        self._state: Optional[str] = None  # 'silence' | 'speech'
        self._current_segment_start: Optional[int] = None
        self._silence_start: Optional[int] = None
        self._sample_idx = 0
        self._segment_audio: list = []

    @property
    def model(self):
        if self._model is None:
            self._load_model()
        return self._model

    def _load_model(self):
        import torch
        self._model, _ = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False,
            trust_repo=True,
        )

    def reset(self):
        """Reset state for a new recording session."""
        self._buffer = np.array([], dtype=np.float32)
        self._state = None
        self._current_segment_start = None
        self._silence_start = None
        self._sample_idx = 0
        self._segment_audio = []

    def process_chunk(self, chunk: np.ndarray) -> list[SpeechSegment]:
        """
        Process an incoming audio chunk.
        Returns any completed SpeechSegments.
        """
        segments = []
        self._buffer = np.concatenate([self._buffer, chunk])

        # Process in windows
        while len(self._buffer) >= self.WINDOW_SIZE_SAMPLES:
            window = self._buffer[:self.WINDOW_SIZE_SAMPLES]
            self._buffer = self._buffer[self.WINDOW_SIZE_SAMPLES:]

            speech_prob = self._detect_speech(window)
            window_start_ms = (self._sample_idx / self.SAMPLE_RATE) * 1000
            self._sample_idx += len(window)

            if speech_prob >= self.SPEECH_THRESHOLD:
                if self._state != 'speech':
                    # Speech started
                    self._state = 'speech'
                    self._current_segment_start = max(
                        0,
                        int(self._sample_idx - self.PRE_SPEECH_PAD_MS * self.SAMPLE_RATE / 1000)
                    )
                    self._segment_audio = [window]
                    self._silence_start = None
                else:
                    self._segment_audio.append(window)

            elif speech_prob < self.SILENCE_THRESHOLD and self._state == 'speech':
                if self._silence_start is None:
                    self._silence_start = self._sample_idx
                    self._segment_audio.append(window)

                silence_duration = (self._sample_idx - self._silence_start) / self.SAMPLE_RATE * 1000
                if silence_duration >= self.MIN_SILENCE_DURATION_MS:
                    # Speech ended
                    segment = self._finalize_segment()
                    if segment:
                        segments.append(segment)
                    self._state = 'silence'
                    self._silence_start = None
                    self._segment_audio = []
            else:
                if self._state == 'speech':
                    self._segment_audio.append(window)
                self._silence_start = None

        return segments

    def flush(self) -> Optional[SpeechSegment]:
        """Force-flush: finalize any in-progress speech segment."""
        if self._state == 'speech' and self._segment_audio:
            return self._finalize_segment()
        return None

    def _detect_speech(self, audio: np.ndarray) -> float:
        import torch
        tensor = torch.from_numpy(audio).float()
        with torch.no_grad():
            prob = self.model(tensor, self.SAMPLE_RATE).item()
        return prob

    def _finalize_segment(self) -> Optional[SpeechSegment]:
        if not self._segment_audio or self._current_segment_start is None:
            return None

        audio = np.concatenate(self._segment_audio)
        duration_ms = len(audio) / self.SAMPLE_RATE * 1000

        if duration_ms < self.MIN_SPEECH_DURATION_MS:
            return None

        start_ms = self._current_segment_start / self.SAMPLE_RATE * 1000
        end_ms = self._sample_idx / self.SAMPLE_RATE * 1000

        return SpeechSegment(
            start_ms=start_ms,
            end_ms=end_ms,
            audio=audio,
            confidence=0.9,  # approximate
        )
