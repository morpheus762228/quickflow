import Foundation

enum WAVWriter {
    static func write(samples: [Int16], sampleRate: UInt32 = 16000, to url: URL) throws {
        var data = Data(capacity: 44 + samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(&data, UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(&data, 16)
        appendUInt16(&data, 1)
        appendUInt16(&data, 1)
        appendUInt32(&data, sampleRate)
        appendUInt32(&data, sampleRate * 2)
        appendUInt16(&data, 2)
        appendUInt16(&data, 16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(&data, UInt32(samples.count * 2))
        for sample in samples {
            appendUInt16(&data, UInt16(bitPattern: sample))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

enum WAVReader {
    struct Audio {
        let samples: [Float]
        let sampleRate: Int
        let channels: Int
    }

    static func readPCM16(_ url: URL) throws -> Audio {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw QuickFlowError.audioFormat("file is too small")
        }
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw QuickFlowError.audioFormat("not a WAV file")
        }

        var offset = 12
        var formatCode: UInt16 = 0
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bits: UInt16 = 0
        var payload: Data?

        while offset + 8 <= data.count {
            let identifier = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32(data, offset + 4))
            let body = offset + 8
            if identifier == "fmt ", chunkSize >= 16, body + 16 <= data.count {
                formatCode = readUInt16(data, body)
                channels = readUInt16(data, body + 2)
                sampleRate = readUInt32(data, body + 4)
                bits = readUInt16(data, body + 14)
            } else if identifier == "data" {
                let end = min(data.count, body + chunkSize)
                payload = data.subdata(in: body..<end)
            }
            offset = body + chunkSize + (chunkSize % 2)
        }

        guard formatCode == 1 else {
            throw QuickFlowError.audioFormat("only uncompressed PCM is supported")
        }
        guard bits == 16 else {
            throw QuickFlowError.audioFormat("expected 16-bit audio, found \(bits)-bit")
        }
        guard channels > 0, sampleRate > 0 else {
            throw QuickFlowError.audioFormat("invalid format header")
        }
        guard let payload, !payload.isEmpty else {
            throw QuickFlowError.audioFormat("no audio data")
        }

        let frameCount = payload.count / (Int(channels) * 2)
        var samples = [Float](repeating: 0, count: frameCount)
        payload.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            for frame in 0..<frameCount {
                var sum: Int32 = 0
                for channel in 0..<Int(channels) {
                    sum += Int32(Int16(littleEndian: buffer[frame * Int(channels) + channel]))
                }
                samples[frame] = Float(sum) / Float(Int(channels)) / 32768.0
            }
        }

        return Audio(samples: samples, sampleRate: Int(sampleRate), channels: Int(channels))
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination, from: offset..<offset + 4)
        }
        return UInt32(littleEndian: value)
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination, from: offset..<offset + 2)
        }
        return UInt16(littleEndian: value)
    }
}
