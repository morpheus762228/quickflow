import AVFoundation
import Foundation

enum AudioFileDecoder {
    static let sampleRate: Double = 16000
    /// Dictation clips are short; refuse to build a giant buffer for a feature-length file.
    private static let maximumSeconds: Double = 1800

    /// Decodes any file AVFoundation understands into 16 kHz mono Float samples.
    static func floats(at url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw QuickFlowError.audioFormat(error.localizedDescription)
        }

        let source = file.processingFormat
        let requested = AVAudioFrameCount(min(Double(file.length), source.sampleRate * maximumSeconds))
        guard source.sampleRate > 0, source.channelCount > 0, requested > 0 else {
            throw QuickFlowError.audioFormat("the file has no audio")
        }

        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: requested) else {
            throw QuickFlowError.audioFormat("could not allocate an audio buffer")
        }
        do {
            try file.read(into: input)
        } catch {
            throw QuickFlowError.audioFormat(error.localizedDescription)
        }
        guard input.frameLength > 0 else {
            throw QuickFlowError.audioFormat("the file has no audio")
        }

        // Fast path: our own recorder already writes 16 kHz mono float-compatible PCM.
        if abs(source.sampleRate - sampleRate) < 0.5,
           source.channelCount == 1,
           source.commonFormat == .pcmFormatFloat32,
           !source.isInterleaved,
           let channel = input.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(input.frameLength)))
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw QuickFlowError.audioFormat("unsupported output format")
        }
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw QuickFlowError.audioFormat("could not convert \(Int(source.sampleRate)) Hz audio")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

        let expected = Double(input.frameLength) * sampleRate / source.sampleRate
        guard let output = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: AVAudioFrameCount(expected.rounded(.up)) + 4096
        ) else {
            throw QuickFlowError.audioFormat("could not allocate an output buffer")
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }

        if status == .error {
            throw QuickFlowError.audioFormat(conversionError?.localizedDescription ?? "conversion failed")
        }
        guard output.frameLength > 0, let channel = output.floatChannelData?[0] else {
            throw QuickFlowError.audioFormat("conversion produced no audio")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
