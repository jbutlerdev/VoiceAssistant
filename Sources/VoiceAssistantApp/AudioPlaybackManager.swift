import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlaybackManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var lastError: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackStartTime: Date?
    
    override init() {
        super.init()
    }
    
    func playAudio(samples: [Float], sampleRate: Double = 16000.0) {
        guard !samples.isEmpty else {
            lastError = "No audio samples provided"
            return
        }
        
        // Stop any existing playback
        stopPlayback()
        
        // Calculate duration
        duration = Double(samples.count) / sampleRate
        
        do {
            // Create and configure audio engine
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            
            // Attach player node to engine
            engine.attach(playerNode)
            
            // Create audio format
            let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            guard let format = audioFormat else {
                lastError = "Failed to create audio format"
                return
            }
            
            // Connect player node to main mixer
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            
            // Create audio buffer
            let bufferSize = AVAudioFrameCount(samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
                lastError = "Failed to create audio buffer"
                return
            }
            
            buffer.frameLength = bufferSize
            
            // Copy samples to buffer
            let channelData = buffer.floatChannelData?[0]
            samples.withUnsafeBufferPointer { samplePtr in
                channelData?.initialize(from: samplePtr.baseAddress!, count: samples.count)
            }
            
            // Store references
            self.audioEngine = engine
            self.playerNode = playerNode
            
            // Start engine
            try engine.start()
            
            // Schedule buffer for playback (without completion handler to avoid crashes)
            playerNode.scheduleBuffer(buffer, at: nil, options: [])
            
            // Start playback
            playerNode.play()
            
            // Update state
            isPlaying = true
            currentTime = 0
            lastError = nil
            playbackStartTime = Date()
            
            // Start timer for progress updates
            startTimer()
            
            // Auto-stop after duration to prevent hanging
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 500_000_000) // Add 0.5s buffer
                if self.isPlaying && self.audioEngine != nil {
                    print("Auto-stopping audio playback after duration")
                    self.stopPlayback()
                }
            }
            
        } catch {
            lastError = "Audio playback failed: \(error.localizedDescription)"
            isPlaying = false
            audioEngine = nil
            playerNode = nil
        }
    }
    
    func stopPlayback() {
        // Stop AVAudioPlayer if it exists
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Stop AVAudioEngine if it exists
        if let engine = audioEngine {
            do {
                if let node = playerNode {
                    node.stop()
                    if engine.attachedNodes.contains(node) {
                        engine.detach(node)
                    }
                }
                if engine.isRunning {
                    engine.stop()
                }
            } catch {
                print("Error stopping audio engine: \(error)")
            }
        }
        audioEngine = nil
        playerNode = nil
        playbackStartTime = nil
        
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    func pausePlayback() {
        do {
            if let player = audioPlayer {
                player.pause()
            } else if let node = playerNode {
                node.pause()
            }
            isPlaying = false
            stopTimer()
        } catch {
            print("Error pausing playback: \(error)")
            stopPlayback()
        }
    }
    
    func resumePlayback() {
        do {
            var resumed = false
            
            if let player = audioPlayer {
                resumed = player.play()
            } else if let node = playerNode {
                node.play()
                resumed = true
            }
            
            if resumed {
                isPlaying = true
                startTimer()
            }
        } catch {
            print("Error resuming playback: \(error)")
            stopPlayback()
        }
    }
    
    func seek(to time: TimeInterval) {
        if let player = audioPlayer {
            player.currentTime = time
            currentTime = time
        } else {
            // Seeking with AVAudioEngine is complex and not supported in this simple implementation
            // For now, just update the displayed time
            currentTime = min(time, duration)
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                
                do {
                    if let player = self.audioPlayer, player.isPlaying {
                        self.currentTime = player.currentTime
                    } else if let startTime = self.playbackStartTime {
                        self.currentTime = Date().timeIntervalSince(startTime)
                        
                        // Stop when we reach the duration
                        if self.currentTime >= self.duration {
                            self.stopPlayback()
                        }
                    }
                } catch {
                    print("Timer update error: \(error)")
                    self.stopPlayback()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
            print("Audio playback finished")
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.lastError = "Decode error: \(error?.localizedDescription ?? "Unknown")"
            self.isPlaying = false
            self.stopTimer()
        }
    }
}