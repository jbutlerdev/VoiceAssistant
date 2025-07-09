import Foundation
import Combine
import Network
import OSLog

// MARK: - OpenAI API Models
struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
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

// MARK: - OpenAI Service
class OpenAIService: ObservableObject {
    @Published var lastResponse: String = ""
    @Published var lastError: String?
    @Published var isProcessing: Bool = false
    @Published var hasRequestedNetworkAccess: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.homeassistant.voice.local", category: "LocalNetworkAuth")
    private let serviceType = "_preflight_check._tcp"
    
    func sendMessage(_ message: String, baseURL: String, apiKey: String, model: String, maxTokens: Int = 32768, systemPrompt: String = "You are a helpful assistant.") {
        guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            lastError = "OpenAI configuration is incomplete"
            return
        }
        
        isProcessing = true
        lastError = nil
        
        // Construct the full URL
        let fullURL = baseURL.hasSuffix("/") ? baseURL + "v1/chat/completions" : baseURL + "/v1/chat/completions"
        
        guard let url = URL(string: fullURL) else {
            lastError = "Invalid base URL"
            isProcessing = false
            return
        }
        
        // Create the request payload
        let request = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: systemPrompt),
                OpenAIMessage(role: "user", content: message)
            ],
            temperature: 0.7,
            maxTokens: maxTokens,
            topP: 1.0,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0
        )
        
        // Create URL request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            lastError = "Failed to encode request: \(error.localizedDescription)"
            isProcessing = false
            return
        }
        
        // Log the API call details
        print("OpenAI API Call:")
        print("URL: \(fullURL)")
        print("Model: \(model)")
        print("Message: \"\(message)\"")
        print("Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")
        
        // Log request body (for debugging)
        if let bodyData = urlRequest.httpBody,
           let bodyString = String(data: bodyData, encoding: .utf8) {
            print("Request Body: \(bodyString)")
        }
        
        // Make the API call
        URLSession.shared.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                // Handle HTTP errors
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode >= 400 {
                        // Try to decode error response
                        do {
                            let errorResponse = try JSONDecoder().decode(OpenAIError.self, from: data)
                            throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [
                                NSLocalizedDescriptionKey: errorResponse.error.message
                            ])
                        } catch {
                            throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [
                                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) error"
                            ])
                        }
                    }
                }
                return data
            }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessing = false
                    
                    switch completion {
                    case .finished:
                        print("OpenAI API call completed successfully")
                    case .failure(let error):
                        print("OpenAI API Error: \(error)")
                        self?.lastError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    print("OpenAI API Response:")
                    print("ID: \(response.id)")
                    print("Model: \(response.model)")
                    print("Choices: \(response.choices.count)")
                    
                    if let usage = response.usage {
                        print("Usage - Prompt: \(usage.promptTokens), Completion: \(usage.completionTokens), Total: \(usage.totalTokens)")
                    }
                    
                    if let firstChoice = response.choices.first {
                        let responseText = firstChoice.message.content
                        print("Response: \(responseText)")
                        self?.lastResponse = responseText
                    } else {
                        self?.lastError = "No response choices returned"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func clearResponse() {
        lastResponse = ""
        lastError = nil
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
    private func requestLocalNetworkAuthorization() async throws -> Bool {
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
                var hasResumed = false
                
                func completeWithResult(_ result: Result<Bool, Error>) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    
                    // Cleanup
                    listener.stateUpdateHandler = nil
                    browser.stateUpdateHandler = nil
                    browser.browseResultsChangedHandler = nil
                    listener.cancel()
                    browser.cancel()
                    
                    continuation.resume(with: result)
                }
                
                // Set up listener state handler
                listener.stateUpdateHandler = { state in
                    self.logger.info("Listener state changed: \(String(describing: state))")
                    switch state {
                    case .ready:
                        self.logger.info("Listener is ready")
                    case .failed(let error):
                        self.logger.error("Listener failed: \(error.localizedDescription)")
                        completeWithResult(.failure(error))
                    case .cancelled:
                        self.logger.info("Listener cancelled")
                    default:
                        break
                    }
                }
                
                // Set up browser state handler
                browser.stateUpdateHandler = { state in
                    self.logger.info("Browser state changed: \(String(describing: state))")
                    switch state {
                    case .ready:
                        self.logger.info("Browser is ready")
                    case .failed(let error):
                        self.logger.error("Browser failed: \(error.localizedDescription)")
                        completeWithResult(.failure(error))
                    case .cancelled:
                        self.logger.info("Browser cancelled")
                    case .waiting(let error):
                        self.logger.warning("Browser waiting: \(error.localizedDescription)")
                        // This might indicate permission denied
                        completeWithResult(.success(false))
                    default:
                        break
                    }
                }
                
                // Set up browser results handler
                browser.browseResultsChangedHandler = { results, changes in
                    self.logger.info("Browse results changed: \(results.count) results")
                    // If we get any results, permission is likely granted
                    if !results.isEmpty {
                        completeWithResult(.success(true))
                    }
                }
                
                // Start listener and browser
                listener.start(queue: queue)
                browser.start(queue: queue)
                
                // Set a timeout to avoid hanging indefinitely
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    if !hasResumed {
                        self.logger.warning("Local network authorization timed out")
                        completeWithResult(.success(false))
                    }
                }
            }
        } onCancel: {
            self.logger.info("Local network authorization cancelled")
            listener.cancel()
            browser.cancel()
        }
    }
}