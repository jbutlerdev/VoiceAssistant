import Foundation

// MARK: - MCP Server Configuration

struct MCPServerConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var args: [String]
    var environment: [String: String] // Environment variables for the server process
    var enabled: Bool
    var selectedTools: Set<String> // Tool names that are enabled
    
    init(id: UUID = UUID(), name: String, command: String, args: [String] = [], environment: [String: String] = [:], enabled: Bool = true, selectedTools: Set<String> = []) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.environment = environment
        self.enabled = enabled
        self.selectedTools = selectedTools
    }
}

// MARK: - MCP Tool Information

struct MCPToolInfo: Identifiable, Hashable {
    let id: String // Tool name
    let description: String?
    let inputSchema: [String: Any]?
    
    init(name: String, description: String? = nil, inputSchema: [String: Any]? = nil) {
        self.id = name
        self.description = description
        self.inputSchema = inputSchema
    }
    
    static func == (lhs: MCPToolInfo, rhs: MCPToolInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - MCP Resource Information

struct MCPResourceInfo: Identifiable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
    
    var id: String { uri }
}

// MARK: - MCP Server State

struct MCPServerState {
    var config: MCPServerConfig
    var isConnected: Bool = false
    var availableTools: [MCPToolInfo] = []
    var availableResources: [MCPResourceInfo] = []
    var lastError: String?
    var connectionTime: Date?
}