import Foundation

struct CustomToolConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var command: String
    var arguments: [CustomToolArgument]
    var environmentVariables: [String: String]
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        command: String = "",
        arguments: [CustomToolArgument] = [],
        environmentVariables: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.arguments = arguments
        self.environmentVariables = environmentVariables
        self.isEnabled = isEnabled
    }
}

struct CustomToolArgument: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var type: ArgumentType
    var required: Bool
    var defaultValue: String?
    
    enum ArgumentType: String, Codable, CaseIterable {
        case string
        case number
        case boolean
        case array
        case object
    }
    
    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        type: ArgumentType = .string,
        required: Bool = false,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}

extension CustomToolConfig {
    func toOpenAITool() -> OpenAITool {
        var properties: [String: [String: Any]] = [:]
        var required: [String] = []
        
        for arg in arguments {
            var property: [String: Any] = [
                "type": arg.type.rawValue,
                "description": arg.description
            ]
            
            if let defaultValue = arg.defaultValue {
                property["default"] = defaultValue
            }
            
            properties[arg.name] = property
            
            if arg.required {
                required.append(arg.name)
            }
        }
        
        let parameters: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required
        ]
        
        return OpenAITool(
            function: OpenAIFunction(
                name: "custom_\(name.replacingOccurrences(of: " ", with: "_").lowercased())",
                description: description,
                parameters: parameters
            )
        )
    }
}