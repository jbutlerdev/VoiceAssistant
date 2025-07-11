import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @ObservedObject var sttManager: SpeechToTextManager
    @ObservedObject var openAIService: OpenAIService
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ttsManager: TextToSpeechManager
    @ObservedObject var historyManager: ChatHistoryManager
    @State private var showDetailedView = false
    @State private var autoScroll = true
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("Speech to Text", systemImage: "waveform.and.mic")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Status indicators
                HStack(spacing: 12) {
                    // Model status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sttManager.isModelLoaded ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(sttManager.isModelLoaded ? "Model Ready" : "Model Loading")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Recording status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(deviceManager.connectionStatus == .connected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(deviceManager.connectionStatus == .connected ? "Device Connected" : "Device Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Transcription status
                    HStack(spacing: 4) {
                        if sttManager.isTranscribing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                        Text(sttManager.isTranscribing ? "Transcribing..." : "Ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Error display
            if let error = sttManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Clear") {
                        sttManager.clearTranscription()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Main transcription display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription")
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack {
                        // Toggle detailed view
                        Button(action: { showDetailedView.toggle() }) {
                            Image(systemName: showDetailedView ? "list.bullet" : "text.alignleft")
                        }
                        .help(showDetailedView ? "Show simple view" : "Show detailed view")
                        
                        // Auto scroll toggle
                        Button(action: { autoScroll.toggle() }) {
                            Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        }
                        .help("Auto scroll")
                        
                        // Clear button
                        Button("Clear") {
                            sttManager.clearTranscription()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Transcription content
                ScrollViewReader { proxy in
                    ScrollView {
                        if showDetailedView {
                            detailedTranscriptionView
                        } else {
                            simpleTranscriptionView
                        }
                    }
                    .frame(height: geometry.size.height * 0.33)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    .onChange(of: sttManager.transcriptionText) { _ in
                        if autoScroll {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: sttManager.streamingSegments.count) { _ in
                        if autoScroll {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Controls
            HStack {
                Spacer()
                
                // Statistics
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Segments: \(sttManager.streamingSegments.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Characters: \(sttManager.transcriptionText.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // AI Response Section
            if settingsStore.isConfigured {
                VStack(spacing: 16) {
                    Divider()
                    
                    AIResponseView(
                        openAIService: openAIService,
                        settingsStore: settingsStore,
                        ttsManager: ttsManager,
                        historyManager: historyManager,
                        sttManager: sttManager,
                        transcribedText: sttManager.transcriptionText
                    )
                    .frame(height: geometry.size.height * 0.6)
                    
                    // Auto-send status
                    if openAIService.isProcessing || !openAIService.activeRequests.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Processing \(openAIService.activeRequests.count) AI request(s)...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    } else if !sttManager.transcriptionText.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Auto-send enabled - transcription will be sent to AI automatically")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Divider()
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("AI Configuration Required")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    
                    Text("Configure OpenAI settings in the Settings tab to enable AI responses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
        .onChange(of: sttManager.transcriptionText) { newText in
            print("STT: Transcription changed to: \"\(newText)\"")
            print("STT: Settings configured: \(settingsStore.isConfigured)")
            print("STT: OpenAI processing: \(openAIService.isProcessing)")
            print("STT: Is transcribing: \(sttManager.isTranscribing)")
            
            // Auto-send to AI when transcription is complete (not while actively transcribing)
            // Removed the isProcessing check to allow concurrent requests
            if settingsStore.isConfigured && !newText.isEmpty && !sttManager.isTranscribing {
                print("STT: Transcription complete, sending to AI: \"\(newText)\"")
                openAIService.sendMessage(
                    newText,
                    baseURL: settingsStore.openAIBaseURL,
                    apiKey: settingsStore.openAIAPIKey,
                    model: settingsStore.openAIModel,
                    maxTokens: settingsStore.openAIMaxTokens,
                    systemPrompt: settingsStore.openAISystemPrompt
                )
            } else {
                print("STT: Not auto-sending - configured: \(settingsStore.isConfigured), empty: \(newText.isEmpty), transcribing: \(sttManager.isTranscribing)")
            }
        }
    }
    
    // MARK: - Transcription Views
    
    @ViewBuilder
    private var simpleTranscriptionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sttManager.transcriptionText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No transcription yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("Speak to your device to see transcription here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(sttManager.transcriptionText)
                    .font(.body)
                    .padding()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                    .id("bottom")
            }
        }
    }
    
    @ViewBuilder
    private var detailedTranscriptionView: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if sttManager.streamingSegments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No segments yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("Detailed view will show transcription segments with timestamps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(sttManager.streamingSegments, id: \.id) { segment in
                    segmentView(segment)
                }
                
                Spacer()
                    .id("bottom")
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func segmentView(_ segment: SpeechToTextManager.TranscriptionSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Timestamp
                Text("\(segment.startTime)ms - \(segment.endTime)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
                
                Spacer()
                
                // Status badge
                Text(segment.isPartial ? "STREAMING" : "FINAL")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(segment.isPartial ? .blue : .green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((segment.isPartial ? Color.blue : Color.green).opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Transcription text
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.leading, 8)
                .opacity(segment.isPartial ? 0.7 : 1.0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(segment.isPartial ? Color.blue.opacity(0.05) : Color.green.opacity(0.05))
        .cornerRadius(6)
    }
    
}