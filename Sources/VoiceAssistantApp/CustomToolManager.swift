import Foundation
import Combine

@MainActor
class CustomToolManager: ObservableObject {
    @Published var customTools: [CustomToolConfig] = []
    
    private let customToolsKey = "CustomToolConfigs"
    
    init() {
        loadCustomTools()
    }
    
    func loadCustomTools() {
        if let data = UserDefaults.standard.data(forKey: customToolsKey),
           let tools = try? JSONDecoder().decode([CustomToolConfig].self, from: data) {
            self.customTools = tools
        }
    }
    
    func saveCustomTools() {
        if let data = try? JSONEncoder().encode(customTools) {
            UserDefaults.standard.set(data, forKey: customToolsKey)
        }
    }
    
    func addCustomTool(_ tool: CustomToolConfig) {
        customTools.append(tool)
        saveCustomTools()
    }
    
    func updateCustomTool(_ tool: CustomToolConfig) {
        if let index = customTools.firstIndex(where: { $0.id == tool.id }) {
            customTools[index] = tool
            saveCustomTools()
        }
    }
    
    func deleteCustomTool(_ tool: CustomToolConfig) {
        customTools.removeAll { $0.id == tool.id }
        saveCustomTools()
    }
    
    func getEnabledTools() -> [CustomToolConfig] {
        return customTools.filter { $0.isEnabled }
    }
    
    func executeCustomTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = customTools.first(where: { 
            "custom_\($0.name.replacingOccurrences(of: " ", with: "_").lowercased())" == name 
        }) else {
            throw CustomToolError.toolNotFound(name)
        }
        
        print("CustomTool: Executing tool '\(name)' with arguments: \(arguments)")
        
        // Prepare the command with arguments
        var command = tool.command
        
        // Replace argument placeholders in the command
        for (argName, argValue) in arguments {
            // Try both with and without spaces
            let placeholders = [
                "{{\(argName)}}",
                "{{ \(argName) }}",
                "{\(argName)}"
            ]
            
            let replacement = String(describing: argValue)
            
            for placeholder in placeholders {
                let newCommand = command.replacingOccurrences(of: placeholder, with: replacement)
                if newCommand != command {
                    command = newCommand
                    print("CustomTool: Replaced '\(placeholder)' with '\(replacement)'")
                }
            }
        }
        
        print("CustomTool: Final command: \(command)")
        
        // Set up the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in tool.environmentVariables {
            environment[key] = value
        }
        process.environment = environment
        
        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the process
        try process.run()
        process.waitUntilExit()
        
        // Get the output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw CustomToolError.executionFailed(error.isEmpty ? "Process exited with status \(process.terminationStatus)" : error)
        }
        
        return output.isEmpty ? error : output
    }
}

enum CustomToolError: LocalizedError {
    case toolNotFound(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Custom tool not found: \(name)"
        case .executionFailed(let message):
            return "Custom tool execution failed: \(message)"
        }
    }
}