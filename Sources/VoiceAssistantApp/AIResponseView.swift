import SwiftUI

struct AIResponseView: View {
    @ObservedObject var openAIService: OpenAIService
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ttsManager: TextToSpeechManager
    @ObservedObject var historyManager: ChatHistoryManager
    @ObservedObject var sttManager: SpeechToTextManager
    let transcribedText: String
    @State private var lastSpokenResponse: String = ""
    
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
                    
                    // Tool Calls Section
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
                }
                .padding(.horizontal)
            }
            
            // Clear button at bottom
            if !openAIService.isProcessing && !openAIService.lastResponse.isEmpty {
                HStack {
                    Button("Clear Response") {
                        openAIService.clearResponse()
                        lastSpokenResponse = ""
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
        .onChange(of: openAIService.lastResponse) { newResponse in
            // Handle both TTS and history saving when a new response is received
            if !newResponse.isEmpty && !openAIService.isProcessing {
                // Trigger TTS if enabled
                if settingsStore.enableTextToSpeech && 
                   newResponse != lastSpokenResponse {
                    ttsManager.speak(newResponse)
                    lastSpokenResponse = newResponse
                }
                
                // Save to history
                if !sttManager.transcriptionText.isEmpty && !sttManager.lastCapturedAudio.isEmpty {
                    historyManager.addChat(
                        recordedAudio: sttManager.lastCapturedAudio,
                        transcription: sttManager.transcriptionText,
                        aiResponse: newResponse,
                        sampleRate: 16000.0
                    )
                }
            }
        }
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