import Foundation
import Combine
import Network
import OSLog

// Helper actor to manage continuation state safely
private actor ContinuationWrapper {
    private var hasResumed = false
    private let continuation: CheckedContinuation<Bool, Error>
    
    init(continuation: CheckedContinuation<Bool, Error>) {
        self.continuation = continuation
    }
    
    func resume(with result: Result<Bool, Error>, cleanup: () -> Void) {
        guard !hasResumed else { return }
        hasResumed = true
        cleanup()
        continuation.resume(with: result)
    }
    
    func hasAlreadyResumed() -> Bool {
        return hasResumed
    }
}

// MARK: - OpenAI API Models
struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double
    let tools: [OpenAITool]?
    let toolChoice: OpenAIToolChoice?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case tools
        case toolChoice = "tool_choice"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [OpenAIToolCall]?
    let toolCallId: String?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallId = nil
    }
    
    init(role: String, toolCalls: [OpenAIToolCall]) {
        self.role = role
        self.content = nil
        self.toolCalls = toolCalls
        self.toolCallId = nil
    }
    
    init(role: String, content: String, toolCallId: String) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallId = toolCallId
    }
}

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAIError: Codable {
    let error: OpenAIErrorDetail
}

struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

// MARK: - OpenAI Function Calling Models

struct OpenAITool: Codable {
    let type: String
    let function: OpenAIFunction
    
    init(function: OpenAIFunction) {
        self.type = "function"
        self.function = function
    }
}

struct OpenAIFunction: Codable {
    let name: String
    let description: String?
    let parameters: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
    
    init(name: String, description: String? = nil, parameters: [String: Any]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        
        if let parameters = parameters {
            let jsonData = try JSONSerialization.data(withJSONObject: parameters)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            try container.encode(AnyCodable(jsonObject), forKey: .parameters)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        if let parametersData = try container.decodeIfPresent(AnyCodable.self, forKey: .parameters) {
            parameters = parametersData.value as? [String: Any]
        } else {
            parameters = nil
        }
    }
}

enum OpenAIToolChoice: Codable {
    case none
    case auto
    case required
    case function(String)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none:
            try container.encode("none")
        case .auto:
            try container.encode("auto")
        case .required:
            try container.encode("required")
        case .function(let name):
            struct FunctionChoice: Codable {
                let type: String
                let function: FunctionName
                
                struct FunctionName: Codable {
                    let name: String
                }
            }
            let functionSpec = FunctionChoice(type: "function", function: FunctionChoice.FunctionName(name: name))
            try container.encode(functionSpec)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            switch string {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default: throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid tool choice"))
            }
        } else {
            let dict = try container.decode([String: [String: [String: String]]].self)
            if let functionName = dict["function"]?["function"]?["name"] {
                self = .function(functionName)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid tool choice format"))
            }
        }
    }
}

struct OpenAIToolCall: Codable {
    let id: String
    let type: String
    let function: OpenAIFunctionCall
}

struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

// Helper for encoding/decoding Any values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map(AnyCodable.init))
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues(AnyCodable.init))
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode value"))
        }
    }
}

// MARK: - Tool Call Display Models

struct ToolCallDisplay: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: String
    let result: String
    let timestamp: Date
}

// MARK: - Chat Request/Response Models

struct ChatRequest: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
    let baseURL: String
    let apiKey: String
    let model: String
    let maxTokens: Int
    let systemPrompt: String
    let removeThinkTags: Bool
    
    init(message: String, baseURL: String, apiKey: String, model: String, maxTokens: Int = 32768, systemPrompt: String = "You are a helpful assistant.", removeThinkTags: Bool = true) {
        self.message = message
        self.timestamp = Date()
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.removeThinkTags = removeThinkTags
    }
}

struct ChatResponse: Identifiable {
    let id = UUID()
    let requestId: UUID
    let message: String
    let response: String?
    let error: String?
    let toolCalls: [ToolCallDisplay]
    let timestamp: Date
    let isProcessing: Bool
    
    init(requestId: UUID, message: String, response: String? = nil, error: String? = nil, toolCalls: [ToolCallDisplay] = [], isProcessing: Bool = false) {
        self.requestId = requestId
        self.message = message
        self.response = response
        self.error = error
        self.toolCalls = toolCalls
        self.timestamp = Date()
        self.isProcessing = isProcessing
    }
}

// MARK: - OpenAI Service
@MainActor
class OpenAIService: ObservableObject {
    // Legacy properties for backward compatibility
    @Published var lastResponse: String = ""
    @Published var lastError: String?
    @Published var isProcessing: Bool = false
    @Published var hasRequestedNetworkAccess: Bool = false
    @Published var currentToolCalls: [ToolCallDisplay] = []
    
    // New concurrent chat properties
    @Published var activeRequests: [ChatRequest] = []
    @Published var chatResponses: [ChatResponse] = []
    @Published var responseQueue: [ChatResponse] = [] // Queue for TTS
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.voiceassistant.app", category: "LocalNetworkAuth")
    private let serviceType = "_preflight_check._tcp"
    private var mcpManager: MCPManager?
    
    func setMCPManager(_ manager: MCPManager) {
        mcpManager = manager
    }
    
    private func removeThinkTagsFromResponse(_ text: String) -> String {
        var result = text
        
        print("DEBUG: Original text: \"\(text)\"")
        
        // More aggressive approach to handle all think tag scenarios
        do {
            // Step 1: Remove everything before the first actual content after think tags
            // This handles cases where think tags appear at the beginning
            if result.contains("<think>") || result.contains("<thinking>") {
                // Find the first <think> or <thinking> tag
                var firstThinkRange: Range<String.Index>?
                
                if let thinkRange = result.range(of: "<think>", options: .caseInsensitive) {
                    firstThinkRange = thinkRange
                }
                
                if let thinkingRange = result.range(of: "<thinking>", options: .caseInsensitive) {
                    if firstThinkRange == nil || thinkingRange.lowerBound < firstThinkRange!.lowerBound {
                        firstThinkRange = thinkingRange
                    }
                }
                
                if let range = firstThinkRange {
                    let beforeThink = String(result[..<range.lowerBound])
                    print("DEBUG: Content before first think tag: \"\(beforeThink)\"")
                    
                    // If there's only whitespace before the first think tag, remove it
                    if beforeThink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result = String(result[range.lowerBound...])
                        print("DEBUG: Removed content before think tag")
                    }
                }
            }
            
            // Step 2: Remove all <think>...</think> and <thinking>...</thinking> blocks
            // Use a greedy approach to handle nested tags better
            let thinkPattern = try NSRegularExpression(
                pattern: "<think(?:ing)?>.*?</think(?:ing)?>", 
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            )
            
            let maxIterations = 10  // Prevent infinite loops
            var iteration = 0
            
            while (result.contains("<think>") || result.contains("<thinking>")) && iteration < maxIterations {
                let range = NSRange(result.startIndex..., in: result)
                let beforeReplace = result
                result = thinkPattern.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
                
                print("DEBUG: Iteration \(iteration + 1): Removed \(beforeReplace.count - result.count) characters")
                
                // If no change occurred, break to prevent infinite loop
                if beforeReplace == result {
                    break
                }
                iteration += 1
            }
            
            // Step 3: Handle any remaining orphaned tags (malformed tags) and variations
            result = result.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
            result = result.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
            result = result.replacingOccurrences(of: "<thinking>", with: "", options: .caseInsensitive)
            result = result.replacingOccurrences(of: "</thinking>", with: "", options: .caseInsensitive)
            
            // Step 4: More aggressive content extraction - look for actual response content
            // If we still have content that looks like it might contain think remnants,
            // try to extract just the final response part
            if result.contains("</think>") || result.contains("<think>") || result.contains("</thinking>") || result.contains("<thinking>") {
                print("DEBUG: Still contains think tags after processing, trying alternative extraction")
                
                // Try to find content after the last </think> or </thinking>
                var lastCloseRange: Range<String.Index>?
                
                if let thinkRange = result.range(of: "</think>", options: [.caseInsensitive, .backwards]) {
                    lastCloseRange = thinkRange
                }
                
                if let thinkingRange = result.range(of: "</thinking>", options: [.caseInsensitive, .backwards]) {
                    if lastCloseRange == nil || thinkingRange.upperBound > lastCloseRange!.upperBound {
                        lastCloseRange = thinkingRange
                    }
                }
                
                if let range = lastCloseRange {
                    let afterLastThink = String(result[range.upperBound...])
                    if !afterLastThink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result = afterLastThink
                        print("DEBUG: Extracted content after last think tag")
                    }
                }
            }
            
        } catch {
            print("Regex error in think tags removal: \(error)")
            // More aggressive fallback
            result = result.replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
            result = result.replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
        }
        
        // Step 5: Clean up whitespace and normalize
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("DEBUG: Final result: \"\(result)\"")
        
        return result
    }
    
    func sendMessage(_ message: String, baseURL: String, apiKey: String, model: String, maxTokens: Int = 32768, systemPrompt: String = "You are a helpful assistant.", removeThinkTags: Bool = true) {
        // Create new concurrent request
        let request = ChatRequest(
            message: message,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt,
            removeThinkTags: removeThinkTags
        )
        
        sendConcurrentMessage(request)
    }
    
    func sendConcurrentMessage(_ request: ChatRequest) {
        guard !request.baseURL.isEmpty, !request.apiKey.isEmpty, !request.model.isEmpty else {
            let errorResponse = ChatResponse(
                requestId: request.id,
                message: request.message,
                error: "OpenAI configuration is incomplete"
            )
            chatResponses.append(errorResponse)
            return
        }
        
        // Add to active requests
        activeRequests.append(request)
        
        // Create initial processing response
        let processingResponse = ChatResponse(
            requestId: request.id,
            message: request.message,
            isProcessing: true
        )
        chatResponses.append(processingResponse)
        
        // Update legacy properties for backward compatibility
        if chatResponses.count == 1 {
            isProcessing = true
            lastError = nil
            currentToolCalls = []
        }
        
        // Construct the full URL
        let fullURL = request.baseURL.hasSuffix("/") ? request.baseURL + "v1/chat/completions" : request.baseURL + "/v1/chat/completions"
        
        guard let url = URL(string: fullURL) else {
            updateResponseWithError(requestId: request.id, error: "Invalid base URL")
            return
        }
        
        // Create enhanced system prompt with MCP tools
        let enhancedSystemPrompt = createEnhancedSystemPrompt(basePrompt: request.systemPrompt)
        
        // Get available MCP tools
        let tools = convertMCPToolsToOpenAI()
        
        // Create the request payload
        let openAIRequest = OpenAIRequest(
            model: request.model,
            messages: [
                OpenAIMessage(role: "system", content: enhancedSystemPrompt),
                OpenAIMessage(role: "user", content: request.message)
            ],
            temperature: 0.7,
            maxTokens: request.maxTokens,
            topP: 1.0,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )
        
        // Create URL request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(openAIRequest)
        } catch {
            updateResponseWithError(requestId: request.id, error: "Failed to encode request: \(error.localizedDescription)")
            return
        }
        
        // Log the API call details
        print("OpenAI API Call [\(request.id)]:")
        print("URL: \(fullURL)")
        print("Model: \(request.model)")
        print("Message: \"\(request.message)\"")
        print("Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")
        
        // Log request body (for debugging)
        if let bodyData = urlRequest.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("Request Body: \(bodyString)")
        }
        
        // Make the API call using basic URLSession (bypassing problematic Combine pipeline)
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Remove from active requests
                self.activeRequests.removeAll { $0.id == request.id }
                
                // Update legacy isProcessing
                self.isProcessing = !self.activeRequests.isEmpty
                
                if let error = error {
                    print("OpenAI Network Error [\(request.id)]: \(error)")
                    self.updateResponseWithError(requestId: request.id, error: error.localizedDescription)
                    return
                }
                
                guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                    self.updateResponseWithError(requestId: request.id, error: "Invalid response")
                    return
                }
                
                print("HTTP Status Code [\(request.id)]: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode >= 400 {
                    // Try to decode error response
                    do {
                        let errorResponse = try JSONDecoder().decode(OpenAIError.self, from: data)
                        self.updateResponseWithError(requestId: request.id, error: errorResponse.error.message)
                    } catch {
                        self.updateResponseWithError(requestId: request.id, error: "HTTP \(httpResponse.statusCode) error")
                    }
                    return
                }
                
                // Parse the response
                do {
                    let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    
                    print("OpenAI API Response [\(request.id)]:")
                    print("ID: \(openAIResponse.id)")
                    print("Model: \(openAIResponse.model)")
                    print("Choices: \(openAIResponse.choices.count)")
                    
                    if let usage = openAIResponse.usage {
                        print("Usage - Prompt: \(usage.promptTokens), Completion: \(usage.completionTokens), Total: \(usage.totalTokens)")
                    }
                    
                    if let firstChoice = openAIResponse.choices.first {
                        await self.handleConcurrentOpenAIResponse(choice: firstChoice, request: request)
                    } else {
                        self.updateResponseWithError(requestId: request.id, error: "No response choices returned")
                    }
                } catch {
                    print("JSON parsing error [\(request.id)]: \(error)")
                    self.updateResponseWithError(requestId: request.id, error: "Failed to parse response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    func clearResponse() {
        lastResponse = ""
        lastError = nil
        currentToolCalls = []
    }
    
    func clearAllResponses() {
        activeRequests.removeAll()
        chatResponses.removeAll()
        responseQueue.removeAll()
        clearResponse()
    }
    
    func removeResponse(id: UUID) {
        chatResponses.removeAll { $0.id == id }
        responseQueue.removeAll { $0.id == id }
    }
    
    // Request network access permission - this will trigger the system dialog
    func requestNetworkAccess() {
        print("OpenAI: Requesting local network access permission...")
        hasRequestedNetworkAccess = true
        
        Task {
            do {
                let hasPermission = try await requestLocalNetworkAuthorization()
                await MainActor.run {
                    if hasPermission {
                        print("OpenAI: Local network permission granted")
                        // Test connection after getting permission
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            self.testLocalServerConnection()
                        }
                    } else {
                        print("OpenAI: Local network permission denied or timed out")
                        print("OpenAI: Please check System Settings > Privacy & Security > Local Network")
                    }
                }
            } catch {
                await MainActor.run {
                    print("OpenAI: Error requesting local network permission: \(error)")
                }
            }
        }
    }
    
    private func testLocalServerConnection() {
        print("OpenAI: Testing connection to local server...")
        
        // Test direct connection to your server
        guard let url = URL(string: "http://10.10.199.146:8080/") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("OpenAI: Local server connection failed: \(error)")
                if let nsError = error as NSError? {
                    print("OpenAI: Error code: \(nsError.code), domain: \(nsError.domain)")
                    if nsError.code == -1009 {
                        print("OpenAI: *** LOCAL NETWORK ACCESS IS BLOCKED ***")
                        print("OpenAI: You need to manually add this app to System Settings > Privacy & Security > Local Network")
                    }
                }
            } else if let httpResponse = response as? HTTPURLResponse {
                print("OpenAI: Local server responded with status: \(httpResponse.statusCode)")
                print("OpenAI: *** LOCAL NETWORK ACCESS IS WORKING ***")
            }
        }.resume()
    }
    
    /// Requests local network authorization and triggers the system permission dialog
    nonisolated private func requestLocalNetworkAuthorization() async throws -> Bool {
        let queue = DispatchQueue(label: "com.homeassistant.voice.local.localNetworkAuth")
        
        logger.info("Setting up listener for local network authorization")
        let listener = try NWListener(using: NWParameters(tls: .none, tcp: NWProtocolTCP.Options()))
        listener.service = NWListener.Service(name: UUID().uuidString, type: serviceType)
        listener.newConnectionHandler = { _ in } // Required to prevent listener error
        
        logger.info("Setting up browser for local network authorization")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let continuationWrapper = ContinuationWrapper(continuation: continuation)
                
                @Sendable func completeWithResult(_ result: Result<Bool, Error>) {
                    Task {
                        await continuationWrapper.resume(with: result) { 
                            // Cleanup
                            listener.stateUpdateHandler = nil
                            browser.stateUpdateHandler = nil
                            browser.browseResultsChangedHandler = nil
                            listener.cancel()
                            browser.cancel()
                        }
                    }
                }
                
                // Set up listener state handler
                listener.stateUpdateHandler = { @Sendable state in
                    Task { @MainActor in
                        self.logger.info("Listener state changed: \(String(describing: state))")
                    }
                    switch state {
                    case .ready:
                        break
                    case .failed(let error):
                        completeWithResult(.failure(error))
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                
                // Set up browser state handler
                browser.stateUpdateHandler = { @Sendable state in
                    Task { @MainActor in
                        self.logger.info("Browser state changed: \(String(describing: state))")
                    }
                    switch state {
                    case .ready:
                        break
                    case .failed(let error):
                        completeWithResult(.failure(error))
                    case .cancelled:
                        break
                    case .waiting(_):
                        // This might indicate permission denied
                        completeWithResult(.success(false))
                    default:
                        break
                    }
                }
                
                // Set up browser results handler
                browser.browseResultsChangedHandler = { @Sendable results, changes in
                    Task { @MainActor in
                        self.logger.info("Browse results changed: \(results.count) results")
                    }
                    // If we get any results, permission is likely granted
                    if !results.isEmpty {
                        completeWithResult(.success(true))
                    }
                }
                
                // Start listener and browser
                listener.start(queue: queue)
                browser.start(queue: queue)
                
                // Set a timeout to avoid hanging indefinitely
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    let alreadyResumed = await continuationWrapper.hasAlreadyResumed()
                    
                    if !alreadyResumed {
                        Task { @MainActor in
                            self.logger.warning("Local network authorization timed out")
                        }
                        completeWithResult(.success(false))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.logger.info("Local network authorization cancelled")
            }
            listener.cancel()
            browser.cancel()
        }
    }
    
    // MARK: - MCP Integration
    
    private func createEnhancedSystemPrompt(basePrompt: String) -> String {
        guard let mcpManager = mcpManager else {
            return basePrompt
        }
        
        let enabledTools = mcpManager.getAllEnabledTools()
        let customTools = mcpManager.getAllEnabledCustomTools()
        
        if enabledTools.isEmpty && customTools.isEmpty {
            return basePrompt
        }
        
        var toolDescriptions: [String] = []
        
        // Add MCP tools
        for (server, tool) in enabledTools {
            var toolDesc = "- **\(tool.id)** (from \(server.name))"
            if let description = tool.description {
                toolDesc += ": \(description)"
            }
            toolDescriptions.append(toolDesc)
        }
        
        // Add custom tools
        for tool in customTools {
            toolDescriptions.append("- **\(tool.name)** (custom tool): \(tool.description)")
        }
        
        let toolsSection = """
        
        ## Available Tools
        You have access to the following tools that can help you perform actions and retrieve information:
        
        \(toolDescriptions.joined(separator: "\n"))
        
        These tools are fully active and ready to use. When a user request would benefit from using these tools, you can call them directly without asking for permission. The tools will be executed automatically and their results will be provided to you for crafting a natural response to the user.
        """
        
        return basePrompt + toolsSection
    }
    
    private func convertMCPToolsToOpenAI() -> [OpenAITool] {
        guard let mcpManager = mcpManager else { return [] }
        
        var allTools: [OpenAITool] = []
        
        // Add MCP tools
        let enabledTools = mcpManager.getAllEnabledTools()
        let mcpTools = enabledTools.map { (server, tool) in
            // Create function name by prefixing with server name to avoid conflicts
            let functionName = "\(server.name)_\(tool.id)"
            
            // Convert MCP input schema to OpenAI function parameters
            var parameters: [String: Any] = [
                "type": "object",
                "properties": [:],
                "required": []
            ]
            
            if let inputSchema = tool.inputSchema {
                parameters = inputSchema
            }
            
            let function = OpenAIFunction(
                name: functionName,
                description: tool.description ?? "Tool from \(server.name)",
                parameters: parameters
            )
            
            return OpenAITool(function: function)
        }
        allTools.append(contentsOf: mcpTools)
        
        // Add custom tools
        let customTools = mcpManager.getAllEnabledCustomTools()
        let customOpenAITools = customTools.map { $0.toOpenAITool() }
        allTools.append(contentsOf: customOpenAITools)
        
        return allTools
    }
    
    private func handleOpenAIResponse(choice: OpenAIChoice, originalMessage: String, baseURL: String, model: String, apiKey: String, systemPrompt: String, removeThinkTags: Bool = true) async {
        if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
            // Handle tool calls
            print("Received \(toolCalls.count) tool calls")
            await handleToolCalls(toolCalls: toolCalls, originalMessage: originalMessage, baseURL: baseURL, model: model, apiKey: apiKey, systemPrompt: systemPrompt, removeThinkTags: removeThinkTags)
        } else if let content = choice.message.content {
            // Handle regular text response
            print("Response: \(content)")
            self.lastResponse = removeThinkTags ? self.removeThinkTagsFromResponse(content) : content
        } else {
            self.lastError = "Empty response from AI"
        }
    }
    
    private func handleToolCalls(toolCalls: [OpenAIToolCall], originalMessage: String, baseURL: String, model: String, apiKey: String, systemPrompt: String, removeThinkTags: Bool = true) async {
        var toolResults: [String] = []
        
        for toolCall in toolCalls {
            print("Executing tool: \(toolCall.function.name)")
            print("Arguments: \(toolCall.function.arguments)")
            
            let resultString: String
            do {
                let result = try await executeToolCall(toolCall)
                resultString = String(describing: result)
                toolResults.append("Tool \(toolCall.function.name): \(resultString)")
            } catch {
                print("Tool execution failed: \(error)")
                resultString = "Error: \(error.localizedDescription)"
                toolResults.append("Tool \(toolCall.function.name) failed: \(error.localizedDescription)")
            }
            
            // Track tool call for UI display
            let toolCallDisplay = ToolCallDisplay(
                toolName: toolCall.function.name,
                arguments: toolCall.function.arguments,
                result: resultString,
                timestamp: Date()
            )
            currentToolCalls.append(toolCallDisplay)
        }
        
        // Send results back to AI for final response
        let toolResultsText = toolResults.joined(separator: "\n")
        let followUpMessage = "The tool execution results are:\n\(toolResultsText)\n\nNow please provide a natural response to the user based on these results."
        
        // Make a follow-up call without tools to get the final response
        await sendFollowUpMessage(followUpMessage, originalMessage: originalMessage, baseURL: baseURL, model: model, apiKey: apiKey, systemPrompt: systemPrompt, removeThinkTags: removeThinkTags)
    }
    
    private func executeToolCall(_ toolCall: OpenAIToolCall) async throws -> String {
        let functionName = toolCall.function.name
        
        // Parse arguments
        let arguments: [String: Any]
        do {
            let data = toolCall.function.arguments.data(using: .utf8) ?? Data()
            arguments = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw MCPError.executionFailed("Invalid arguments format")
        }
        
        // Check if it's a custom tool
        if functionName.hasPrefix("custom_") {
            guard let mcpManager = mcpManager else {
                throw MCPError.notConnected
            }
            return try await mcpManager.executeCustomTool(name: functionName, arguments: arguments)
        }
        
        // Otherwise, it's an MCP tool
        // Parse function name to extract server name and tool name
        let components = functionName.components(separatedBy: "_")
        
        guard components.count >= 2 else {
            throw MCPError.toolNotFound
        }
        
        let serverName = components[0]
        let toolName = components.dropFirst().joined(separator: "_")
        
        // Find the server by name
        guard let mcpManager = mcpManager,
              let server = mcpManager.servers.first(where: { $0.name == serverName }) else {
            throw MCPError.notConnected
        }
        
        // Execute the tool
        let result = try await mcpManager.executeTool(
            serverId: server.id,
            toolName: toolName,
            arguments: arguments
        )
        
        return String(describing: result)
    }
    
    private func sendFollowUpMessage(_ message: String, originalMessage: String, baseURL: String, model: String, apiKey: String, systemPrompt: String = "You are a helpful assistant.", removeThinkTags: Bool = true) async {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            await MainActor.run {
                self.lastError = "Invalid API URL"
            }
            return
        }
        
        let enhancedSystemPrompt = createEnhancedSystemPrompt(basePrompt: systemPrompt)
        
        let request = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: enhancedSystemPrompt + "\n\nIMPORTANT: Respond only with your final answer to the user. Do not repeat tool results, explain your reasoning process, or add meta-commentary. Just provide the direct response the user needs."),
                OpenAIMessage(role: "user", content: originalMessage),
                OpenAIMessage(role: "assistant", content: message),
                OpenAIMessage(role: "user", content: "Based on the above tool results, please provide your final response to my original question. Keep it concise and direct.")
            ],
            temperature: 0.7,
            maxTokens: 1000,
            topP: 1.0,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0,
            tools: nil,
            toolChoice: nil
        )
        
        // Create and send the request (simplified version of sendMessage)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            self.lastError = "Failed to encode request: \(error.localizedDescription)"
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            Task { @MainActor in
                if let error = error {
                    self.lastError = "Request failed: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.lastError = "No data received"
                    return
                }
                
                do {
                    let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    if let firstChoice = openAIResponse.choices.first,
                       let content = firstChoice.message.content {
                        print("Raw final response: \(content)")
                        
                        // Process the response and ensure we only show the final answer
                        var finalResponse = removeThinkTags ? self.removeThinkTagsFromResponse(content) : content
                        
                        // Additional cleanup: if the response starts with references to tool results, 
                        // try to extract just the final answer portion
                        if finalResponse.contains("tool execution results") || finalResponse.contains("Based on") {
                            // Look for the actual answer after common prefixes
                            let patterns = [
                                "Based on the.*?tool.*?results[.,:]\\s*",
                                "The tool execution results.*?show.*?that\\s*",
                                "According to the.*?results[.,:]\\s*",
                                "The.*?results.*?indicate.*?that\\s*"
                            ]
                            
                            for pattern in patterns {
                                do {
                                    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                                    let range = NSRange(finalResponse.startIndex..., in: finalResponse)
                                    finalResponse = regex.stringByReplacingMatches(in: finalResponse, options: [], range: range, withTemplate: "")
                                } catch {
                                    print("Error applying cleanup pattern: \(error)")
                                }
                            }
                            
                            finalResponse = finalResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        print("Cleaned final response: \(finalResponse)")
                        self.lastResponse = finalResponse
                    } else {
                        self.lastError = "No response content"
                    }
                } catch {
                    self.lastError = "Failed to parse follow-up response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // MARK: - Concurrent Response Handling
    
    private func updateResponseWithError(requestId: UUID, error: String) {
        if let index = chatResponses.firstIndex(where: { $0.requestId == requestId }) {
            let originalResponse = chatResponses[index]
            let errorResponse = ChatResponse(
                requestId: requestId,
                message: originalResponse.message,
                error: error
            )
            chatResponses[index] = errorResponse
        }
        
        // Update legacy properties if this is the most recent request
        if chatResponses.last?.requestId == requestId {
            lastError = error
        }
    }
    
    private func updateResponseWithSuccess(requestId: UUID, response: String, toolCalls: [ToolCallDisplay] = []) {
        if let index = chatResponses.firstIndex(where: { $0.requestId == requestId }) {
            let originalResponse = chatResponses[index]
            let successResponse = ChatResponse(
                requestId: requestId,
                message: originalResponse.message,
                response: response,
                toolCalls: toolCalls
            )
            chatResponses[index] = successResponse
            
            // Add to response queue for TTS
            responseQueue.append(successResponse)
        }
        
        // Update legacy properties if this is the most recent request
        if chatResponses.last?.requestId == requestId {
            lastResponse = response
            lastError = nil
            currentToolCalls = toolCalls
        }
    }
    
    private func handleConcurrentOpenAIResponse(choice: OpenAIChoice, request: ChatRequest) async {
        if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
            // Handle tool calls
            print("Received \(toolCalls.count) tool calls for request \(request.id)")
            await handleConcurrentToolCalls(toolCalls: toolCalls, request: request)
        } else if let content = choice.message.content {
            // Handle regular text response
            print("Response for request \(request.id): \(content)")
            let cleanedResponse = request.removeThinkTags ? self.removeThinkTagsFromResponse(content) : content
            self.updateResponseWithSuccess(requestId: request.id, response: cleanedResponse)
        } else {
            self.updateResponseWithError(requestId: request.id, error: "Empty response from AI")
        }
    }
    
    private func handleConcurrentToolCalls(toolCalls: [OpenAIToolCall], request: ChatRequest) async {
        var toolResults: [String] = []
        var toolCallDisplays: [ToolCallDisplay] = []
        
        for toolCall in toolCalls {
            print("Executing tool for request \(request.id): \(toolCall.function.name)")
            print("Arguments: \(toolCall.function.arguments)")
            
            let resultString: String
            do {
                let result = try await executeToolCall(toolCall)
                resultString = String(describing: result)
                toolResults.append("Tool \(toolCall.function.name): \(resultString)")
            } catch {
                print("Tool execution failed for request \(request.id): \(error)")
                resultString = "Error: \(error.localizedDescription)"
                toolResults.append("Tool \(toolCall.function.name) failed: \(error.localizedDescription)")
            }
            
            // Track tool call for UI display
            let toolCallDisplay = ToolCallDisplay(
                toolName: toolCall.function.name,
                arguments: toolCall.function.arguments,
                result: resultString,
                timestamp: Date()
            )
            toolCallDisplays.append(toolCallDisplay)
        }
        
        // Update response with tool calls
        if let index = chatResponses.firstIndex(where: { $0.requestId == request.id }) {
            let originalResponse = chatResponses[index]
            let toolResponse = ChatResponse(
                requestId: request.id,
                message: originalResponse.message,
                toolCalls: toolCallDisplays,
                isProcessing: true  // Still processing follow-up
            )
            chatResponses[index] = toolResponse
        }
        
        // Send results back to AI for final response
        let toolResultsText = toolResults.joined(separator: "\n")
        let followUpMessage = "The tool execution results are:\n\(toolResultsText)\n\nNow please provide a natural response to the user based on these results."
        
        // Make a follow-up call without tools to get the final response
        await sendConcurrentFollowUpMessage(followUpMessage, request: request, toolCalls: toolCallDisplays)
    }
    
    private func sendConcurrentFollowUpMessage(_ message: String, request: ChatRequest, toolCalls: [ToolCallDisplay]) async {
        let baseURL = request.baseURL
        let fullURL = baseURL.hasSuffix("/") ? baseURL + "v1/chat/completions" : baseURL + "/v1/chat/completions"
        
        guard let url = URL(string: fullURL) else {
            updateResponseWithError(requestId: request.id, error: "Invalid API URL")
            return
        }
        
        let enhancedSystemPrompt = createEnhancedSystemPrompt(basePrompt: request.systemPrompt)
        
        let openAIRequest = OpenAIRequest(
            model: request.model,
            messages: [
                OpenAIMessage(role: "system", content: enhancedSystemPrompt + "\n\nIMPORTANT: Respond only with your final answer to the user. Do not repeat tool results, explain your reasoning process, or add meta-commentary. Just provide the direct response the user needs."),
                OpenAIMessage(role: "user", content: request.message),
                OpenAIMessage(role: "assistant", content: message),
                OpenAIMessage(role: "user", content: "Based on the above tool results, please provide your final response to my original question. Keep it concise and direct.")
            ],
            temperature: 0.7,
            maxTokens: 1000,
            topP: 1.0,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0,
            tools: nil,
            toolChoice: nil
        )
        
        // Create and send the request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(openAIRequest)
        } catch {
            updateResponseWithError(requestId: request.id, error: "Failed to encode request: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    self.updateResponseWithError(requestId: request.id, error: "Request failed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.updateResponseWithError(requestId: request.id, error: "No data received")
                    return
                }
                
                do {
                    let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
                    if let firstChoice = openAIResponse.choices.first,
                       let content = firstChoice.message.content {
                        print("Raw final response for request \(request.id): \(content)")
                        
                        // Process the response and ensure we only show the final answer
                        var finalResponse = request.removeThinkTags ? self.removeThinkTagsFromResponse(content) : content
                        
                        // Additional cleanup: if the response starts with references to tool results, 
                        // try to extract just the final answer portion
                        if finalResponse.contains("tool execution results") || finalResponse.contains("Based on") {
                            // Look for the actual answer after common prefixes
                            let patterns = [
                                "Based on the.*?tool.*?results[.,:]\\s*",
                                "The tool execution results.*?show.*?that\\s*",
                                "According to the.*?results[.,:]\\s*",
                                "The.*?results.*?indicate.*?that\\s*"
                            ]
                            
                            for pattern in patterns {
                                do {
                                    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                                    let range = NSRange(finalResponse.startIndex..., in: finalResponse)
                                    finalResponse = regex.stringByReplacingMatches(in: finalResponse, options: [], range: range, withTemplate: "")
                                } catch {
                                    print("Error applying cleanup pattern: \(error)")
                                }
                            }
                            
                            finalResponse = finalResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        print("Cleaned final response for request \(request.id): \(finalResponse)")
                        self.updateResponseWithSuccess(requestId: request.id, response: finalResponse, toolCalls: toolCalls)
                    } else {
                        self.updateResponseWithError(requestId: request.id, error: "No response content")
                    }
                } catch {
                    self.updateResponseWithError(requestId: request.id, error: "Failed to parse follow-up response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // MARK: - Response Queue Management
    
    func getNextResponseForTTS() -> ChatResponse? {
        guard !responseQueue.isEmpty else { return nil }
        return responseQueue.removeFirst()
    }
    
    func hasQueuedResponses() -> Bool {
        return !responseQueue.isEmpty
    }
}