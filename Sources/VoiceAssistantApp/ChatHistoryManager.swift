import Foundation
import Combine

@MainActor
class ChatHistoryManager: ObservableObject {
    @Published var chatHistory: [ChatHistoryItem] = []
    @Published var currentChatIndex: Int = 0
    @Published var isLoading = false
    
    private let storageDirectory: URL
    private let historyFileName = "chat_history.json"
    private let maxHistorySize = 1000 // Maximum number of chats to keep
    
    var currentChat: ChatHistoryItem? {
        guard !chatHistory.isEmpty && currentChatIndex >= 0 && currentChatIndex < chatHistory.count else {
            return nil
        }
        return chatHistory[currentChatIndex]
    }
    
    var hasNext: Bool {
        return currentChatIndex < chatHistory.count - 1
    }
    
    var hasPrevious: Bool {
        return currentChatIndex > 0
    }
    
    init() {
        // Create storage directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "VoiceAssistant"
        storageDirectory = appSupport.appendingPathComponent(bundleID).appendingPathComponent("ChatHistory")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        
        // Load existing history
        loadHistory()
    }
    
    // MARK: - Navigation
    
    func goToNext() {
        if hasNext {
            currentChatIndex += 1
        }
    }
    
    func goToPrevious() {
        if hasPrevious {
            currentChatIndex -= 1
        }
    }
    
    func goToMostRecent() {
        currentChatIndex = 0
    }
    
    // MARK: - CRUD Operations
    
    func addChat(recordedAudio: [Float], transcription: String, aiResponse: String, sampleRate: Double = 16000.0) {
        let duration = Double(recordedAudio.count) / sampleRate
        let audioData = recordedAudio.audioData
        
        let newChat = ChatHistoryItem(
            recordedAudio: audioData,
            transcription: transcription,
            aiResponse: aiResponse,
            audioSampleRate: sampleRate,
            audioDuration: duration
        )
        
        // Insert at beginning (most recent first)
        chatHistory.insert(newChat, at: 0)
        
        // Trim history if it exceeds max size
        if chatHistory.count > maxHistorySize {
            chatHistory = Array(chatHistory.prefix(maxHistorySize))
        }
        
        // Reset to most recent
        currentChatIndex = 0
        
        // Save to disk
        saveHistory()
    }
    
    func deleteCurrentChat() {
        guard let current = currentChat else { return }
        deleteChat(current)
    }
    
    func deleteChat(_ chat: ChatHistoryItem) {
        if let index = chatHistory.firstIndex(where: { $0.id == chat.id }) {
            chatHistory.remove(at: index)
            
            // Adjust current index if needed
            if currentChatIndex >= chatHistory.count && !chatHistory.isEmpty {
                currentChatIndex = chatHistory.count - 1
            } else if chatHistory.isEmpty {
                currentChatIndex = 0
            }
            
            saveHistory()
        }
    }
    
    func deleteAllChatsOlderThanCurrent() {
        guard let current = currentChat else { return }
        
        // Find the index of the current chat
        if let index = chatHistory.firstIndex(where: { $0.id == current.id }) {
            // Remove all chats after this index (older chats)
            if index < chatHistory.count - 1 {
                chatHistory = Array(chatHistory.prefix(index + 1))
                saveHistory()
            }
        }
    }
    
    func clearAllHistory() {
        chatHistory.removeAll()
        currentChatIndex = 0
        saveHistory()
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        let historyURL = storageDirectory.appendingPathComponent(historyFileName)
        let historyToSave = chatHistory // Capture the current state
        
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(historyToSave)
                try data.write(to: historyURL)
                await MainActor.run {
                    print("Chat history saved: \(historyToSave.count) items")
                }
            } catch {
                await MainActor.run {
                    print("Failed to save chat history: \(error)")
                }
            }
        }
    }
    
    private func loadHistory() {
        isLoading = true
        let historyURL = storageDirectory.appendingPathComponent(historyFileName)
        
        Task {
            defer { 
                Task { @MainActor in
                    self.isLoading = false
                }
            }
            
            guard FileManager.default.fileExists(atPath: historyURL.path) else {
                await MainActor.run {
                    print("No chat history file found")
                }
                return
            }
            
            do {
                let data = try Data(contentsOf: historyURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let loadedHistory = try decoder.decode([ChatHistoryItem].self, from: data)
                
                await MainActor.run {
                    self.chatHistory = loadedHistory
                    self.currentChatIndex = 0
                    print("Chat history loaded: \(loadedHistory.count) items")
                }
            } catch {
                await MainActor.run {
                    print("Failed to load chat history: \(error)")
                }
            }
        }
    }
    
    // MARK: - Export/Import
    
    func exportHistory() async -> URL? {
        let exportURL = storageDirectory.appendingPathComponent("chat_history_export_\(Date().timeIntervalSince1970).json")
        let historyToExport = chatHistory // Capture current state
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(historyToExport)
            try data.write(to: exportURL)
            return exportURL
        } catch {
            print("Failed to export chat history: \(error)")
            return nil
        }
    }
}