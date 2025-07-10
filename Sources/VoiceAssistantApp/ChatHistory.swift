import Foundation

struct ChatHistoryItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let recordedAudio: Data // Store raw audio data
    let transcription: String
    let aiResponse: String
    let audioSampleRate: Double
    let audioDuration: TimeInterval
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         recordedAudio: Data,
         transcription: String,
         aiResponse: String,
         audioSampleRate: Double = 16000.0,
         audioDuration: TimeInterval = 0) {
        self.id = id
        self.timestamp = timestamp
        self.recordedAudio = recordedAudio
        self.transcription = transcription
        self.aiResponse = aiResponse
        self.audioSampleRate = audioSampleRate
        self.audioDuration = audioDuration
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var audioSamples: [Float] {
        // Convert stored Data back to Float array for playback
        let count = recordedAudio.count / MemoryLayout<Float>.size
        return recordedAudio.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let floatPointer = baseAddress.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: floatPointer, count: count))
        }
    }
}

// Extension to convert audio samples to Data for storage
extension Array where Element == Float {
    var audioData: Data {
        return self.withUnsafeBytes { buffer in
            Data(buffer)
        }
    }
}

extension Array where Element == Int16 {
    var audioData: Data {
        // Convert Int16 to Float for consistent storage with consistent divisor
        let floatArray = self.map { sample -> Float in
            return Float(sample) / 32768.0  // Use consistent divisor to avoid DC bias
        }
        return floatArray.audioData
    }
}