import SwiftUI

struct MCPConfigurationView: View {
    @ObservedObject var mcpManager: MCPManager
    @State private var showAddServerSheet = false
    @State private var selectedServer: MCPServerConfig?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                Text("MCP Servers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showAddServerSheet = true }) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            if mcpManager.servers.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(mcpManager.servers) { server in
                            MCPServerRow(
                                server: server,
                                state: mcpManager.serverStates[server.id],
                                mcpManager: mcpManager,
                                onEdit: { selectedServer = server }
                            )
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showAddServerSheet) {
            MCPServerEditSheet(
                mcpManager: mcpManager,
                server: nil
            )
        }
        .sheet(item: $selectedServer) { server in
            MCPServerEditSheet(
                mcpManager: mcpManager,
                server: server
            )
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No MCP Servers Configured")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add MCP servers to extend your assistant with tools and resources")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showAddServerSheet = true }) {
                Label("Add Your First Server", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Server Row

struct MCPServerRow: View {
    let server: MCPServerConfig
    let state: MCPServerState?
    @ObservedObject var mcpManager: MCPManager
    let onEdit: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                    
                    Text("\(server.command) \(server.args.joined(separator: " "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 8) {
                    if let state = state, state.isConnected {
                        Text("\(state.availableTools.count) tools")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("", isOn: .init(
                        get: { server.enabled },
                        set: { newValue in
                            var updatedServer = server
                            updatedServer.enabled = newValue
                            mcpManager.updateServer(updatedServer)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { mcpManager.removeServer(server.id) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Error message
            if let error = state?.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)
            }
            
            // Expanded content - Tools
            if isExpanded, let state = state, state.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    Text("Available Tools")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if state.availableTools.isEmpty {
                        Text("No tools available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(state.availableTools) { tool in
                            HStack {
                                Toggle(isOn: .init(
                                    get: {
                                        server.selectedTools.isEmpty || server.selectedTools.contains(tool.id)
                                    },
                                    set: { _ in
                                        mcpManager.toggleTool(serverId: server.id, toolName: tool.id)
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.id)
                                            .font(.system(.body, design: .monospaced))
                                        
                                        if let description = tool.description {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    // Resources section
                    if !state.availableResources.isEmpty {
                        Divider()
                        
                        Text("Available Resources")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ForEach(state.availableResources) { resource in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.name)
                                    .font(.system(.body, design: .monospaced))
                                
                                if let description = resource.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var statusColor: Color {
        guard let state = state else { return .gray }
        if !server.enabled { return .gray }
        return state.isConnected ? .green : .orange
    }
}

// MARK: - Server Edit Sheet

struct MCPServerEditSheet: View {
    @ObservedObject var mcpManager: MCPManager
    let server: MCPServerConfig?
    
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var environment: [String: String] = [:]
    @State private var newEnvKey: String = ""
    @State private var newEnvValue: String = ""
    @State private var enabled: Bool = true
    
    @Environment(\.dismiss) var dismiss
    
    var isEditing: Bool { server != nil }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(isEditing ? "Edit MCP Server" : "Add MCP Server")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            Form {
                Section("Server Configuration") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Command", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Path to the MCP server executable")
                    
                    TextField("Arguments (space-separated)", text: $args)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Command line arguments for the server")
                    
                    Toggle("Enable on startup", isOn: $enabled)
                }
                
                Section("Environment Variables") {
                    VStack(alignment: .leading, spacing: 8) {
                        if environment.isEmpty {
                            Text("No environment variables set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(environment.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(minWidth: 80, alignment: .leading)
                                    
                                    Text("=")
                                        .foregroundColor(.secondary)
                                    
                                    Text(environment[key] ?? "")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        environment.removeValue(forKey: key)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        
                        Divider()
                        
                        // Add new environment variable
                        HStack {
                            TextField("Variable name", text: $newEnvKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Text("=")
                                .foregroundColor(.secondary)
                            
                            TextField("Value", text: $newEnvValue)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Button("Add") {
                                if !newEnvKey.isEmpty {
                                    environment[newEnvKey] = newEnvValue
                                    newEnvKey = ""
                                    newEnvValue = ""
                                }
                            }
                            .disabled(newEnvKey.isEmpty)
                        }
                        
                        Text("Environment variables support $VAR and ${VAR} expansion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Examples") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Node.js server:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Command: node")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Arguments: ${HOME}/mcp-servers/server.js")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Text("Python server with environment variables:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Command: python3")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Arguments: -m $MCP_MODULE")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Environment: MCP_MODULE=my_mcp_server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Text("Server with API key:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("Environment: API_KEY=your-secret-key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Arguments: --api-key=${API_KEY}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(isEditing ? "Save" : "Add") {
                    saveServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || command.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            if let server = server {
                name = server.name
                command = server.command
                args = server.args.joined(separator: " ")
                environment = server.environment
                enabled = server.enabled
            }
        }
    }
    
    private func saveServer() {
        let argsArray = args.split(separator: " ").map(String.init)
        
        if let existingServer = server {
            var updated = existingServer
            updated.name = name
            updated.command = command
            updated.args = argsArray
            updated.environment = environment
            updated.enabled = enabled
            mcpManager.updateServer(updated)
        } else {
            let newServer = MCPServerConfig(
                name: name,
                command: command,
                args: argsArray,
                environment: environment,
                enabled: enabled
            )
            mcpManager.addServer(newServer)
        }
        
        dismiss()
    }
}