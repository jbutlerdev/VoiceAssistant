import SwiftUI

struct AIConfigurationView: View {
    @ObservedObject var aiConfig: AIConfiguration
    @State private var showingMCPServerForm = false
    
    var body: some View {
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
            
            ScrollView {
                VStack(spacing: 20) {
                    // Notice Banner
                    NoticeBanner()
                    
                    // OpenAI Configuration
                    OpenAIConfigCard(aiConfig: aiConfig)
                    
                    // MCP Servers Configuration
                    MCPServersConfigCard(
                        aiConfig: aiConfig,
                        showingMCPServerForm: $showingMCPServerForm
                    )
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingMCPServerForm) {
            MCPServerFormView(aiConfig: aiConfig)
        }
    }
}

struct NoticeBanner: View {
    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Integration - Coming Soon")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("AI processing features are currently stubbed out for future implementation. Configure your settings now for when the feature becomes available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Color.blue.opacity(0.05))
    }
}

struct OpenAIConfigCard: View {
    @ObservedObject var aiConfig: AIConfiguration
    @State private var isAPIKeyVisible = false
    
    var body: some View {
        GroupBox(label: Text("OpenAI Configuration").font(.headline)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API URL:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("https://api.openai.com/v1", text: $aiConfig.openAIURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: aiConfig.openAIURL) { _ in
                            aiConfig.saveToUserDefaults()
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            isAPIKeyVisible.toggle()
                        }) {
                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if isAPIKeyVisible {
                        TextField("sk-...", text: $aiConfig.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $aiConfig.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .onChange(of: aiConfig.openAIAPIKey) { _ in
                    aiConfig.saveToUserDefaults()
                }
                
                Text("Your OpenAI API key will be used for voice processing and responses. Keys are stored securely in your system keychain.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

struct MCPServersConfigCard: View {
    @ObservedObject var aiConfig: AIConfiguration
    @Binding var showingMCPServerForm: Bool
    
    var body: some View {
        GroupBox(label: Text("MCP Servers").font(.headline)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Model Context Protocol (MCP) servers provide additional capabilities and data sources for AI interactions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if aiConfig.mcpServers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                        Text("No MCP servers configured")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Add MCP servers to extend AI capabilities")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(Array(aiConfig.mcpServers.enumerated()), id: \.element.id) { index, server in
                        MCPServerRow(
                            server: server,
                            onDelete: {
                                aiConfig.removeMCPServer(at: index)
                            }
                        )
                    }
                }
                
                Button("Add MCP Server") {
                    showingMCPServerForm = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}

struct MCPServerRow: View {
    let server: MCPServer
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(server.url.isEmpty ? "No URL configured" : server.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
            
            Spacer()
            
            Toggle("", isOn: .constant(server.isEnabled))
                .toggleStyle(.switch)
                .disabled(true) // Disabled in stub version
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MCPServerFormView: View {
    @ObservedObject var aiConfig: AIConfiguration
    @Environment(\.dismiss) private var dismiss
    
    @State private var serverName = ""
    @State private var serverURL = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Information")) {
                    TextField("Server Name", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Server URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section(header: Text("Examples")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• File System: mcp://filesystem")
                        Text("• Database: mcp://postgres://localhost:5432/db")
                        Text("• Web Search: mcp://search-api")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let newServer = MCPServer(name: serverName, url: serverURL)
                        aiConfig.mcpServers.append(newServer)
                        aiConfig.saveToUserDefaults()
                        dismiss()
                    }
                    .disabled(serverName.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

// Preview removed for command-line build compatibility