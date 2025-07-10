import Foundation
import Combine
import MCP

#if canImport(System)
import System
#else
import SystemPackage
#endif

@MainActor
class MCPManager: ObservableObject {
    @Published var servers: [MCPServerConfig] = []
    @Published var serverStates: [UUID: MCPServerState] = [:]
    @Published var isConnecting: Bool = false
    
    private var clients: [UUID: Client] = [:]  // MCP clients
    private var transports: [UUID: StdioTransport] = [:]  // MCP transports
    private var processes: [UUID: Process] = [:]  // Subprocess processes
    private var cancellables = Set<AnyCancellable>()
    
    private let storageKey = "MCPServerConfigs"
    
    init() {
        loadServers()
    }
    
    // MARK: - Server Management
    
    func addServer(_ config: MCPServerConfig) {
        servers.append(config)
        serverStates[config.id] = MCPServerState(config: config)
        saveServers()
        
        if config.enabled {
            Task {
                await connectToServer(config.id)
            }
        }
    }
    
    func updateServer(_ config: MCPServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == config.id }) {
            servers[index] = config
            
            // Update state config
            if var state = serverStates[config.id] {
                state.config = config
                serverStates[config.id] = state
            }
            
            saveServers()
            
            // Reconnect if needed
            if config.enabled && !isConnected(serverId: config.id) {
                Task {
                    await connectToServer(config.id)
                }
            } else if !config.enabled && isConnected(serverId: config.id) {
                Task {
                    await disconnectFromServer(config.id)
                }
            }
        }
    }
    
    func removeServer(_ id: UUID) {
        Task {
            await disconnectFromServer(id)
            servers.removeAll { $0.id == id }
            serverStates.removeValue(forKey: id)
            saveServers()
        }
    }
    
    // MARK: - Command Resolution
    
    private func resolveCommandPath(_ command: String) -> String {
        // If it's already an absolute path, use it as-is
        if command.hasPrefix("/") {
            return command
        }
        
        // Try to find the command in PATH
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress error output
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("MCP: Failed to resolve command path for '\(command)': \(error)")
        }
        
        // Fallback: try common paths for Node.js commands
        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)"
        ]
        
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Last resort: return original command and hope it works
        print("MCP: Warning - Could not resolve command path for '\(command)', using as-is")
        return command
    }
    
    // MARK: - Environment Variable Expansion
    
    private func expandEnvironmentVariables(in text: String, with customEnv: [String: String] = [:]) -> String {
        var result = text
        
        // Create combined environment (custom env overrides system env)
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in customEnv {
            environment[key] = value
        }
        
        // Replace ${VAR} and $VAR patterns
        let patterns = [
            "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}",  // ${VAR}
            "\\$([A-Za-z_][A-Za-z0-9_]*)"         // $VAR
        ]
        
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            
            while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
                let fullMatchRange = Range(match.range, in: result)!
                let varNameRange = Range(match.range(at: 1), in: result)!
                let varName = String(result[varNameRange])
                
                let replacement = environment[varName] ?? ""
                result.replaceSubrange(fullMatchRange, with: replacement)
            }
        }
        
        return result
    }
    
    private func expandEnvironmentVariables(in args: [String], with customEnv: [String: String] = [:]) -> [String] {
        return args.map { expandEnvironmentVariables(in: $0, with: customEnv) }
    }
    
    // MARK: - Connection Management
    
    func connectToServer(_ serverId: UUID) async {
        guard let config = servers.first(where: { $0.id == serverId }) else { return }
        
        isConnecting = true
        defer { isConnecting = false }
        
        // Expand environment variables in command and args
        let expandedCommand = expandEnvironmentVariables(in: config.command, with: config.environment)
        let expandedArgs = expandEnvironmentVariables(in: config.args, with: config.environment)
        
        // Resolve command path (handles commands like 'npx' that need PATH resolution)
        let resolvedCommandPath = resolveCommandPath(expandedCommand)
        
        print("MCP: Connecting to server \(config.name)")
        print("MCP: Original command: \(config.command)")
        print("MCP: Expanded command: \(expandedCommand)")
        print("MCP: Resolved command path: \(resolvedCommandPath)")
        print("MCP: Args: \(expandedArgs)")
        print("MCP: Environment: \(config.environment)")
        
        var state = serverStates[serverId] ?? MCPServerState(config: config)
        
        do {
            // Create subprocess for the MCP server
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedCommandPath)
            process.arguments = expandedArgs
            
            // Set up environment variables
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in config.environment {
                environment[key] = value
            }
            process.environment = environment
            
            // Create pipes for stdio communication
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = Pipe() // Capture stderr
            
            // Start the process
            try process.run()
            processes[serverId] = process
            
            // Create file descriptors from pipes
            let inputFD = FileDescriptor(rawValue: inputPipe.fileHandleForWriting.fileDescriptor)
            let outputFD = FileDescriptor(rawValue: outputPipe.fileHandleForReading.fileDescriptor)
            
            // Create StdioTransport with the file descriptors
            let transport = StdioTransport(
                input: outputFD,  // Read from process stdout
                output: inputFD   // Write to process stdin
            )
            
            // Create MCP client with proper identification
            let client = Client(name: "VoiceAssistant", version: "1.0.0")
            
            // Store transport and client
            transports[serverId] = transport
            clients[serverId] = client
            
            // Connect to the MCP server (this automatically initializes)
            print("MCP: Attempting to connect to server...")
            
            let result: Initialize.Result
            do {
                result = try await client.connect(transport: transport)
            } catch {
                print("MCP: Connection failed during handshake: \(error)")
                if error.localizedDescription.contains("Method not found") {
                    throw NSError(domain: "MCPError", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "MCP handshake failed - Server may not implement required MCP protocol methods. Ensure you're using a compatible MCP server."
                    ])
                }
                throw error
            }
            
            print("MCP: Connected to server \(config.name)")
            print("MCP: Server info: \(result.serverInfo)")
            print("MCP: Protocol version: \(result.protocolVersion)")
            print("MCP: Server name: \(result.serverInfo.name), version: \(result.serverInfo.version)")
            
            // Give the server a moment to fully initialize
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second - increased for slow servers
            
            // List available tools
            print("MCP: Listing available tools...")
            var availableTools: [MCPToolInfo] = []
            do {
                let toolsResult = try await client.listTools()
                print("MCP: Found \(toolsResult.tools.count) tools")
                
                // Convert MCP tools to our internal format
                availableTools = toolsResult.tools.map { tool in
                    MCPToolInfo(
                        name: tool.name,
                        description: tool.description,
                        inputSchema: convertInputSchemaToStringAny(tool.inputSchema)
                    )
                }
            } catch {
                print("MCP: Failed to list tools: \(error)")
                if error.localizedDescription.contains("Method not found") {
                    print("MCP: Server does not support tools/list method - this is optional in MCP")
                }
                // Continue without tools - server might not support tools
            }
            
            // List available resources if any
            print("MCP: Listing available resources...")
            var availableResources: [MCPResourceInfo] = []
            do {
                let resourcesResult = try await client.listResources()
                print("MCP: Found \(resourcesResult.resources.count) resources")
                
                availableResources = resourcesResult.resources.map { resource in
                    MCPResourceInfo(
                        uri: resource.uri,
                        name: resource.name,
                        description: resource.description,
                        mimeType: resource.mimeType
                    )
                }
            } catch {
                print("MCP: Failed to list resources: \(error)")
                if error.localizedDescription.contains("Method not found") {
                    print("MCP: Server does not support resources/list method - this is optional in MCP")
                }
                // Continue without resources - server might not support resources
            }
            
            // Update state with real data
            state.isConnected = true
            state.connectionTime = Date()
            state.lastError = nil
            state.availableTools = availableTools
            state.availableResources = availableResources
            
            serverStates[serverId] = state
            
            print("MCP: Successfully connected to server \(config.name) with \(availableTools.count) tools and \(availableResources.count) resources")
            
        } catch {
            print("MCP: Failed to connect to server \(config.name): \(error)")
            
            // Log more detailed error information
            if let mcpError = error as? MCPError {
                print("MCP: MCP-specific error: \(mcpError)")
            } else if let nsError = error as NSError? {
                print("MCP: NSError - Domain: \(nsError.domain), Code: \(nsError.code)")
                print("MCP: NSError - Description: \(nsError.localizedDescription)")
                print("MCP: NSError - UserInfo: \(nsError.userInfo)")
            }
            
            // Clean up on failure
            clients.removeValue(forKey: serverId)
            transports.removeValue(forKey: serverId)
            if let process = processes.removeValue(forKey: serverId) {
                process.terminate()
                process.waitUntilExit()
            }
            
            state.isConnected = false
            
            // Provide detailed error information for UI
            var errorMessage = error.localizedDescription
            if errorMessage.contains("Method not found") {
                errorMessage = "Method not found - Server may not support required MCP protocol methods. Try checking server version compatibility."
            } else if errorMessage.contains("npx") {
                errorMessage = "Command 'npx' not found. Please ensure Node.js and npm are installed: 'brew install node'"
            } else if errorMessage.contains("ENOENT") {
                errorMessage = "Command not found. Please check the command path and ensure the server executable exists."
            }
            
            state.lastError = errorMessage
            state.connectionTime = nil
            
            serverStates[serverId] = state
        }
    }
    
    func disconnectFromServer(_ serverId: UUID) async {
        // Disconnect the client if it exists
        if let client = clients[serverId] {
            await client.disconnect()
            print("MCP: Disconnected client from server")
        }
        
        // Terminate the process if it exists
        if let process = processes[serverId] {
            process.terminate()
            process.waitUntilExit()
            print("MCP: Terminated server process")
        }
        
        // Clean up stored objects
        clients.removeValue(forKey: serverId)
        transports.removeValue(forKey: serverId)
        processes.removeValue(forKey: serverId)
        
        // Update state
        if var state = serverStates[serverId] {
            state.isConnected = false
            state.connectionTime = nil
            state.availableTools = []
            state.availableResources = []
            serverStates[serverId] = state
        }
    }
    
    func reconnectAllServers() async {
        for server in servers where server.enabled {
            await connectToServer(server.id)
        }
    }
    
    // MARK: - Tool Management
    
    func toggleTool(serverId: UUID, toolName: String) {
        guard var config = servers.first(where: { $0.id == serverId }) else { return }
        
        if config.selectedTools.contains(toolName) {
            config.selectedTools.remove(toolName)
        } else {
            config.selectedTools.insert(toolName)
        }
        
        updateServer(config)
    }
    
    func getAllEnabledTools() -> [(server: MCPServerConfig, tool: MCPToolInfo)] {
        var enabledTools: [(MCPServerConfig, MCPToolInfo)] = []
        
        for server in servers where server.enabled {
            if let state = serverStates[server.id], state.isConnected {
                for tool in state.availableTools {
                    if server.selectedTools.isEmpty || server.selectedTools.contains(tool.id) {
                        enabledTools.append((server, tool))
                    }
                }
            }
        }
        
        return enabledTools
    }
    
    // MARK: - Tool Execution
    
    func executeTool(serverId: UUID, toolName: String, arguments: [String: Any]) async throws -> Any {
        guard isConnected(serverId: serverId) else {
            throw MCPError.notConnected
        }
        
        guard let client = clients[serverId] else {
            throw MCPError.notConnected
        }
        
        print("MCP: Executing tool \(toolName) with arguments: \(arguments)")
        
        do {
            // Convert arguments to MCP Value format
            let mcpArguments = try convertArgumentsToMCPValues(arguments)
            
            // Execute the tool using the real MCP client
            let result = try await client.callTool(
                name: toolName,
                arguments: mcpArguments
            )
            
            print("MCP: Tool execution successful")
            print("MCP: Result: \(result)")
            
            // Return the content from the tool result
            if let content = result.content.first {
                switch content {
                case .text(let text):
                    return text
                case .image(let data, let mimeType, _):
                    return "Image result (type: \(mimeType), size: \(data.count) bytes)"
                case .resource(let uri, let mimeType, let text):
                    if let text = text {
                        return text
                    } else {
                        return "Resource result: \(uri) (type: \(mimeType))"
                    }
                case .audio(let data, let mimeType):
                    return "Audio result (type: \(mimeType), size: \(data.count) bytes)"
                }
            } else {
                return "Tool executed successfully but returned no content"
            }
            
        } catch {
            print("MCP: Tool execution failed: \(error)")
            throw MCPError.executionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    
    func isConnected(serverId: UUID) -> Bool {
        return serverStates[serverId]?.isConnected ?? false
    }
    
    private func convertArgumentsToMCPValues(_ arguments: [String: Any]) throws -> [String: Value] {
        var mcpArguments: [String: Value] = [:]
        
        for (key, value) in arguments {
            mcpArguments[key] = try convertToMCPValue(value)
        }
        
        return mcpArguments
    }
    
    private func convertToMCPValue(_ value: Any) throws -> Value {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            let convertedArray = try array.map { try convertToMCPValue($0) }
            return .array(convertedArray)
        case let dict as [String: Any]:
            let convertedDict = try convertArgumentsToMCPValues(dict)
            return .object(convertedDict)
        case is NSNull:
            return .null
        default:
            // For other types, try to convert to string as fallback
            return .string(String(describing: value))
        }
    }
    
    private func convertValueToAny(_ value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(let mimeType, let data):
            return ["mimeType": mimeType as Any, "data": data]
        case .array(let array):
            return array.map { convertValueToAny($0) }
        case .object(let object):
            return object.mapValues { convertValueToAny($0) }
        }
    }
    
    private func convertInputSchemaToStringAny(_ inputSchema: Value?) -> [String: Any]? {
        guard let inputSchema = inputSchema else { return nil }
        guard let objectValue = inputSchema.objectValue else { return nil }
        return objectValue.mapValues { convertValueToAny($0) }
    }
    
    // MARK: - Persistence
    
    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            servers = decoded
            
            // Initialize states
            for server in servers {
                serverStates[server.id] = MCPServerState(config: server)
            }
            
            // Connect to enabled servers
            Task {
                await reconnectAllServers()
            }
        }
    }
}

// MARK: - Error Types

enum MCPError: LocalizedError {
    case notConnected
    case toolNotFound
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Server not connected"
        case .toolNotFound:
            return "Tool not found"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}