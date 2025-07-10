import Foundation
@preconcurrency import SwiftWhisper
import Combine
import AVFoundation

@MainActor
class SpeechToTextManager: ObservableObject {
    @Published var transcriptionText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var lastError: String?
    @Published var streamingSegments: [TranscriptionSegment] = []
    @Published var audioQualityStats: AudioQualityStats?
    
    private var whisper: Whisper?
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000.0 // ESP32 sends 16kHz audio
    private let minimumAudioLength: Int = 8000 // 0.5 second minimum for transcription
    
    // Audio capture for history
    private var capturedAudioBuffer: [Float] = []
    var lastCapturedAudio: [Float] {
        return capturedAudioBuffer
    }
    
    // Store raw unprocessed audio for debugging
    private var rawAudioBuffer: [Float] = []
    var lastRawAudio: [Float] {
        return rawAudioBuffer
    }
    
    // Whisper instance synchronization
    private var isWhisperBusy: Bool = false
    private let whisperQueue = DispatchQueue(label: "whisper.transcription", qos: .userInitiated)
    
    struct TranscriptionSegment {
        let id = UUID()
        let text: String
        let startTime: Int
        let endTime: Int
        let confidence: Float
        var isPartial: Bool = false
    }
    
    struct AudioQualityStats {
        let sampleCount: Int
        let durationSeconds: Double
        let maxAmplitude: Float
        let avgAmplitude: Float
        let rmsLevel: Float
        let timestamp: Date
        
        var qualityDescription: String {
            if maxAmplitude < 0.01 {
                return "Very Low"
            } else if maxAmplitude < 0.1 {
                return "Low"
            } else if maxAmplitude < 0.5 {
                return "Good"
            } else if maxAmplitude < 0.95 {
                return "High"
            } else {
                return "Clipping"
            }
        }
        
        var noiseLevel: String {
            let snr = maxAmplitude / max(avgAmplitude, 0.001)
            if snr > 10 {
                return "Low Noise"
            } else if snr > 5 {
                return "Medium Noise"
            } else {
                return "High Noise"
            }
        }
    }
    
    init() {
        loadWhisperModel()
        // Reset busy flag on initialization
        isWhisperBusy = false
    }
    
    private func loadWhisperModel() {
        lastError = nil
        
        // Get path to the bundled model file
        guard let modelPath = getModelPath() else {
            Task { @MainActor in
                self.lastError = "Could not find Whisper model file in bundle"
            }
            return
        }
        
        // Load the Whisper model on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Create Whisper params with English language forced
            let whisperParams = WhisperParams(strategy: .greedy)
            whisperParams.language = .english
            whisperParams.no_speech_thold = 0.1  // Lower threshold for speech detection
            whisperParams.temperature = 0.0     // More deterministic output
            
            let whisperModel = Whisper(fromFileURL: URL(fileURLWithPath: modelPath), withParams: whisperParams)
            
            Task { @MainActor in
                self.whisper = whisperModel
                self.isModelLoaded = true
                print("STT: Whisper model loaded")
            }
        }
    }
    
    private func getModelPath() -> String? {
        // Try different possible locations for the model file
        let possiblePaths = [
            // Resource bundle path
            Bundle.main.path(forResource: "ggml-base", ofType: "bin"),
            // Relative to executable
            "./Sources/VoiceAssistantApp/Resources/ggml-base.bin",
            // Absolute path for development
            "/Users/jbutler/git/home-assistant-voice-pe/VoiceAssistantApp/Sources/VoiceAssistantApp/Resources/ggml-base.bin"
        ]
        
        for path in possiblePaths {
            if let path = path, FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Audio Processing
    
    func processAudioSamples(_ samples: [Int16]) {
        // First, store raw unmodified samples converted to Float32 with standard conversion
        let rawFloatSamples = samples.map { Float($0) / 32768.0 }
        rawAudioBuffer.append(contentsOf: rawFloatSamples)
        
        // Convert Int16 samples to Float32 normalized to [-1.0, 1.0]
        // Use consistent divisor to avoid DC bias
        let floatSamples = samples.map { sample -> Float in
            // Use standard conversion with slight headroom for safety
            let floatValue = Float(sample) / 36000.0  // Balanced conversion: preserves levels but prevents clipping
            
            // Check for NaN, infinity, or invalid values
            if floatValue.isNaN || floatValue.isInfinite {
                return 0.0
            }
            // Clamp to valid range
            return max(-0.9, min(0.9, floatValue))
        }
        
        // Minimal processing - just remove DC offset if significant
        if !floatSamples.isEmpty {
            let dcOffset = floatSamples.reduce(0, +) / Float(floatSamples.count)
            
            // Only remove DC offset if it's significant (> 0.05)
            if abs(dcOffset) > 0.05 {
                let dcCorrectedSamples = floatSamples.map { $0 - dcOffset }
                audioBuffer.append(contentsOf: dcCorrectedSamples)
            } else {
                // Use original samples if DC offset is minimal
                audioBuffer.append(contentsOf: floatSamples)
            }
        }
    }
    
    func startRecording() {
        guard isModelLoaded else {
            lastError = "Whisper model not loaded"
            return
        }
        
        isTranscribing = true
        audioBuffer.removeAll()
        capturedAudioBuffer.removeAll()
        rawAudioBuffer.removeAll()
        streamingSegments.removeAll()
        transcriptionText = ""
        lastError = nil
        audioQualityStats = nil
    }
    
    func stopRecording() {
        if audioBuffer.count >= minimumAudioLength {
            transcribeCompleteAudio()
        } else {
            isTranscribing = false
        }
    }
    
    private func transcribeCompleteAudio() {
        guard let whisper = whisper, !audioBuffer.isEmpty else { 
            isTranscribing = false
            return 
        }
        
        // Skip if Whisper is busy
        guard !isWhisperBusy else {
            print("STT: Whisper is busy, cannot transcribe now")
            isTranscribing = false
            return
        }
        
        isWhisperBusy = true
        let audioToTranscribe = audioBuffer // Capture current audio
        
        // Store ORIGINAL unprocessed audio for history (to avoid static in playback)
        capturedAudioBuffer = audioToTranscribe
        
        Task {
            do {
                    print("STT: Transcribing \(audioToTranscribe.count) samples (\(String(format: "%.1f", Double(audioToTranscribe.count) / self.sampleRate))s)")
                    
                    // Calculate audio quality metrics for UI display
                    let maxAmp = audioToTranscribe.map { abs($0) }.max() ?? 0
                    let avgAmp = audioToTranscribe.reduce(0) { $0 + abs($1) } / Float(audioToTranscribe.count)
                    let rms = sqrt(audioToTranscribe.reduce(0) { $0 + $1 * $1 } / Float(audioToTranscribe.count))
                    let duration = Double(audioToTranscribe.count) / self.sampleRate
                    
                    // Additional diagnostics for static analysis
                    let zeroCrossings = audioToTranscribe.indices.dropFirst().filter { i in
                        (audioToTranscribe[i-1] < 0 && audioToTranscribe[i] >= 0) ||
                        (audioToTranscribe[i-1] >= 0 && audioToTranscribe[i] < 0)
                    }.count
                    let zeroCrossingRate = Float(zeroCrossings) / Float(audioToTranscribe.count)
                    
                    // Check for constant high-frequency noise pattern
                    var highFreqEnergy: Float = 0
                    if audioToTranscribe.count > 10 {
                        for i in 1..<min(1000, audioToTranscribe.count) {
                            let diff = audioToTranscribe[i] - audioToTranscribe[i-1]
                            highFreqEnergy += diff * diff
                        }
                        highFreqEnergy = sqrt(highFreqEnergy / Float(min(999, audioToTranscribe.count - 1)))
                    }
                    
                    print("STT: Zero crossing rate: \(String(format: "%.3f", zeroCrossingRate)), High-freq energy: \(String(format: "%.3f", highFreqEnergy))")
                    
                    // Store stats for UI display
                    await MainActor.run {
                        self.audioQualityStats = AudioQualityStats(
                            sampleCount: audioToTranscribe.count,
                            durationSeconds: duration,
                            maxAmplitude: maxAmp,
                            avgAmplitude: avgAmp,
                            rmsLevel: rms,
                            timestamp: Date()
                        )
                    }
                    
                    print("STT: Audio quality - Max: \(String(format: "%.4f", maxAmp)), Avg: \(String(format: "%.4f", avgAmp)), RMS: \(String(format: "%.4f", rms))")
                    
                    // Apply noise reduction and amplification to a COPY for transcription only
                    var processedAudio = audioToTranscribe
                    
                    // Minimal validation - only remove NaN/infinite values
                    processedAudio = processedAudio.map { sample in
                        if sample.isNaN || sample.isInfinite {
                            return 0.0
                        }
                        return max(-1.0, min(1.0, sample))
                    }
                    
                    // No amplification - preserve original audio levels to avoid clipping
                    // The ESP32 audio levels should be appropriate as-is
                    
                    // Add silence padding
                    let paddingSamples = Int(self.sampleRate * 0.3)
                    let silencePadding = Array(repeating: Float(0.0), count: paddingSamples)
                    processedAudio = silencePadding + processedAudio + silencePadding
                    
                    // Use the standard transcribe method
                    let segments = try await whisper.transcribe(audioFrames: processedAudio)
                    
                    await MainActor.run {
                        self.isWhisperBusy = false
                        
                        // Clear previous segments and add new complete transcription
                        self.streamingSegments.removeAll()
                        
                        var completeText = ""
                        for segment in segments {
                            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                completeText += text + " "
                                
                                let transcriptionSegment = TranscriptionSegment(
                                    text: text,
                                    startTime: segment.startTime,
                                    endTime: segment.endTime,
                                    confidence: 1.0,
                                    isPartial: false
                                )
                                self.streamingSegments.append(transcriptionSegment)
                            }
                        }
                        
                        let cleanedText = self.postProcessTranscription(completeText)
                        self.transcriptionText = cleanedText
                        self.isTranscribing = false
                        print("STT: \"\(self.transcriptionText)\"")
                    }
                } catch {
                    await MainActor.run {
                        self.isWhisperBusy = false
                        self.isTranscribing = false
                        self.lastError = "Transcription failed: \(error.localizedDescription)"
                        print("STT Error: \(error)")
                        if let whisperError = error as? WhisperError {
                            print("STT WhisperError details: \(whisperError)")
                        }
                    }
                }
            }
    }
    
    
    // MARK: - Public API
    
    func transcribeAudio(_ audioSamples: [Int16], completion: @escaping @Sendable (String) -> Void) {
        guard isModelLoaded, let whisper = whisper else {
            Task { @MainActor in
                self.lastError = "Whisper model not loaded"
                completion("")
            }
            return
        }
        
        // Convert Int16 to Float32 normalized
        let floatSamples = audioSamples.map { Float($0) / 32767.0 }
        
        guard floatSamples.count >= minimumAudioLength else {
            Task { @MainActor in
                self.lastError = "Audio too short for transcription"
                completion("")
            }
            return
        }
        
        // Skip if Whisper is busy
        guard !isWhisperBusy else {
            Task { @MainActor in
                self.lastError = "Whisper is busy with another transcription"
                completion("")
            }
            return
        }
        
        Task { @MainActor in
            self.isTranscribing = true
            self.lastError = nil
        }
        
        Task {
            // Check if whisper is busy
            let isBusy = await MainActor.run { isWhisperBusy }
            guard !isBusy else {
                await MainActor.run {
                    self.isTranscribing = false
                }
                completion("")
                return
            }
            
            await MainActor.run { self.isWhisperBusy = true }
            
            do {
                let segments = try await whisper.transcribe(audioFrames: floatSamples)
                
                await MainActor.run {
                    self.isWhisperBusy = false
                    
                    var fullText = ""
                    self.streamingSegments.removeAll()
                    
                    for segment in segments {
                        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            fullText += text + " "
                            
                            let transcriptionSegment = TranscriptionSegment(
                                text: text,
                                startTime: segment.startTime,
                                endTime: segment.endTime,
                                confidence: 1.0
                            )
                            self.streamingSegments.append(transcriptionSegment)
                        }
                    }
                    
                    let result = self.postProcessTranscription(fullText)
                    self.transcriptionText = result
                    
                    self.isTranscribing = false
                    completion(result)
                }
            } catch {
                await MainActor.run {
                    self.isWhisperBusy = false
                    self.lastError = "Transcription failed: \(error.localizedDescription)"
                    print("STT Error: \(error)")
                    self.isTranscribing = false
                }
                completion("")
            }
        }
    }
    
    func clearTranscription() {
        transcriptionText = ""
        streamingSegments.removeAll()
        audioBuffer.removeAll()
        capturedAudioBuffer.removeAll()
    }
    
    // Reset Whisper state
    func resetWhisperState() {
        isWhisperBusy = false
        lastError = nil
    }
    
    var whisperStatus: String {
        return "Model loaded: \(isModelLoaded), Whisper busy: \(isWhisperBusy), Transcribing: \(isTranscribing)"
    }
    
    // Test method to verify Whisper works with synthetic audio
    func testWhisperWithSyntheticAudio() {
        guard let whisper = whisper else {
            lastError = "Whisper model not loaded"
            return
        }
        
        guard !isWhisperBusy else {
            lastError = "Whisper is busy with another transcription"
            return
        }
        
        // Generate 2 seconds of 440Hz sine wave at 16kHz sample rate
        let duration: Double = 2.0
        let frequency: Float = 440.0
        let sampleCount = Int(sampleRate * duration)
        
        var testAudio: [Float] = []
        for i in 0..<sampleCount {
            let t = Float(i) / Float(sampleRate)
            let sample = sin(2.0 * Float.pi * frequency * t) * 0.5
            testAudio.append(sample)
        }
        
        Task {
            let isBusy = await MainActor.run { isWhisperBusy }
            guard !isBusy else {
                await MainActor.run {
                    self.lastError = "Whisper became busy"
                }
                return
            }
            
            await MainActor.run { self.isWhisperBusy = true }
            
            do {
                let segments = try await whisper.transcribe(audioFrames: testAudio)
                
                await MainActor.run {
                    self.isWhisperBusy = false
                    print("STT Test: Got \(segments.count) segments")
                    self.lastError = nil
                }
            } catch {
                await MainActor.run {
                    self.isWhisperBusy = false
                    self.lastError = "Test transcription failed: \(error.localizedDescription)"
                    print("STT Test Error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Post-Processing
    
    private func postProcessTranscription(_ text: String) -> String {
        var cleanedText = text
        
        // Remove content within parentheses including the parentheses themselves
        // This handles cases like "(car engine)", "(music)", "(slamming)", etc.
        let parenthesesPattern = "\\([^)]*\\)"
        cleanedText = cleanedText.replacingOccurrences(of: parenthesesPattern, 
                                                      with: "", 
                                                      options: .regularExpression)
        
        // Remove content within asterisks including the asterisks themselves
        // This handles cases like "*laughing*", "*noise*", "*background music*", etc.
        let asterisksPattern = "\\*[^*]*\\*"
        cleanedText = cleanedText.replacingOccurrences(of: asterisksPattern, 
                                                      with: "", 
                                                      options: .regularExpression)
        
        // Remove content within square brackets including the brackets themselves
        // This handles cases like "[music]", "[noise]", "[background sound]", etc.
        let bracketsPattern = "\\[[^\\]]*\\]"
        cleanedText = cleanedText.replacingOccurrences(of: bracketsPattern, 
                                                      with: "", 
                                                      options: .regularExpression)
        
        // Clean up any double spaces that may result from removing parentheses, asterisks, or brackets
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", 
                                                      with: " ", 
                                                      options: .regularExpression)
        
        // Trim whitespace and newlines
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Utility
    
    var formattedTranscriptionWithTimestamps: String {
        return streamingSegments.map { segment in
            let startTime = String(format: "%.1f", Double(segment.startTime) / 1000.0)
            let endTime = String(format: "%.1f", Double(segment.endTime) / 1000.0)
            let status = segment.isPartial ? "[PARTIAL]" : "[FINAL]"
            return "[\(startTime)s-\(endTime)s] \(status) \(segment.text)"
        }.joined(separator: "\n")
    }
    
    // MARK: - Helper Methods
    
    private func createTempAudioFile(from audioSamples: [Float]) -> URL? {
        do {
            // Create a temporary file URL
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileName = "whisper_audio_\(UUID().uuidString).wav"
            let tempURL = tempDir.appendingPathComponent(tempFileName)
            
            // Create audio buffer settings (16kHz, 1 channel, 16-bit PCM)
            let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, 
                                          sampleRate: sampleRate, 
                                          channels: 1, 
                                          interleaved: false)
            
            guard let format = audioFormat else {
                return nil
            }
            
            // Create audio file
            let audioFile = try AVAudioFile(forWriting: tempURL, 
                                          settings: format.settings)
            
            // Convert Float32 samples to Int16 and create audio buffer
            let frameCount = AVAudioFrameCount(audioSamples.count)
            guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            
            audioBuffer.frameLength = frameCount
            
            // Convert Float32 samples (-1.0 to 1.0) to Int16 samples
            if let int16ChannelData = audioBuffer.int16ChannelData {
                let channelData = int16ChannelData[0]
                for i in 0..<audioSamples.count {
                    // Clamp to [-1.0, 1.0] and convert to Int16 range
                    let clampedSample = max(-1.0, min(1.0, audioSamples[i]))
                    channelData[i] = Int16(clampedSample * 32767.0)
                }
            }
            
            // Write the buffer to the file
            try audioFile.write(from: audioBuffer)
            
            return tempURL
            
        } catch {
            print("STT Error creating temp audio file: \(error)")
            return nil
        }
    }
}