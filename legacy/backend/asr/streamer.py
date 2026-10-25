"""
Streaming ASR with Prebuffer
============================
Continuous audio capture with VAD-based segmentation,
prebuffer for zero-latency start, and faster-whisper transcription.
"""

import os
import time
import threading
import subprocess
import tempfile
import wave
from dataclasses import dataclass, field
from typing import Callable, Optional

import numpy as np

from .vad import VAD, SpeechSegment


@dataclass
class TranscriptionResult:
    text: str
    segment_start_ms: float
    segment_end_ms: float
    latency_ms: float
    is_partial: bool = False
    confidence: float = 0.0


class StreamingASR:
    """
    Continuous speech-to-text with:
    - Prebuffer: always capturing last N seconds so start is instant
    - VAD segmentation: detects speech boundaries
    - faster-whisper transcription: runs on each completed segment
    - Partial results: streams interim text as it arrives
    """

    PREBUFFER_SECONDS = 3.0
    SAMPLE_RATE = 16000
    CHANNELS = 1
    CHUNK_SAMPLES = 1024  # 64ms at 16kHz

    def __init__(
        self,
        model_size: str = "small",
        device: str = "auto",
        compute_type: str = "int8",
        on_partial: Optional[Callable[[TranscriptionResult], None]] = None,
        on_segment: Optional[Callable[[TranscriptionResult], None]] = None,
    ):
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.on_partial = on_partial
        self.on_segment = on_segment

        self._vad = VAD()
        self._model = None
        self._recording = False
        self._thread: Optional[threading.Thread] = None
        self._buffer: list[np.ndarray] = []
        self._segments: list[SpeechSegment] = []
        self._partial_text: str = ""
        self._stop_event = threading.Event()

    @property
    def model(self):
        if self._model is None:
            from faster_whisper import WhisperModel
            self._model = WhisperModel(
                self.model_size,
                device=self.device,
                compute_type=self.compute_type,
                cpu_threads=4,
                num_workers=1,
            )
        return self._model

    def start(self):
        """Start continuous recording with prebuffer."""
        self._buffer = []
        self._segments = []
        self._partial_text = ""
        self._stop_event.clear()
        self._recording = True
        self._thread = threading.Thread(target=self._record_loop, daemon=True)
        self._thread.start()

    def stop(self) -> list[TranscriptionResult]:
        """Stop recording, transcribe all pending segments, return all results."""
        self._recording = False
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=3.0)
            self._thread = None

        # Flush VAD for any trailing speech
        final_segment = self._vad.flush()
        if final_segment:
            self._segments.append(final_segment)

        # Transcribe all segments
        results = []
        for seg in self._segments:
            result = self._transcribe_segment(seg)
            if result:
                results.append(result)
                if self.on_segment:
                    self.on_segment(result)
        return results

    def get_partial_text(self) -> str:
        """Return the current partial transcription (non-blocking)."""
        return self._partial_text

    def _record_loop(self):
        """Background thread: capture audio and run VAD."""
        import sounddevice as sd

        # Prebuffer: circular buffer of last N seconds
        prebuffer_size = int(self.PREBUFFER_SECONDS * self.SAMPLE_RATE)
        prebuffer = np.zeros(prebuffer_size, dtype=np.float32)
        prebuffer_idx = 0
        prebuffer_full = False

        def callback(indata, frames, t, status):
            nonlocal prebuffer_idx, prebuffer_full

            if status:
                return

            chunk = indata[:, 0].astype(np.float32)

            # Update prebuffer
            chunk_len = len(chunk)
            end_idx = prebuffer_idx + chunk_len
            if end_idx <= prebuffer_size:
                prebuffer[prebuffer_idx:end_idx] = chunk
            else:
                # Wrap around
                first_part = prebuffer_size - prebuffer_idx
                prebuffer[prebuffer_idx:] = chunk[:first_part]
                prebuffer[:chunk_len - first_part] = chunk[first_part:]
                prebuffer_full = True
            prebuffer_idx = (prebuffer_idx + chunk_len) % prebuffer_size

            # Run VAD
            segments = self._vad.process_chunk(chunk)
            if segments:
                # Prepend prebuffer context to each segment
                for seg in segments:
                    seg = self._attach_prebuffer(seg, prebuffer, prebuffer_full, prebuffer_idx, prebuffer_size)
                    self._segments.append(seg)
                    # Transcribe in background
                    t = threading.Thread(target=self._transcribe_and_notify, args=(seg,), daemon=True)
                    t.start()

        try:
            with sd.InputStream(
                samplerate=self.SAMPLE_RATE,
                channels=1,
                dtype='float32',
                callback=callback,
                blocksize=self.CHUNK_SAMPLES,
            ):
                while not self._stop_event.is_set():
                    time.sleep(0.05)
        except Exception as e:
            print(f"[ASR] Recording error: {e}")

    def _attach_prebuffer(
        self, seg: SpeechSegment, prebuffer: np.ndarray,
        full: bool, idx: int, size: int
    ) -> SpeechSegment:
        """Attach prebuffer audio before the detected speech segment."""
        if not full:
            # Prebuffer not full yet, just use what we have
            pre_audio = prebuffer[:idx]
        else:
            # Read prebuffer in order (circular)
            pre_audio = np.concatenate([prebuffer[idx:], prebuffer[:idx]])

        # Take only the last PREBUFFER_SECONDS
        pre_samples = int(self.PREBUFFER_SECONDS * self.SAMPLE_RATE)
        if len(pre_audio) > pre_samples:
            pre_audio = pre_audio[-pre_samples:]

        seg.audio = np.concatenate([pre_audio, seg.audio])
        seg.start_ms = max(0, seg.start_ms - self.PREBUFFER_SECONDS * 1000)
        return seg

    def _transcribe_and_notify(self, seg: SpeechSegment):
        """Transcribe a segment in a background thread, notify callbacks."""
        result = self._transcribe_segment(seg)
        if result and result.text:
            self._partial_text += " " + result.text
            if self.on_partial:
                self.on_partial(result)
            if self.on_segment:
                self.on_segment(result)

    def _transcribe_segment(self, seg: SpeechSegment) -> Optional[TranscriptionResult]:
        """Run faster-whisper on a speech segment."""
        t0 = time.time()
        try:
            # Save to temp WAV file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
                wav_path = f.name
                with wave.open(f, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)  # 16-bit
                    wf.setframerate(self.SAMPLE_RATE)
                    audio_16 = (seg.audio * 32767).astype(np.int16)
                    wf.writeframes(audio_16.tobytes())

            segments, info = self.model.transcribe(
                wav_path,
                beam_size=5,
                language="en",
                vad_filter=False,  # We already did VAD
                condition_on_previous_text=True,
            )

            text = " ".join(s.text.strip() for s in segments if s.text.strip())
            os.unlink(wav_path)

            if not text:
                return None

            latency = (time.time() - t0) * 1000
            return TranscriptionResult(
                text=text,
                segment_start_ms=seg.start_ms,
                segment_end_ms=seg.end_ms,
                latency_ms=latency,
                confidence=info.language_probability if info else 0.0,
            )
        except Exception as e:
            print(f"[ASR] Transcription error: {e}")
            return None


# ── Fallback: non-streaming mode (uses current ffmpeg + whisper) ──

class BatchASR:
    """Simpler record-then-transcribe mode for when streaming deps aren't ready."""

    def __init__(self, model_size: str = "small"):
        self.model_size = model_size

    def transcribe_file(self, audio_path: str, context: str = "") -> str:
        """Transcribe a WAV file using whisper CLI (fallback)."""
        import subprocess
        whisper = self._find_whisper()
        if not whisper:
            print("[BatchASR] ERROR: whisper not found. Run: pip3 install openai-whisper", file=sys.stderr)
            return ""
        cmd = [whisper, audio_path, "--model", self.model_size, "--output_dir", "/tmp", "--output_format", "txt"]
        if context:
            cmd += ["--initial_prompt", context]
        subprocess.run(cmd, capture_output=True, timeout=60)
        txt_path = audio_path.replace(".wav", ".txt")
        if os.path.exists(txt_path):
            with open(txt_path) as f:
                return f.read().strip()
        return ""

    @staticmethod
    def _find_whisper() -> str:
        """Find the whisper CLI in common locations."""
        # Check PATH first
        result = subprocess.run(["which", "whisper"], capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        # Check common user pip install locations
        for py_ver in ["3.9", "3.10", "3.11", "3.12", "3.13"]:
            candidate = os.path.expanduser(f"~/Library/Python/{py_ver}/bin/whisper")
            if os.path.isfile(candidate):
                return candidate
        return ""
