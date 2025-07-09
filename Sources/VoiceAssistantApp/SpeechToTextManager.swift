import Foundation
@preconcurrency import SwiftWhisper
import Combine
import AVFoundation

class SpeechToTextManager: ObservableObject {
    @Published var transcriptionText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var lastError: String?
    @Published var streamingSegments: [TranscriptionSegment] = []
    
    private var whisper: Whisper?
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000.0 // ESP32 sends 16kHz audio
    private let minimumAudioLength: Int = 8000 // 0.5 second minimum for transcription
    
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
    
    init() {
        loadWhisperModel()
        // Reset busy flag on initialization
        isWhisperBusy = false
    }
    
    private func loadWhisperModel() {
        lastError = nil
        
        // Get path to the bundled model file
        guard let modelPath = getModelPath() else {
            DispatchQueue.main.async {
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
            
            DispatchQueue.main.async {
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
        // Convert Int16 samples to Float32 normalized to [-1.0, 1.0]
        let floatSamples = samples.compactMap { sample -> Float? in
            let floatValue = Float(sample) / 32767.0
            // Check for NaN, infinity, or invalid values
            if floatValue.isNaN || floatValue.isInfinite {
                return nil
            }
            // Clamp to valid range
            return max(-1.0, min(1.0, floatValue))
        }
        
        // Only append if we have valid samples
        if !floatSamples.isEmpty {
            audioBuffer.append(contentsOf: floatSamples)
        }
    }
    
    func startRecording() {
        guard isModelLoaded else {
            lastError = "Whisper model not loaded"
            return
        }
        
        isTranscribing = true
        audioBuffer.removeAll()
        streamingSegments.removeAll()
        transcriptionText = ""
        lastError = nil
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
        
        let workItem = DispatchWorkItem { [weak self] in
            // Check again inside the queue
            guard let self = self else { return }
            guard !self.isWhisperBusy else { return }
            
            self.isWhisperBusy = true
            let audioToTranscribe = self.audioBuffer // Capture current audio
            
            Task {
                do {
                    print("STT: Transcribing \(audioToTranscribe.count) samples (\(String(format: "%.1f", Double(audioToTranscribe.count) / self.sampleRate))s)")
                    
                    // Apply noise reduction and amplification
                    var processedAudio = audioToTranscribe
                    
                    // Validate and clean audio data
                    processedAudio = processedAudio.compactMap { sample in
                        if sample.isNaN || sample.isInfinite {
                            return 0.0
                        }
                        return max(-1.0, min(1.0, sample))
                    }
                    
                    // Apply noise gate and amplification
                    let maxAmplitude = processedAudio.map { abs($0) }.max() ?? 0
                    let avgAmplitude = processedAudio.reduce(0) { $0 + abs($1) } / Float(processedAudio.count)
                    
                    let noiseThreshold = avgAmplitude * 0.3
                    processedAudio = processedAudio.map { sample in
                        if abs(sample) < noiseThreshold {
                            return 0.0
                        }
                        return sample
                    }
                    
                    // Amplify if needed
                    if maxAmplitude < 0.5 {
                        let amplificationFactor: Float = 0.7 / maxAmplitude
                        processedAudio = processedAudio.map { sample in
                            let amplified = sample * amplificationFactor
                            if amplified.isNaN || amplified.isInfinite {
                                return 0.0
                            }
                            return max(-1.0, min(1.0, amplified))
                        }
                    }
                    
                    // Add silence padding
                    let paddingSamples = Int(self.sampleRate * 0.3)
                    let silencePadding = Array(repeating: Float(0.0), count: paddingSamples)
                    processedAudio = silencePadding + processedAudio + silencePadding
                    
                    // Use the standard transcribe method
                    let segments = try await whisper.transcribe(audioFrames: processedAudio)
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
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
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
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
        
        whisperQueue.async(execute: workItem)
    }
    
    
    // MARK: - Public API
    
    func transcribeAudio(_ audioSamples: [Int16], completion: @escaping (String) -> Void) {
        guard isModelLoaded, let whisper = whisper else {
            DispatchQueue.main.async {
                self.lastError = "Whisper model not loaded"
                completion("")
            }
            return
        }
        
        // Convert Int16 to Float32 normalized
        let floatSamples = audioSamples.map { Float($0) / 32767.0 }
        
        guard floatSamples.count >= minimumAudioLength else {
            DispatchQueue.main.async {
                self.lastError = "Audio too short for transcription"
                completion("")
            }
            return
        }
        
        // Skip if Whisper is busy
        guard !isWhisperBusy else {
            DispatchQueue.main.async {
                self.lastError = "Whisper is busy with another transcription"
                completion("")
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = true
            self?.lastError = nil
        }
        
        whisperQueue.async {
            // Check again inside the queue
            guard !self.isWhisperBusy else {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    completion("")
                }
                return
            }
            
            self.isWhisperBusy = true
            
            Task {
                do {
                    let segments = try await whisper.transcribe(audioFrames: floatSamples)
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
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
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.isWhisperBusy = false
                        self.lastError = "Transcription failed: \(error.localizedDescription)"
                        print("STT Error: \(error)")
                        self.isTranscribing = false
                        completion("")
                    }
                }
            }
        }
    }
    
    func clearTranscription() {
        transcriptionText = ""
        streamingSegments.removeAll()
        audioBuffer.removeAll()
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
        
        whisperQueue.async {
            guard !self.isWhisperBusy else {
                DispatchQueue.main.async {
                    self.lastError = "Whisper became busy"
                }
                return
            }
            
            self.isWhisperBusy = true
            
            Task {
                do {
                    let segments = try await whisper.transcribe(audioFrames: testAudio)
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.isWhisperBusy = false
                        print("STT Test: Got \(segments.count) segments")
                        self.lastError = nil
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.isWhisperBusy = false
                        self?.lastError = "Test transcription failed: \(error.localizedDescription)"
                        print("STT Test Error: \(error)")
                    }
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
        
        // Clean up any double spaces that may result from removing parentheses
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