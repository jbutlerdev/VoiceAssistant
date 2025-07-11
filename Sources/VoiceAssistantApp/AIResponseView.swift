import SwiftUI

struct AIResponseView: View {
    @ObservedObject var openAIService: OpenAIService
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ttsManager: TextToSpeechManager
    @ObservedObject var historyManager: ChatHistoryManager
    @ObservedObject var sttManager: SpeechToTextManager
    let transcribedText: String
    @State private var lastSpokenResponse: String = ""
    @State private var spokenResponses: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and speech controls
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                
                Spacer()
                
                // Speech controls always visible in header
                if settingsStore.enableTextToSpeech {
                    HStack(spacing: 8) {
                        // Always show stop button prominently
                        Button("Stop Speech") {
                            ttsManager.stopSpeaking()
                        }
                        .foregroundColor(.red)
                        .buttonStyle(.borderedProminent)
                        .disabled(!ttsManager.isSpeaking)
                        
                        // Show clear queue button when there are queued items
                        if !ttsManager.speechQueue.isEmpty {
                            Button("Clear Queue (\(ttsManager.speechQueue.count))") {
                                ttsManager.clearQueue()
                            }
                            .foregroundColor(.orange)
                            .buttonStyle(.bordered)
                        }
                        
                        // Show speak again when there's content and not speaking
                        if !openAIService.lastResponse.isEmpty && !ttsManager.isSpeaking {
                            Button("Speak Again") {
                                ttsManager.speak(openAIService.lastResponse)
                            }
                            .foregroundColor(.green)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.bottom, 15)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    
                    if !transcribedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Message:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text(transcribedText)
                                .padding(12)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Show all chat responses
                    if !openAIService.chatResponses.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("AI Responses:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            LazyVStack(spacing: 15) {
                                ForEach(openAIService.chatResponses) { response in
                                    ChatResponseRowView(
                                        response: response,
                                        ttsManager: ttsManager,
                                        settingsStore: settingsStore,
                                        openAIService: openAIService
                                    )
                                }
                            }
                        }
                    }
                    
                    // Legacy single response view (for backward compatibility)
                    if openAIService.chatResponses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI Response:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if openAIService.isProcessing {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating response...")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            } else if let error = openAIService.lastError {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.red)
                                        Text("Error")
                                            .foregroundColor(.red)
                                            .font(.subheadline)
                                    }
                                    
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if !openAIService.lastResponse.isEmpty {
                                Text(openAIService.lastResponse)
                                    .padding(12)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("No response yet")
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        // Tool Calls Section for legacy view
                        if !openAIService.currentToolCalls.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tool Calls:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                LazyVStack(spacing: 8) {
                                    ForEach(openAIService.currentToolCalls) { toolCall in
                                        ToolCallRowView(toolCall: toolCall)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Clear button at bottom
            if !openAIService.isProcessing && (!openAIService.lastResponse.isEmpty || !openAIService.chatResponses.isEmpty) {
                HStack {
                    Button("Clear All Responses") {
                        openAIService.clearAllResponses()
                        lastSpokenResponse = ""
                        spokenResponses.removeAll()
                    }
                    .foregroundColor(.blue)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.top, 5)
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onChange(of: openAIService.responseQueue.count) { _ in
            // Process TTS queue when new responses are added
            if settingsStore.enableTextToSpeech {
                processResponseQueue()
            }
        }
        .onChange(of: openAIService.lastResponse) { newResponse in
            // Handle history saving only - TTS is handled by responseQueue
            if !newResponse.isEmpty && !openAIService.isProcessing {
                // Only save to history if using legacy single response mode
                if openAIService.chatResponses.isEmpty && !sttManager.transcriptionText.isEmpty && !sttManager.lastCapturedAudio.isEmpty {
                    historyManager.addChat(
                        recordedAudio: sttManager.lastCapturedAudio,
                        transcription: sttManager.transcriptionText,
                        aiResponse: newResponse,
                        sampleRate: 16000.0,
                        toolCalls: openAIService.currentToolCalls
                    )
                }
            }
        }
    }
    
    private func processResponseQueue() {
        // Process queued responses for TTS
        while let response = openAIService.getNextResponseForTTS() {
            if let responseText = response.response,
               !spokenResponses.contains(response.id) {
                print("TTS: Queueing response: \(responseText.prefix(50))...")
                ttsManager.queueSpeech(responseText)
                spokenResponses.insert(response.id)
                
                // Save to history
                if !sttManager.transcriptionText.isEmpty && !sttManager.lastCapturedAudio.isEmpty {
                    historyManager.addChat(
                        recordedAudio: sttManager.lastCapturedAudio,
                        transcription: sttManager.transcriptionText,
                        aiResponse: responseText,
                        sampleRate: 16000.0,
                        toolCalls: response.toolCalls
                    )
                }
            }
        }
    }
}

struct ChatResponseRowView: View {
    let response: ChatResponse
    @ObservedObject var ttsManager: TextToSpeechManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var openAIService: OpenAIService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Response header
            HStack {
                Text("Request: \(response.message.prefix(50))\(response.message.count > 50 ? "..." : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(DateFormatter.timeFormatter.string(from: response.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Remove individual response button
                Button(action: {
                    openAIService.removeResponse(id: response.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            // Response content
            if response.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if let error = response.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text("Error")
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                    
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let responseText = response.response {
                VStack(alignment: .leading, spacing: 8) {
                    Text(responseText)
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Individual response TTS controls
                    if settingsStore.enableTextToSpeech {
                        HStack {
                            Button("Speak This") {
                                ttsManager.speak(responseText)
                            }
                            .font(.caption)
                            .foregroundColor(.green)
                            .buttonStyle(.bordered)
                            
                            Button("Queue This") {
                                ttsManager.queueSpeech(responseText)
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            // Tool calls section
            if !response.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tool Calls:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(response.toolCalls) { toolCall in
                            ToolCallRowView(toolCall: toolCall)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ToolCallRowView: View {
    let toolCall: ToolCallDisplay
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolCallHeader
            
            if isExpanded {
                toolCallDetails
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var toolCallHeader: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toolCall.toolName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(DateFormatter.timeFormatter.string(from: toolCall.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
    }
    
    private var toolCallDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            argumentsSection
            responseSection
        }
        .padding(.leading, 20)
    }
    
    private var argumentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arguments:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(formatJSON(toolCall.arguments))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Response:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(toolCall.result)
                .font(.caption)
                .textSelection(.enabled)
                .padding(8)
                .background(toolCall.result.hasPrefix("Error:") ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return jsonString
        }
        return prettyString
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}