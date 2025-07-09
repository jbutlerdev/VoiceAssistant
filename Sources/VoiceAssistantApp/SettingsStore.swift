import Foundation
import Combine

class SettingsStore: ObservableObject {
    @Published var openAIBaseURL: String = "https://api.openai.com"
    @Published var openAIAPIKey: String = ""
    @Published var openAIModel: String = "gpt-4o-mini"
    @Published var openAIMaxTokens: Int = 32768
    @Published var openAISystemPrompt: String = "You are a helpful assistant."
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private let baseURLKey = "openAIBaseURL"
    private let apiKeyKey = "openAIAPIKey"
    private let modelKey = "openAIModel"
    private let maxTokensKey = "openAIMaxTokens"
    private let systemPromptKey = "openAISystemPrompt"
    
    init() {
        loadSettings()
        
        // Save settings whenever they change
        $openAIBaseURL
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
        
        $openAIAPIKey
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
        
        $openAIModel
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
        
        $openAIMaxTokens
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
        
        $openAISystemPrompt
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func loadSettings() {
        print("Loading settings from UserDefaults...")
        print("Available keys: \(userDefaults.dictionaryRepresentation().keys)")
        
        if let baseURL = userDefaults.string(forKey: baseURLKey) {
            print("Loaded base URL: \(baseURL)")
            openAIBaseURL = baseURL
        } else {
            print("No base URL found in UserDefaults")
        }
        
        if let apiKey = userDefaults.string(forKey: apiKeyKey) {
            print("Loaded API key: \(apiKey.isEmpty ? "empty" : "***set***")")
            openAIAPIKey = apiKey
        } else {
            print("No API key found in UserDefaults")
        }
        
        if let model = userDefaults.string(forKey: modelKey) {
            print("Loaded model: \(model)")
            openAIModel = model
        } else {
            print("No model found in UserDefaults")
        }
        
        let maxTokens = userDefaults.integer(forKey: maxTokensKey)
        if maxTokens > 0 {
            print("Loaded max tokens: \(maxTokens)")
            openAIMaxTokens = maxTokens
        } else {
            print("No max tokens found in UserDefaults, using default: \(openAIMaxTokens)")
        }
        
        if let systemPrompt = userDefaults.string(forKey: systemPromptKey) {
            print("Loaded system prompt: \(systemPrompt.prefix(50))...")
            openAISystemPrompt = systemPrompt
        } else {
            print("No system prompt found in UserDefaults, using default: \(openAISystemPrompt)")
        }
        
        print("Settings loaded - Base URL: \(openAIBaseURL), Model: \(openAIModel), Max Tokens: \(openAIMaxTokens), System Prompt: \(openAISystemPrompt.prefix(30))..., API Key: \(openAIAPIKey.isEmpty ? "Not set" : "Set")")
    }
    
    private func saveSettings() {
        print("Saving settings...")
        userDefaults.set(openAIBaseURL, forKey: baseURLKey)
        userDefaults.set(openAIAPIKey, forKey: apiKeyKey)
        userDefaults.set(openAIModel, forKey: modelKey)
        userDefaults.set(openAIMaxTokens, forKey: maxTokensKey)
        userDefaults.set(openAISystemPrompt, forKey: systemPromptKey)
        
        // Force synchronization to ensure settings are written immediately
        userDefaults.synchronize()
        
        print("Settings saved - Base URL: \(openAIBaseURL), Model: \(openAIModel), Max Tokens: \(openAIMaxTokens), System Prompt: \(openAISystemPrompt.prefix(30))..., API Key: \(openAIAPIKey.isEmpty ? "Not set" : "Set")")
        
        // Verify settings were saved
        print("Verification - Base URL: \(userDefaults.string(forKey: baseURLKey) ?? "nil")")
        print("Verification - API Key: \(userDefaults.string(forKey: apiKeyKey)?.isEmpty == false ? "set" : "not set")")
        print("Verification - Model: \(userDefaults.string(forKey: modelKey) ?? "nil")")
        print("Verification - Max Tokens: \(userDefaults.integer(forKey: maxTokensKey))")
        print("Verification - System Prompt: \(userDefaults.string(forKey: systemPromptKey)?.prefix(30) ?? "nil")...")
    }
    
    // Force save settings - can be called manually
    func forceSave() {
        saveSettings()
    }
    
    // Check if settings are complete
    var isConfigured: Bool {
        let configured = !openAIBaseURL.isEmpty && !openAIAPIKey.isEmpty && !openAIModel.isEmpty
        print("Settings check - Base URL: '\(openAIBaseURL)', API Key: '\(openAIAPIKey.isEmpty ? "empty" : "set")', Model: '\(openAIModel)', Configured: \(configured)")
        return configured
    }
    
    // Common model options
    static let commonModels = [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo",
        "gpt-3.5-turbo",
        "o1",
        "o1-mini"
    ]
}