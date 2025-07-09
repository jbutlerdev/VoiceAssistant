import SwiftUI

struct AIConfigurationView: View {
    @ObservedObject var settingsStore: SettingsStore
    @StateObject private var openAIService = OpenAIService()
    @State private var showingMCPServerForm = false
    @State private var showingAPIKeyField = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    Text("AI Configuration")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                Divider()
                
                // OpenAI Configuration Section
                VStack(alignment: .leading, spacing: 15) {
                    Text("OpenAI Configuration")
                        .font(.headline)
                        .padding(.bottom, 10)
                    
                    // Base URL
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Base URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("https://api.openai.com", text: $settingsStore.openAIBaseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // API Key
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                showingAPIKeyField.toggle()
                            }) {
                                Image(systemName: showingAPIKeyField ? "eye.slash" : "eye")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if showingAPIKeyField {
                            TextField("sk-...", text: $settingsStore.openAIAPIKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            SecureField("sk-...", text: $settingsStore.openAIAPIKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    // Model
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("gpt-4o-mini", text: $settingsStore.openAIModel)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Menu {
                                ForEach(SettingsStore.commonModels, id: \.self) { model in
                                    Button(model) {
                                        settingsStore.openAIModel = model
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    // Max Tokens
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Max Tokens")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("32768", value: $settingsStore.openAIMaxTokens, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Maximum number of tokens the AI can generate in response. Higher values allow longer responses but cost more.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // System Prompt
                    VStack(alignment: .leading, spacing: 5) {
                        Text("System Prompt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $settingsStore.openAISystemPrompt)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separatorColor), lineWidth: 1)
                            )
                        
                        Text("Instructions that define the AI's behavior and personality. This message is sent with every conversation.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Configuration Status
                    HStack {
                        Image(systemName: settingsStore.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(settingsStore.isConfigured ? .green : .orange)
                        
                        Text(settingsStore.isConfigured ? "Configuration Complete" : "Configuration Incomplete")
                            .font(.subheadline)
                            .foregroundColor(settingsStore.isConfigured ? .green : .orange)
                    }
                    .padding(.top, 10)
                }
                
                // Network Access Section
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local Network Access")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("If using a local AI server (like Ollama, LM Studio, etc.), you need to grant local network access.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Request Network Access") {
                            openAIService.requestNetworkAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(openAIService.hasRequestedNetworkAccess)
                        
                        Button("Force Save Settings") {
                            settingsStore.forceSave()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if openAIService.hasRequestedNetworkAccess {
                        Text("✓ Network access requested. Check System Settings > Privacy & Security > Local Network")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Text("After granting permission, the app will appear in: System Settings > Privacy & Security > Local Network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Security Note
                Divider()
                
                Text("Note: Your API key is stored securely on this device and never transmitted except to your specified OpenAI endpoint.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}


// Preview removed for command-line build compatibility