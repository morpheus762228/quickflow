import Foundation
import AVFoundation
import CoreAudio

struct Recording {
    let url: URL
    let duration: TimeInterval
    let rms: Float
    let peak: Float
    let sampleCount: Int

    var isSilent: Bool {
        rms < 0.0016 || peak < 0.01
    }
}

final class AudioRecorder {
    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Every captured chunk as 16 kHz mono PCM, for the live subtitle preview.
    var onSamples: (([Int16]) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    private var converter: AVAudioConverter?
    private var samples: [Int16] = []
    private var recording = false
    private var startedAt: Date?
    private var limitTimer: Timer?
    private var levelAccumulator: Float = 0
    private var levelSamples = 0
    private var lastLevelEmission: CFAbsoluteTime = 0
    private var totalSquares: Double = 0
    private var peak: Float = 0
    private var sourceFormat: AVAudioFormat?

    private let maximumDuration: TimeInterval = 300

    func start(deviceUID: String?) throws {
        guard !recording else { return }
        guard Permissions.microphone == .granted else {
            throw QuickFlowError.recordingFailed("microphone permission has not been granted")
        }
        guard let device = (deviceUID?.isEmpty == false)
            ? AudioDevices.device(uid: deviceUID ?? "")
            : AudioDevices.preferredInput() else {
            throw QuickFlowError.noMicrophone
        }

        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            throw QuickFlowError.audioEngine("input node has no audio unit")
        }

        let defaultDevice = AudioDevices.defaultInput()
        if device.id != defaultDevice?.id {
            var deviceID = device.id
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw QuickFlowError.audioEngine("could not select \(device.name) (error \(status))")
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate >= 8000, format.channelCount > 0 else {
            throw QuickFlowError.noMicrophone
        }
        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            throw QuickFlowError.audioEngine("could not create a 16 kHz converter")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        self.converter = converter
        self.sourceFormat = format

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        totalSquares = 0
        peak = 0
        levelAccumulator = 0
        levelSamples = 0
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        recording = true
        startedAt = Date()
        do {
            try engine.start()
        } catch {
            recording = false
            input.removeTap(onBus: 0)
            self.converter = nil
            throw QuickFlowError.audioEngine(error.localizedDescription)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.limitTimer = Timer.scheduledTimer(withTimeInterval: self.maximumDuration, repeats: false) { [weak self] _ in
                guard let self, self.recording else { return }
                self.onLimitReached?()
            }
        }
    }

    func stop() -> Recording? {
        guard recording else { return nil }
        recording = false
        limitTimer?.invalidate()
        limitTimer = nil

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        let squares = totalSquares
        let capturedPeak = peak
        lock.unlock()

        converter = nil
        sourceFormat = nil

        guard !captured.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickflow-\(UUID().uuidString).wav")
        do {
            try WAVWriter.write(samples: captured, to: url)
        } catch {
            return nil
        }

        let duration = Double(captured.count) / 16000.0
        let rms = Float(sqrt(squares / Double(captured.count)))
        return Recording(
            url: url,
            duration: duration,
            rms: rms,
            peak: capturedPeak,
            sampleCount: captured.count
        )
    }

    func cancel() {
        guard recording else { return }
        recording = false
        limitTimer?.invalidate()
        limitTimer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        converter = nil
        sourceFormat = nil
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    var isRecording: Bool { recording }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard recording, let converter else { return }
        let ratio = 16000.0 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            if let conversionError {
                DispatchQueue.main.async { [weak self] in
                    self?.onError?(QuickFlowError.audioEngine(conversionError.localizedDescription))
                }
            }
            return
        }

        guard output.frameLength > 0, let channel = output.int16ChannelData?[0] else { return }
        let count = Int(output.frameLength)
        var squares: Double = 0
        var localPeak: Float = 0
        var localLevel: Float = 0
        for index in 0..<count {
            let value = Float(channel[index]) / 32768.0
            squares += Double(value * value)
            localPeak = max(localPeak, abs(value))
            localLevel += abs(value)
        }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
        totalSquares += squares
        peak = max(peak, localPeak)
        levelAccumulator += localLevel
        levelSamples += count
        let now = CFAbsoluteTimeGetCurrent()
        var emitLevel: Float?
        if now - lastLevelEmission >= 0.033 {
            lastLevelEmission = now
            let mean = levelAccumulator / Float(max(1, levelSamples))
            levelAccumulator = 0
            levelSamples = 0
            let decibels = 20 * log10(max(mean, 0.00001))
            let normalized = max(0, min(1, (decibels + 55) / 55))
            emitLevel = Float(sqrt(normalized))
        }
        lock.unlock()

        if let onSamples {
            onSamples(chunk)
        }

        if let emitLevel {
            DispatchQueue.main.async { [weak self] in
                self?.onLevel?(emitLevel)
            }
        }
    }
}
