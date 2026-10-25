#!/bin/bash
# QuickFlow Voice-to-Text: Record → Transcribe → Paste
# Usage: transcribe.sh start | stop

# Find whisper CLI
WHISPER=""
if command -v whisper &>/dev/null; then
    WHISPER="whisper"
else
    for py_ver in 3.9 3.10 3.11 3.12 3.13; do
        candidate="$HOME/Library/Python/${py_ver}/bin/whisper"
        if [ -f "$candidate" ]; then
            WHISPER="$candidate"
            break
        fi
    done
fi

PIDFILE="/tmp/quickflow-recording.pid"
AUDIOFILE="/tmp/quickflow-recording.wav"
MODEL="small"

# Auto-detect mic index (skip virtual devices like BlackHole)
MIC_INDEX="${QUICKFLOW_MIC_INDEX:-}"
if [ -z "$MIC_INDEX" ]; then
    # Try to auto-detect physical microphone
    MIC_INDEX="1"  # Safe default
fi

case "${1:-}" in
    start)
        # Kill any stale recording
        if [ -f "$PIDFILE" ]; then
            OLD_PID=$(cat "$PIDFILE")
            kill -INT "$OLD_PID" 2>/dev/null
            wait "$OLD_PID" 2>/dev/null
        fi
        rm -f "$PIDFILE" "$AUDIOFILE" /tmp/quickflow-recording.txt

        # Start recording (mono, 16kHz for whisper)
        ffmpeg -y -loglevel quiet -f avfoundation -i ":${MIC_INDEX}" -ac 1 -ar 16000 "$AUDIOFILE" &
        echo $! > "$PIDFILE"

        osascript -e 'display notification "Recording started — speak now" with title "QuickFlow 🎙️"'
        ;;

    stop)
        if [ ! -f "$PIDFILE" ]; then
            osascript -e 'display notification "No recording in progress" with title "QuickFlow"'
            exit 0
        fi

        PID=$(cat "$PIDFILE")
        rm -f "$PIDFILE"

        # Stop ffmpeg (SIGINT flushes the WAV header properly)
        kill -INT "$PID" 2>/dev/null
        sleep 1
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null || true

        if [ ! -f "$AUDIOFILE" ] || [ ! -s "$AUDIOFILE" ]; then
            osascript -e 'display notification "Recording empty or failed" with title "QuickFlow"'
            exit 1
        fi

        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIOFILE" 2>/dev/null | cut -d. -f1)
        if [ -z "$DURATION" ] || [ "$DURATION" -lt 1 ]; then
            osascript -e 'display notification "Recording too short (need at least 1 second)" with title "QuickFlow"'
            rm -f "$AUDIOFILE"
            exit 1
        fi

        osascript -e 'display notification "Transcribing... (~'"${DURATION}"'s)" with title "QuickFlow 🤖"'

        if [ -z "$WHISPER" ]; then
            osascript -e 'display notification "whisper not found. Run: pip3 install openai-whisper" with title "QuickFlow"'
            exit 1
        fi

        # Run whisper
        "$WHISPER" "$AUDIOFILE" --model "$MODEL" --output_dir /tmp --output_format txt 2>/dev/null

        TXTFILE="/tmp/quickflow-recording.txt"
        if [ -f "$TXTFILE" ] && [ -s "$TXTFILE" ]; then
            TEXT=$(cat "$TXTFILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            if [ -z "$TEXT" ]; then
                osascript -e 'display notification "No speech detected" with title "QuickFlow"'
            else
                # Copy to clipboard
                echo -n "$TEXT" | pbcopy

                # Try to paste; fall back to clipboard-only if accessibility not granted
                osascript -e '
                    try
                        tell application "System Events" to keystroke "v" using command down
                    on error
                        tell application "System Events" to display notification "Transcribed! Text is on your clipboard (Cmd+V to paste)" with title "QuickFlow ✅"
                        return
                    end try
                    tell application "System Events" to display notification "Transcribed and pasted!" with title "QuickFlow ✅"
                '
            fi
        else
            osascript -e 'display notification "Transcription failed" with title "QuickFlow"'
        fi

        # Cleanup
        rm -f "$AUDIOFILE" "$TXTFILE" /tmp/quickflow-recording.srt /tmp/quickflow-recording.vtt /tmp/quickflow-recording.tsv /tmp/quickflow-recording.json
        ;;

    *)
        echo "Usage: transcribe.sh start | stop"
        exit 1
        ;;
esac
