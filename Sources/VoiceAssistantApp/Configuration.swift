import Foundation
import Combine

@MainActor
class DeviceConfiguration: ObservableObject {
    @Published var wakeWord: String = "Okay Nabu"
    @Published var wakeWordSensitivity: String = "Moderately sensitive"
    @Published var ledBrightness: Double = 0.66
    @Published var volume: Double = 0.7
    @Published var wakeWordOptions: [String] = ["Okay Nabu"] // Default fallback
    
    let wakeWordSensitivityOptions = [
        "Slightly sensitive",
        "Moderately sensitive", 
        "Very sensitive"
    ]
    
    // Flag to prevent infinite sync loops
    private var isApplyingConfiguration = false
    
    init() {
        // Listen for device status updates to sync configuration
        NotificationCenter.default.addObserver(
            forName: .deviceStatusUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let status = notification.object as? DeviceStatus {
                Task { @MainActor in
                    self?.syncWithDeviceStatus(status)
                }
            }
        }
        
        // Listen for wake word options updates from device
        NotificationCenter.default.addObserver(
            forName: .wakeWordOptionsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let options = notification.object as? [String] {
                Task { @MainActor in
                    self?.updateWakeWordOptions(options)
                }
            }
        }
    }
    
    private func syncWithDeviceStatus(_ status: DeviceStatus) {
        // Don't sync while we're applying configuration to prevent loops
        guard !isApplyingConfiguration else {
            print("Skipping device status sync while applying configuration")
            return
        }
        
        print("Syncing with device status: wake_word=\(status.wakeWord), sensitivity=\(status.wakeWordSensitivity)")
        
        // Only update if values are different to avoid infinite loops
        if wakeWord != status.wakeWord {
            print("Updating wake word from \(wakeWord) to \(status.wakeWord)")
            wakeWord = status.wakeWord
        }
        if wakeWordSensitivity != status.wakeWordSensitivity {
            print("Updating sensitivity from \(wakeWordSensitivity) to \(status.wakeWordSensitivity)")
            wakeWordSensitivity = status.wakeWordSensitivity
        }
        if abs(ledBrightness - status.ledBrightness) > 0.01 {
            print("Updating LED brightness from \(ledBrightness) to \(status.ledBrightness)")
            ledBrightness = status.ledBrightness
        }
        if abs(volume - status.volume) > 0.01 {
            print("Updating volume from \(volume) to \(status.volume)")
            volume = status.volume
        }
    }
    
    private func updateWakeWordOptions(_ options: [String]) {
        print("Updating wake word options in configuration: \(options)")
        print("Current wakeWordOptions before update: \(wakeWordOptions)")
        print("Current wakeWord before update: \(wakeWord)")
        
        wakeWordOptions = options
        
        // If current wake word is not in the new options, select the first available option
        if !options.contains(wakeWord) && !options.isEmpty {
            print("Current wake word '\(wakeWord)' not in options, switching to '\(options[0])'")
            wakeWord = options[0]
        }
        
        print("wakeWordOptions after update: \(wakeWordOptions)")
        print("wakeWord after update: \(wakeWord)")
    }
    
    func apply(to deviceManager: VoiceDeviceManager) {
        // Set flag to prevent sync loops while applying
        isApplyingConfiguration = true
        
        let config: [String: Any] = [
            "wake_word": wakeWord,
            "sensitivity": wakeWordSensitivity,
            "led_brightness": ledBrightness,
            "volume": volume
        ]
        print("Applying configuration to device: \(config)")
        deviceManager.sendConfiguration(config)
        
        // Clear flag after a delay to allow for device response
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.isApplyingConfiguration = false
            print("Configuration application completed, re-enabling sync")
        }
    }
}

class AIConfiguration: ObservableObject {
    @Published var openAIAPIKey: String = ""
    @Published var openAIURL: String = "https://api.openai.com/v1"
    @Published var mcpServers: [MCPServer] = []
    
    // Save to UserDefaults
    init() {
        loadFromUserDefaults()
    }
    
    private func loadFromUserDefaults() {
        openAIAPIKey = UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""
        openAIURL = UserDefaults.standard.string(forKey: "openAIURL") ?? "https://api.openai.com/v1"
        
        if let mcpData = UserDefaults.standard.data(forKey: "mcpServers"),
           let servers = try? JSONDecoder().decode([MCPServer].self, from: mcpData) {
            mcpServers = servers
        }
    }
    
    func saveToUserDefaults() {
        UserDefaults.standard.set(openAIAPIKey, forKey: "openAIAPIKey")
        UserDefaults.standard.set(openAIURL, forKey: "openAIURL")
        
        if let mcpData = try? JSONEncoder().encode(mcpServers) {
            UserDefaults.standard.set(mcpData, forKey: "mcpServers")
        }
    }
    
    func addMCPServer() {
        mcpServers.append(MCPServer(name: "New Server", url: ""))
        saveToUserDefaults()
    }
    
    func removeMCPServer(at index: Int) {
        guard index < mcpServers.count else { return }
        mcpServers.remove(at: index)
        saveToUserDefaults()
    }
}

struct MCPServer: Codable, Identifiable {
    let id = UUID()
    var name: String
    var url: String
    var isEnabled: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case name, url, isEnabled
    }
}