import Foundation

/// Rolling preview transcription while the user is still speaking.
///
/// Whisper is not a streaming model: it decodes a fixed buffer in one shot. So we
/// keep the whole recording, and every ~0.7s re-decode only the last `windowSeconds`
/// of it. Segments whose end lands before the last committed point are dropped, which
/// is what turns overlapping decodes into one stable, growing transcript instead of
/// duplicated text. The final transcript still comes from the full decode on stop;
/// this preview exists so long dictation stays referenceable while it happens.
final class LiveTranscriber {
    /// Called on the main queue with the text to display.
    var onUpdate: ((String) -> Void)?

    private let engine: WhisperEngine
    private let language: String
    private let queue = DispatchQueue(label: "com.quickflow.live.transcriber", qos: .userInitiated)

    private var timer: DispatchSourceTimer?
    private var buffer: [Int16] = []
    private var overflow: Int = 0          // samples dropped from the front, ever
    private var finalizedText = ""
    private var finalizedEnd: Double = 0   // absolute seconds, from recording start
    private var lastEmitted = ""
    private var decoding = false
    private var running = false

    private let windowSeconds: Double = 12
    private let minimumSeconds: Double = 1.2
    private let sampleRate: Double = 16000

    init(engine: WhisperEngine, language: String) {
        self.engine = engine
        self.language = language
    }

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.buffer.removeAll(keepingCapacity: true)
            self.overflow = 0
            self.finalizedText = ""
            self.finalizedEnd = 0
            self.lastEmitted = ""

            let source = DispatchSource.makeTimerSource(queue: self.queue)
            source.schedule(deadline: .now() + 0.9, repeating: 0.7, leeway: .milliseconds(120))
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            self.timer = source
        }
    }

    /// Feed freshly captured 16 kHz mono PCM. Safe to call from the audio tap thread.
    func append(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        queue.async {
            guard self.running else { return }
            self.buffer.append(contentsOf: samples)
        }
    }

    /// Show a preview from audio that is already on disk (used by `--dictate` too).
    func stop() {
        queue.async {
            self.running = false
            self.timer?.cancel()
            self.timer = nil
            self.buffer.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - Decode loop

    private func tick() {
        guard running, !decoding else { return }
        let total = buffer.count
        guard Double(total) / sampleRate >= minimumSeconds else { return }

        let windowSamples = min(total, Int(windowSeconds * sampleRate))
        let windowStart = Double(total - windowSamples) / sampleRate + Double(overflow) / sampleRate
        let slice = Array(buffer[(total - windowSamples)...])
        let floats = slice.map { Float($0) / 32768.0 }

        // Silence: whisper happily invents text for a quiet room. Skip the decode.
        var energy: Float = 0
        for value in floats { energy += value * value }
        guard sqrt(energy / Float(floats.count)) > 0.004 else { return }

        decoding = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let segments = (try? self.engine.segments(samples: floats, language: self.language)) ?? []
            self.queue.async {
                self.decoding = false
                self.commit(
                    segments,
                    windowStart: windowStart,
                    windowSeconds: Double(windowSamples) / self.sampleRate
                )
            }
        }
    }

    private func commit(_ segments: [WhisperEngine.PartialSegment], windowStart: Double, windowSeconds: Double) {
        guard running, !segments.isEmpty else { return }
        var text = finalizedText
        var cursor = finalizedEnd
        var tail: [String] = []
        // Never commit audio from the last half second: whisper will happily freeze a
        // half-spoken word into the permanent transcript.
        let safeEnd = windowStart + windowSeconds - 0.5

        for (index, segment) in segments.enumerated() {
            let end = windowStart + segment.end
            let start = windowStart + segment.start
            // Keep the final segment as the live tail so words appear immediately,
            // minus any words that are already on screen from the committed text.
            if index == segments.count - 1 {
                let visible = Self.trimOverlap(segment.text, committed: text)
                if !visible.isEmpty {
                    tail.append(visible)
                }
                continue
            }
            guard end <= safeEnd else { continue }
            guard end > cursor + 0.05 else { continue }
            // A segment straddling the commit point would duplicate what we have.
            if start < cursor - 0.6 { continue }
            text = Self.join(text, segment.text)
            cursor = end
        }

        finalizedText = text
        finalizedEnd = max(finalizedEnd, cursor)

        var tailText = tail.joined(separator: " ")
        if let last = text.last, ".!?".contains(last),
           let first = tailText.first, first.isLowercase {
            tailText = first.uppercased() + tailText.dropFirst()
        }

        let display = Self.join(text, tailText)
        guard !display.isEmpty, display != lastEmitted else { return }
        lastEmitted = display
        DispatchQueue.main.async { self.onUpdate?(display) }
    }

    /// Whisper segments carry no leading space, and often start lowercase mid-sentence.
    /// Join without inventing a space before punctuation; keep one space otherwise.
    private static func join(_ lhs: String, _ rhs: String) -> String {
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !right.isEmpty else { return lhs }
        guard !lhs.isEmpty else { return right }
        if let first = right.first, ",.;:!?)]}".contains(first) {
            return lhs + right
        }
        return lhs + " " + right
    }

    /// Drops the leading words of `tail` that are already visible at the end of
    /// `committed`. Whisper re-times a whole sentence when the rolling window slides,
    /// so without this the last sentence flickers as a duplicate.
    private static func trimOverlap(_ tail: String, committed: String) -> String {
        let tailWords = tail.split(separator: " ")
        guard !tailWords.isEmpty else { return "" }
        let committedWords = committed.split(separator: " ").map(normalized)
        let tailWordsNormalized = tailWords.map(normalized)
        let limit = min(committedWords.count, tailWordsNormalized.count)
        var overlap = 0
        if limit >= 2 {
            for count in stride(from: limit, through: 2, by: -1)
            where committedWords.suffix(count).elementsEqual(tailWordsNormalized.prefix(count)) {
                overlap = count
                break
            }
        }
        return tailWords.dropFirst(overlap).joined(separator: " ")
    }

    private static func normalized(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'…—-"))
    }
}
