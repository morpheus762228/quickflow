# Legacy: QuickFlow 1.0

This directory is the 1.0 implementation, archived for reference. **It is not part of the build and is not maintained.** `build.sh` ignores it.

## What it was

A Swift menu bar shell (`main.swift`) that drove a Python orchestrator (`backend/server.py`) over a local process boundary. The Python side was the interesting part, and it aimed considerably higher than what 3.0 ships:

| Module | Intent |
| --- | --- |
| `asr/streamer.py` | Continuous capture with VAD segmentation, a prebuffer for zero-latency starts, and `faster-whisper` decoding |
| `asr/vad.py` | Voice activity detection to cut audio at speech boundaries |
| `context/injector.py` | Read surrounding text from the active app to bias transcription and choose a style |
| `llm/pipeline.py` | Two stages: clean ASR artifacts, then transform into the requested style |
| `learning/adapter.py` | SQLite store of user corrections, replayed as few-shot examples |
| `budget.py` | End-to-end latency budget with graceful degradation when a stage overruns |
| `transcribe.sh`, `setup.sh` | Virtualenv bootstrap and a CLI shim |
| `DISTRIBUTION-1.0.md` | The 1.0 packaging notes |

`requirements.txt` shows how much of it was aspirational: `faster-whisper`, `sounddevice`, `torch`, and `llama-cpp-python` are all commented out, and the only uncommented dependency is `openai-whisper`.

## Why it was replaced

The 1.0 design paid a fixed cost on every dictation: Python interpreter startup, model load, and a process handoff through temporary WAV files. It also needed a virtualenv on the user's machine, and the LLM stages wanted a local model plus screen context — which is a much larger privacy surface than "audio goes in, text comes out."

3.0 keeps the parts that mattered and drops the machinery:

| 1.0 idea | 3.0 form |
| --- | --- |
| Screen context to pick a style | Frontmost app's bundle identifier → `TextCleaner.Style` |
| LLM cleanup pass | Deterministic `TextCleaner` + `SmartFormatter` rules, no model call |
| Correction learning | A custom-vocabulary field passed as whisper's `initial_prompt` |
| Latency budget with degradation | Model and Metal warm-up at launch; one decode, no fallback chain |
| Streaming ASR | Rolling-window re-decode for live subtitles, final decode on stop |

The result is one process, no per-take startup cost, no disk I/O for audio, and no networking surface.

## Running it

Don't, unless you are curious and have an afternoon. If you must:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python backend/server.py start   # and `stop` in another shell
```

Expect it to be slow, to want a model path configured by hand, and to paste through the same Accessibility permission that 3.0 uses. The code is here to document where the project came from, not to work.
