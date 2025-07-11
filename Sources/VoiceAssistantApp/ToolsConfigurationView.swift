import SwiftUI

struct ToolsConfigurationView: View {
    @ObservedObject var mcpManager: MCPManager
    @StateObject private var customToolManager = CustomToolManager()
    @State private var showAddServerSheet = false
    @State private var selectedServer: MCPServerConfig?
    @State private var showAddToolSheet = false
    @State private var selectedTool: CustomToolConfig?
    @State private var splitRatio: CGFloat = 0.67
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    
                    Text("Tools Configuration")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Split view
                VStack(spacing: 0) {
                    // MCP Servers section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("MCP Servers")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button(action: { showAddServerSheet = true }) {
                                Label("Add Server", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        if mcpManager.servers.isEmpty {
                            mcpEmptyStateView
                                .frame(height: geometry.size.height * splitRatio - 100)
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
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            .frame(height: geometry.size.height * splitRatio - 100)
                        }
                    }
                    .frame(height: geometry.size.height * splitRatio)
                    
                    Divider()
                        .padding(.vertical, 5)
                    
                    // Custom Tools section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Custom Tools")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button(action: { showAddToolSheet = true }) {
                                Label("Add Tool", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        if customToolManager.customTools.isEmpty {
                            customToolsEmptyStateView
                                .frame(maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 15) {
                                    ForEach(customToolManager.customTools) { tool in
                                        CustomToolRow(
                                            tool: tool,
                                            customToolManager: customToolManager,
                                            onEdit: { selectedTool = tool }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(height: geometry.size.height * (1 - splitRatio))
                }
            }
        }
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
        .sheet(isPresented: $showAddToolSheet) {
            CustomToolEditSheet(
                customToolManager: customToolManager,
                tool: nil
            )
        }
        .sheet(item: $selectedTool) { tool in
            CustomToolEditSheet(
                customToolManager: customToolManager,
                tool: tool
            )
        }
        .onAppear {
            // Set the custom tool manager on the mcpManager for integration
            mcpManager.setCustomToolManager(customToolManager)
        }
    }
    
    private var mcpEmptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No MCP Servers Configured")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Add MCP servers to extend your assistant with external tools")
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
    
    private var customToolsEmptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No Custom Tools Configured")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Add custom zsh commands as tools for your assistant")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showAddToolSheet = true }) {
                Label("Add Your First Tool", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Custom Tool Row

struct CustomToolRow: View {
    let tool: CustomToolConfig
    @ObservedObject var customToolManager: CustomToolManager
    let onEdit: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.headline)
                    
                    Text(tool.command)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .font(.system(.body, design: .monospaced))
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 8) {
                    if !tool.arguments.isEmpty {
                        Text("\(tool.arguments.count) args")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("", isOn: .init(
                        get: { tool.isEnabled },
                        set: { newValue in
                            var updatedTool = tool
                            updatedTool.isEnabled = newValue
                            customToolManager.updateCustomTool(updatedTool)
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
                    
                    Button(action: { customToolManager.deleteCustomTool(tool) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Description
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    if !tool.arguments.isEmpty {
                        Text("Arguments")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ForEach(tool.arguments) { arg in
                            HStack(alignment: .top) {
                                Text(arg.name)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minWidth: 100, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(arg.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !arg.description.isEmpty {
                                        Text(arg.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if arg.required {
                                        Text("Required")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    if !tool.environmentVariables.isEmpty {
                        Divider()
                        
                        Text("Environment Variables")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(tool.environmentVariables.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                Text("=")
                                    .foregroundColor(.secondary)
                                Text(tool.environmentVariables[key] ?? "")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
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
}

// MARK: - Custom Tool Edit Sheet

struct CustomToolEditSheet: View {
    @ObservedObject var customToolManager: CustomToolManager
    let tool: CustomToolConfig?
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var command: String = ""
    @State private var arguments: [CustomToolArgument] = []
    @State private var environmentVariables: [String: String] = [:]
    @State private var isEnabled: Bool = true
    
    @State private var newEnvKey: String = ""
    @State private var newEnvValue: String = ""
    
    @Environment(\.dismiss) var dismiss
    
    var isEditing: Bool { tool != nil }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(isEditing ? "Edit Custom Tool" : "Add Custom Tool")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Basic Configuration
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Basic Configuration")
                            .font(.headline)
                        
                        TextField("Tool Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .help("A unique name for this tool")
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Description")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextEditor(text: $description)
                                .font(.system(.body))
                                .frame(height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        
                        TextField("Command or Path", text: $command)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .help("The zsh command or path to script to execute. You can use {{argName}} placeholders.")
                        
                        Toggle("Enable tool", isOn: $isEnabled)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // Arguments
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Arguments")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: addArgument) {
                                Label("Add Argument", systemImage: "plus.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if arguments.isEmpty {
                            Text("No arguments defined")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach($arguments) { $arg in
                                ArgumentEditRow(argument: $arg, onDelete: {
                                    arguments.removeAll { $0.id == arg.id }
                                })
                            }
                        }
                        
                        Text("Use {{argumentName}} in your command to reference arguments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // Environment Variables
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Environment Variables")
                            .font(.headline)
                        
                        if environmentVariables.isEmpty {
                            Text("No environment variables set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(Array(environmentVariables.keys.sorted()), id: \.self) { key in
                                HStack {
                                    Text(key)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(minWidth: 100, alignment: .leading)
                                    
                                    Text("=")
                                        .foregroundColor(.secondary)
                                    
                                    Text(environmentVariables[key] ?? "")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        environmentVariables.removeValue(forKey: key)
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
                                    environmentVariables[newEnvKey] = newEnvValue
                                    newEnvKey = ""
                                    newEnvValue = ""
                                }
                            }
                            .disabled(newEnvKey.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    
                    // Examples
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Examples")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Group {
                                Text("Simple command:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("ls -la {{path}}")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            Divider()
                            
                            Group {
                                Text("Script with environment variables:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("python3 ~/scripts/my_tool.py --input {{input}} --output {{output}}")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                                Text("With PYTHONPATH=/Users/me/lib in environment variables")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Group {
                                Text("Complex command with pipes:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("cat {{file}} | grep {{pattern}} | wc -l")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(isEditing ? "Save" : "Add") {
                    saveTool()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || command.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 600, height: 700)
        .onAppear {
            if let tool = tool {
                name = tool.name
                description = tool.description
                command = tool.command
                arguments = tool.arguments
                environmentVariables = tool.environmentVariables
                isEnabled = tool.isEnabled
            }
        }
    }
    
    private func addArgument() {
        arguments.append(CustomToolArgument())
    }
    
    private func saveTool() {
        let newTool = CustomToolConfig(
            id: tool?.id ?? UUID(),
            name: name,
            description: description,
            command: command,
            arguments: arguments,
            environmentVariables: environmentVariables,
            isEnabled: isEnabled
        )
        
        if isEditing {
            customToolManager.updateCustomTool(newTool)
        } else {
            customToolManager.addCustomTool(newTool)
        }
        
        dismiss()
    }
}

// MARK: - Argument Edit Row

struct ArgumentEditRow: View {
    @Binding var argument: CustomToolArgument
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $argument.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                
                Picker("Type", selection: $argument.type) {
                    ForEach(CustomToolArgument.ArgumentType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .frame(width: 100)
                
                Toggle("Required", isOn: $argument.required)
                    .toggleStyle(.checkbox)
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                TextField("Description", text: $argument.description)
                    .textFieldStyle(.roundedBorder)
                
                if !argument.required {
                    TextField("Default Value", text: Binding(
                        get: { argument.defaultValue ?? "" },
                        set: { argument.defaultValue = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}