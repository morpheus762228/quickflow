import Foundation

enum QuickFlowError: LocalizedError {
    case modelMissing(String)
    case modelLoadFailed(String)
    case noMicrophone
    case audioEngine(String)
    case recordingFailed(String)
    case transcriptionFailed(String)
    case audioFormat(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let path):
            return "No speech model found at \(path)."
        case .modelLoadFailed(let path):
            return "Could not load the speech model at \(path)."
        case .noMicrophone:
            return "No microphone is available. Connect an input device and try again."
        case .audioEngine(let message):
            return "Audio engine error: \(message)"
        case .recordingFailed(let message):
            return "Could not record audio: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .audioFormat(let message):
            return "Unsupported audio: \(message)"
        }
    }
}

struct Transcript {
    let text: String
    let confidence: Float
    let noSpeechProbability: Float
    let language: String
    let inferenceTime: TimeInterval
    let audioDuration: TimeInterval

    var realTimeFactor: Double {
        audioDuration > 0 ? inferenceTime / audioDuration : 0
    }
}

/// Thin, resident wrapper around whisper.cpp. Create once, reuse for every dictation.
final class WhisperEngine {
    /// whisper.cpp and ggml log to stderr by default, which floods a GUI app's
    /// console and buries real errors. Off unless someone asks for it.
    nonisolated(unsafe) static var verboseLogging = false

    private static let installLogHandler: Void = {
        whisper_log_set({ _, text, _ in
            guard WhisperEngine.verboseLogging, let text else { return }
            fputs(text, stderr)
        }, nil)
    }()

    private var ctx: OpaquePointer?
    let modelPath: String
    private(set) var loadDuration: TimeInterval = 0
    /// whisper.cpp contexts are not re-entrant: a live preview decode and the final
    /// decode can arrive at the same moment, so every whisper_full call serialises here.
    private let decodeLock = NSLock()

    struct PartialSegment {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    init(modelPath: String) throws {
        Self.installLogHandler.self
        self.modelPath = modelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw QuickFlowError.modelMissing(modelPath)
        }

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true

        let start = CFAbsoluteTimeGetCurrent()
        guard let context = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw QuickFlowError.modelLoadFailed(modelPath)
        }
        ctx = context
        loadDuration = CFAbsoluteTimeGetCurrent() - start
    }

    deinit {
        if let ctx {
            whisper_free(ctx)
        }
    }

    var threadCount: Int {
        max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    /// Run one throwaway pass so Metal kernels and the graph are compiled before
    /// the user's first real dictation. Without this the first transcript pays a
    /// one-time cost of several hundred milliseconds.
    func warmUp() {
        guard let ctx else { return }
        decodeLock.lock()
        defer { decodeLock.unlock() }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(threadCount)
        params.no_context = true
        params.no_timestamps = true
        params.single_segment = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.suppress_blank = true
        params.temperature = 0.0
        params.no_speech_thold = 0.9

        let silence = [Float](repeating: 0, count: 16000)
        "en".withCString { language in
            params.language = language
            _ = whisper_full(ctx, params, silence, Int32(silence.count))
        }
        whisper_reset_timings(ctx)
    }

    func transcribe(url: URL, language: String?, prompt: String?, translate: Bool = false) throws -> Transcript {
        let samples = try AudioFileDecoder.floats(at: url)
        return try transcribe(samples: samples, language: language, prompt: prompt, translate: translate)
    }

    func transcribe(samples: [Float], language: String?, prompt: String?, translate: Bool = false) throws -> Transcript {
        guard let ctx else {
            throw QuickFlowError.transcriptionFailed("model is not loaded")
        }
        guard samples.count >= 1600 else {
            throw QuickFlowError.transcriptionFailed("audio is too short")
        }

        decodeLock.lock()
        defer { decodeLock.unlock() }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(threadCount)
        params.translate = translate
        params.no_context = true
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0.0
        params.temperature_inc = 0.2
        params.no_speech_thold = 0.6
        params.entropy_thold = 2.4
        params.logprob_thold = -1.0
        params.audio_ctx = 0
        params.max_len = 0

        var languagePointer: UnsafeMutablePointer<CChar>?
        if let language, !language.isEmpty, language != "auto" {
            languagePointer = strdup(language)
        }
        var promptPointer: UnsafeMutablePointer<CChar>?
        if let prompt, !prompt.isEmpty {
            promptPointer = strdup(prompt)
        }
        defer {
            free(languagePointer)
            free(promptPointer)
        }

        params.language = UnsafePointer(languagePointer)
        params.initial_prompt = UnsafePointer(promptPointer)

        let start = CFAbsoluteTimeGetCurrent()
        let result = whisper_full(ctx, params, samples, Int32(samples.count))
        guard result == 0 else {
            throw QuickFlowError.transcriptionFailed("whisper_full returned \(result)")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        var text = ""
        var probabilities: [Float] = []
        var noSpeech: Float = 0
        let segments = Int(whisper_full_n_segments(ctx))
        for index in 0..<max(0, segments) {
            if let chunk = whisper_full_get_segment_text(ctx, Int32(index)) {
                text += String(cString: chunk)
            }
            noSpeech = max(noSpeech, whisper_full_get_segment_no_speech_prob(ctx, Int32(index)))
            let tokenCount = Int(whisper_full_n_tokens(ctx, Int32(index)))
            if tokenCount > 0 {
                for token in 0..<tokenCount {
                    probabilities.append(whisper_full_get_token_p(ctx, Int32(index), Int32(token)))
                }
            }
        }

        let confidence = probabilities.isEmpty ? 0 : probabilities.reduce(0, +) / Float(probabilities.count)
        let languageID = whisper_full_lang_id(ctx)
        let languageName: String
        if languageID >= 0, let code = whisper_lang_str(languageID) {
            languageName = String(cString: code)
        } else {
            languageName = language ?? "en"
        }

        return Transcript(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence,
            noSpeechProbability: noSpeech,
            language: languageName,
            inferenceTime: elapsed,
            audioDuration: Double(samples.count) / 16000.0
        )
    }

    /// Decode a short rolling window for the live subtitle preview. Timestamps are
    /// required here so the caller can tell which segments it already committed.
    /// Deliberately cheaper than `transcribe`: fewer threads, no prompt, no retries.
    func segments(samples: [Float], language: String?) throws -> [PartialSegment] {
        guard let ctx else {
            throw QuickFlowError.transcriptionFailed("model is not loaded")
        }
        guard samples.count >= 3200 else { return [] }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.no_context = true
        params.no_timestamps = false
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_realtime = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0.0
        params.temperature_inc = 0.0
        params.no_speech_thold = 0.6
        params.entropy_thold = 2.4
        params.logprob_thold = -1.0
        params.audio_ctx = 0
        params.max_len = 0

        let code = (language?.isEmpty == false && language != "auto") ? language! : "en"

        decodeLock.lock()
        defer { decodeLock.unlock() }

        let result = code.withCString { pointer -> Int32 in
            params.language = pointer
            return whisper_full(ctx, params, samples, Int32(samples.count))
        }
        guard result == 0 else {
            throw QuickFlowError.transcriptionFailed("whisper_full returned \(result)")
        }

        var output: [PartialSegment] = []
        let count = Int(whisper_full_n_segments(ctx))
        output.reserveCapacity(max(0, count))
        for index in 0..<max(0, count) {
            guard let chunk = whisper_full_get_segment_text(ctx, Int32(index)) else { continue }
            let text = String(cString: chunk).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = Double(whisper_full_get_segment_t0(ctx, Int32(index))) / 100.0
            let end = Double(whisper_full_get_segment_t1(ctx, Int32(index))) / 100.0
            output.append(PartialSegment(text: text, start: start, end: end))
        }
        return output
    }
}
