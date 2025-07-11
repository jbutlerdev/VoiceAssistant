import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var lastError: String?
    @Published var speechQueue: [String] = []
    @Published var currentlySpeaking: String?
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()
    private var processingQueue = false
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        // Note: Audio session setup not required on macOS
    }
    
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Stop any current speech
        stopSpeaking()
        
        // Clear any previous errors
        lastError = nil
        
        // Create speech utterance
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure speech parameters
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        // Try to use a more natural voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        print("TTS: Speaking text: \(text.prefix(50))...")
        currentlySpeaking = text
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    func queueSpeech(_ text: String) {
        guard !text.isEmpty else { return }
        
        print("TTS: Queueing text: \(text.prefix(50))...")
        speechQueue.append(text)
        processQueue()
    }
    
    private func processQueue() {
        guard !processingQueue && !speechQueue.isEmpty && !isSpeaking else { return }
        
        processingQueue = true
        let nextText = speechQueue.removeFirst()
        
        // Clear any previous errors
        lastError = nil
        
        // Create speech utterance
        let utterance = AVSpeechUtterance(string: nextText)
        
        // Configure speech parameters
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        // Try to use a more natural voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        print("TTS: Processing queue - speaking: \(nextText.prefix(50))...")
        currentlySpeaking = nextText
        isSpeaking = true
        speechSynthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }
        currentlySpeaking = nil
        processingQueue = false
    }
    
    func clearQueue() {
        speechQueue.removeAll()
        stopSpeaking()
    }
    
    func pauseSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.pauseSpeaking(at: .immediate)
        }
    }
    
    func continueSpeaking() {
        if speechSynthesizer.isPaused {
            speechSynthesizer.continueSpeaking()
        }
    }
    
    var availableVoices: [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
    }
    
    var currentVoice: AVSpeechSynthesisVoice? {
        return AVSpeechSynthesisVoice(language: "en-US")
    }
    
    func testTTS() {
        speak("Text to speech is working correctly!")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
        print("TTS: Speech started")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentlySpeaking = nil
            self.processingQueue = false
            
            // Process next item in queue if available
            self.processQueue()
        }
        print("TTS: Speech finished")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentlySpeaking = nil
            self.processingQueue = false
            
            // Process next item in queue if available
            self.processQueue()
        }
        print("TTS: Speech cancelled")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("TTS: Speech paused")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("TTS: Speech continued")
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // This can be used for real-time highlighting if needed
    }
}