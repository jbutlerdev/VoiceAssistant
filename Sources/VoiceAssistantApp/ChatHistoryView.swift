import SwiftUI

struct ChatHistoryView: View {
    @ObservedObject var historyManager: ChatHistoryManager
    @StateObject private var audioPlayer = AudioPlaybackManager()
    @State private var showDeleteAllAlert = false
    @State private var showDeleteOlderAlert = false
    @State private var showAudioError = false
    @State private var audioErrorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if historyManager.chatHistory.isEmpty {
                emptyStateView
            } else if let currentChat = historyManager.currentChat {
                ScrollView {
                    chatDetailView(currentChat)
                        .padding()
                }
            }
            
            Divider()
            
            // Footer controls
            footerControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor))
        .alert("Delete All Older Chats", isPresented: $showDeleteOlderAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                historyManager.deleteAllChatsOlderThanCurrent()
            }
        } message: {
            Text("Are you sure you want to delete all chats older than the current one? This action cannot be undone.")
        }
        .alert("Clear All History", isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                historyManager.clearAllHistory()
            }
        } message: {
            Text("Are you sure you want to clear all chat history? This action cannot be undone.")
        }
        .alert("Audio Playback Error", isPresented: $showAudioError) {
            Button("OK") { }
        } message: {
            Text(audioErrorMessage)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
            
            Text("Chat History")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            if !historyManager.chatHistory.isEmpty {
                Text("\(historyManager.currentChatIndex + 1) of \(historyManager.chatHistory.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Chat History")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your conversation history will appear here")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Chat Detail View
    
    private func chatDetailView(_ chat: ChatHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Timestamp
            HStack {
                Image(systemName: "calendar")
                Text(chat.formattedDate)
                
                Spacer()
                
                Image(systemName: "clock")
                Text(chat.formattedTime)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            // Transcription Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Your Message", systemImage: "mic.fill")
                        .font(.headline)
                    
                    Spacer()
                    
                    // Audio playback controls
                    audioPlaybackControls(for: chat)
                }
                
                Text(chat.transcription)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
            
            // AI Response Section
            VStack(alignment: .leading, spacing: 10) {
                Label("AI Response", systemImage: "cpu")
                    .font(.headline)
                
                Text(chat.aiResponse)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
            
            // Audio Info
            HStack {
                Image(systemName: "waveform")
                if chat.audioDuration > 0 {
                    Text("Audio Duration: \(formatDuration(chat.audioDuration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No audio data")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                // Show sample count for debugging
                Text("(\(chat.audioSamples.count) samples)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Audio Playback Controls
    
    private func audioPlaybackControls(for chat: ChatHistoryItem) -> some View {
        HStack(spacing: 12) {
            if audioPlayer.isPlaying {
                Button(action: { audioPlayer.stopPlayback() }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                
                // Progress indicator
                Text("\(formatDuration(audioPlayer.currentTime)) / \(formatDuration(audioPlayer.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(action: { 
                    let samples = chat.audioSamples
                    if samples.isEmpty {
                        audioErrorMessage = "No audio data available for this recording."
                        showAudioError = true
                    } else {
                        // Clear any previous errors
                        audioPlayer.lastError = nil
                        
                        // Start playback
                        audioPlayer.playAudio(samples: samples, sampleRate: chat.audioSampleRate)
                        
                        // Check for playback errors after a brief delay
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            if let error = audioPlayer.lastError {
                                audioErrorMessage = "Audio playback failed: \(error)"
                                showAudioError = true
                                audioPlayer.stopPlayback() // Ensure cleanup
                            }
                        }
                    }
                }) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                // Show error if there's one
                if let error = audioPlayer.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
    }
    
    // MARK: - Footer Controls
    
    private var footerControls: some View {
        HStack(spacing: 20) {
            // Navigation controls
            HStack(spacing: 15) {
                Button(action: { historyManager.goToPrevious() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!historyManager.hasPrevious)
                
                Button(action: { historyManager.goToMostRecent() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(historyManager.currentChatIndex == 0)
                
                Button(action: { historyManager.goToNext() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!historyManager.hasNext)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // Delete controls
            if !historyManager.chatHistory.isEmpty {
                Menu {
                    Button(role: .destructive, action: {
                        historyManager.deleteCurrentChat()
                    }) {
                        Label("Delete Current Chat", systemImage: "trash")
                    }
                    
                    Button(role: .destructive, action: {
                        showDeleteOlderAlert = true
                    }) {
                        Label("Delete All Older Chats", systemImage: "trash.slash")
                    }
                    .disabled(historyManager.currentChatIndex == historyManager.chatHistory.count - 1)
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        showDeleteAllAlert = true
                    }) {
                        Label("Clear All History", systemImage: "xmark.circle")
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}