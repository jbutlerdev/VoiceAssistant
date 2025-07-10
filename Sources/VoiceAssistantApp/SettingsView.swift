import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "gear")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Divider()
            
            // App Information Section
            VStack(alignment: .leading, spacing: 15) {
                Text("App Information")
                    .font(.headline)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Version:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Text("Build:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Text("Bundle ID:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "Unknown")
                            .font(.subheadline)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }
            }
            
            Divider()
            
            // Data Management Section
            VStack(alignment: .leading, spacing: 15) {
                Text("Data Management")
                    .font(.headline)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings are automatically saved to your device and synchronized across app launches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Reset All Settings") {
                        // Reset to default values
                        settingsStore.openAIBaseURL = "https://api.openai.com"
                        settingsStore.openAIAPIKey = ""
                        settingsStore.openAIModel = "gpt-4o-mini"
                        settingsStore.openAIMaxTokens = 32768
                        settingsStore.openAISystemPrompt = "You are a helpful assistant."
                        settingsStore.enableTextToSpeech = false
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // About Section
            VStack(alignment: .leading, spacing: 15) {
                Text("About")
                    .font(.headline)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home Assistant Voice - Local")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("A local voice assistant for Home Assistant Voice devices with USB communication and AI integration.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Built with Swift, SwiftUI, and Whisper for speech recognition.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Footer Note
            Text("For AI configuration, see the AI Config tab. For device settings, see the Device tab.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}