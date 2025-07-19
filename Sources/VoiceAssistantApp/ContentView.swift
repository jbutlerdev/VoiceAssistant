import SwiftUI

struct ContentView: View {
    @StateObject private var deviceManager = VoiceDeviceManager()
    @StateObject private var deviceConfig = DeviceConfiguration()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var openAIService = OpenAIService()
    @StateObject private var sttManager = SpeechToTextManager()
    @StateObject private var ttsManager = TextToSpeechManager()
    @StateObject private var historyManager = ChatHistoryManager()
    @StateObject private var mcpManager = MCPManager()
    @State private var selectedTab = 3 // Default to Transcription tab
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionView(deviceManager: deviceManager)
                .tabItem {
                    Label("Connection", systemImage: "cable.connector")
                }
                .tag(0)
            
            DeviceView(
                deviceManager: deviceManager,
                deviceConfig: deviceConfig
            )
            .tabItem {
                Label("Device", systemImage: "speaker.wave.3")
            }
            .tag(1)
            
            AIConfigurationView(settingsStore: settingsStore)
                .tabItem {
                    Label("AI Config", systemImage: "brain.head.profile")
                }
                .tag(2)
            
            TranscriptionView(
                deviceManager: deviceManager, 
                sttManager: sttManager,
                openAIService: openAIService,
                settingsStore: settingsStore,
                ttsManager: ttsManager,
                historyManager: historyManager
            )
                .tabItem {
                    Label("Transcription", systemImage: "waveform.and.mic")
                }
                .tag(3)
            
            ToolsConfigurationView(mcpManager: mcpManager)
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
                .tag(4)
            
            ChatHistoryView(historyManager: historyManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(5)
            
            SettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(6)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            deviceManager.setSpeechToTextManager(sttManager)
            openAIService.setMCPManager(mcpManager)
            deviceManager.startDeviceDiscovery()
            
            // Check if we need to request network access for local servers
            if settingsStore.openAIBaseURL.contains("localhost") || 
               settingsStore.openAIBaseURL.contains("127.0.0.1") || 
               settingsStore.openAIBaseURL.contains("192.168.") || 
               settingsStore.openAIBaseURL.contains("10.") {
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    openAIService.requestNetworkAccess()
                }
            }
        }
        .onDisappear {
            deviceManager.disconnect()
        }
    }
}

// Preview removed for command-line build compatibility