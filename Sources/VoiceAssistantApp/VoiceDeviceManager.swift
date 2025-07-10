import Foundation
import Combine
import ORSSerial

@MainActor
class VoiceDeviceManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var availablePorts: [ORSSerialPort] = []
    @Published var selectedPort: ORSSerialPort?
    @Published var deviceStatus: DeviceStatus?
    @Published var lastError: String?
    @Published var availableWakeWords: [String] = []
    
    private var serialPort: ORSSerialPort?
    private let portManager = ORSSerialPortManager.shared()
    private var heartbeatTimer: Timer?
    private var connectionTimeoutTimer: Timer?
    private var messageBuffer = ""
    private var lastHeartbeatResponse: Date?
    private var heartbeatCount: Int = 0
    private var lastHeartbeatLog: Date = Date()
    
    // Audio pipeline properties
    private var audioBuffer: [[Int16]] = []
    private var isRecording = false
    private var sttManager: SpeechToTextManager?
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .error(let message): return "Error: \(message)"
            }
        }
        
        var color: String {
            switch self {
            case .disconnected: return "gray"
            case .connecting: return "orange"
            case .connected: return "green"
            case .error: return "red"
            }
        }
    }
    
    override init() {
        super.init()
        setupPortManager()
    }
    
    private func setupPortManager() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serialPortsWereConnected(_:)),
            name: .ORSSerialPortsWereConnected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(serialPortsWereDisconnected(_:)),
            name: .ORSSerialPortsWereDisconnected,
            object: nil
        )
        
        updateAvailablePorts()
    }
    
    @objc private func serialPortsWereConnected(_ notification: Notification) {
        Task { @MainActor in
            self.updateAvailablePorts()
        }
    }
    
    @objc private func serialPortsWereDisconnected(_ notification: Notification) {
        Task { @MainActor in
            self.updateAvailablePorts()
        }
    }
    
    private func updateAvailablePorts() {
        availablePorts = portManager.availablePorts.filter { port in
            // Filter for ESP32-S3 devices (look for common USB-to-UART chip names)
            let name = port.name.lowercased()
            let path = port.path.lowercased()
            return name.contains("esp") ||
                   name.contains("cp210") ||
                   name.contains("ftdi") ||
                   name.contains("usb") ||
                   path.contains("tty.usb") ||
                   path.contains("tty.usbmodem") ||  // Common on macOS
                   path.contains("tty.wchusbserial") || // Another common pattern
                   path.contains("cu.usb") ||
                   path.contains("cu.usbmodem") ||  // macOS cu devices
                   path.contains("cu.wchusbserial")
        }
        
        // Debug: print all available ports
        print("All available ports:")
        for port in portManager.availablePorts {
            print("  - Name: \(port.name), Path: \(port.path)")
        }
        
        print("Filtered ESP32-like ports:")
        for port in availablePorts {
            print("  - Name: \(port.name), Path: \(port.path)")
        }
    }
    
    func startDeviceDiscovery() {
        updateAvailablePorts()
        
        // Auto-connect to the first available device
        if let device = availablePorts.first {
            print("Auto-connecting to: \(device.name) at \(device.path)")
            selectedPort = device
            connectToDevice()
        } else {
            print("No suitable USB devices found for auto-connection")
        }
    }
    
    func connectToDevice() {
        guard let port = selectedPort else {
            connectionStatus = .error("No device selected")
            return
        }
        
        print("Attempting to connect to: \(port.name) at \(port.path)")
        connectionStatus = .connecting
        
        // Disconnect any existing connection
        disconnect()
        
        // Configure the serial port
        serialPort = port
        serialPort?.delegate = self
        serialPort?.baudRate = 115200
        serialPort?.numberOfDataBits = 8
        serialPort?.parity = .none
        serialPort?.numberOfStopBits = 1
        serialPort?.usesRTSCTSFlowControl = false
        serialPort?.usesDTRDSRFlowControl = false
        
        print("Opening serial port with settings: 115200 8N1")
        
        // Set a connection timeout - if device doesn't respond in 10 seconds, consider it failed
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if self.connectionStatus == .connecting {
                print("Connection timeout - device not responding")
                self.connectionStatus = .error("Connection timeout - device not responding")
                self.disconnect()
            }
        }
        
        // Open the connection
        serialPort?.open()
    }
    
    func disconnect() {
        // Send disconnection message to device before closing
        if serialPort?.isOpen == true {
            let disconnectMessage = "{\"type\":\"disconnect\"}\n"
            if let data = disconnectMessage.data(using: .utf8) {
                serialPort?.send(data)
                // Give it a moment to send
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        
        serialPort?.close()
        serialPort?.delegate = nil
        serialPort = nil
        
        connectionStatus = .disconnected
        deviceStatus = nil
        lastHeartbeatResponse = nil
        heartbeatCount = 0
        lastHeartbeatLog = Date()
    }
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
    }
    
    private func startConnectionTimeout() {
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnectionHealth()
            }
        }
    }
    
    private func checkConnectionHealth() {
        guard let lastResponse = lastHeartbeatResponse else {
            print("No heartbeat response received yet")
            return
        }
        
        let timeSinceLastResponse = Date().timeIntervalSince(lastResponse)
        if timeSinceLastResponse > 10.0 { // 10 seconds timeout
            print("Device appears unresponsive - no heartbeat for \(timeSinceLastResponse) seconds")
            connectionStatus = .error("Device not responding")
        } else if timeSinceLastResponse > 5.0 {
            print("Warning: No heartbeat response for \(timeSinceLastResponse) seconds")
        }
    }
    
    private func sendHeartbeat() {
        let message = "{\"type\":\"heartbeat\"}\n"
        heartbeatCount += 1
        
        // Log heartbeat status every 30 seconds
        let timeSinceLastLog = Date().timeIntervalSince(lastHeartbeatLog)
        if timeSinceLastLog >= 30.0 {
            print("Heartbeat status: \(heartbeatCount) heartbeats sent, connection healthy")
            lastHeartbeatLog = Date()
        }
        
        // Send heartbeat without logging
        if let data = message.data(using: .utf8) {
            serialPort?.send(data)
        }
    }
    
    private func sendMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else { 
            print("Failed to convert message to UTF8: \(message)")
            return 
        }
        print("Sending message: \(message.debugDescription)")
        serialPort?.send(data)
    }
    
    func requestStatus() {
        let message = "{\"type\":\"get_status\"}\n"
        sendMessage(message)
    }
    
    func requestWakeWordOptions() {
        let message = "{\"type\":\"get_wake_word_options\"}\n"
        print("Requesting wake word options: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        sendMessage(message)
    }
    
    func sendConfiguration(_ config: [String: Any]) {
        do {
            var message = config
            message["type"] = "config"
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                sendMessage(jsonString)
            }
        } catch {
            lastError = "Failed to serialize configuration: \(error.localizedDescription)"
        }
    }
    
    func setSpeechToTextManager(_ manager: SpeechToTextManager) {
        sttManager = manager
    }
}

// MARK: - ORSSerialPortDelegate
extension VoiceDeviceManager: ORSSerialPortDelegate {
    nonisolated func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            print("Serial port opened successfully")
            // Don't mark as connected yet - wait for device response
            self.connectionStatus = .connecting
            self.startConnectionTimeout()
            
            // Give device time to initialize, then start gentle communication
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                print("Starting heartbeat after device initialization delay")
                self.startHeartbeat()
                
                // Send initial heartbeat and wait for response
                self.sendHeartbeat()
                
                // Check for response after delay
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                if self.lastHeartbeatResponse == nil {
                    print("No heartbeat response received - device may not be running proper firmware")
                    self.connectionStatus = .error("Device not responding - check firmware")
                    self.disconnect()
                } else {
                    print("Device responding - requesting initial data")
                    self.connectionStatus = .connected
                    self.requestStatus()
                    self.requestWakeWordOptions()
                }
            }
        }
    }
    
    nonisolated func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        guard let receivedString = String(data: data, encoding: .utf8) else { 
            print("Received non-UTF8 data: \(data)")
            return 
        }
        
        print("Raw received: \(receivedString.debugDescription)")
        
        Task { @MainActor in
            self.messageBuffer += receivedString
            self.processBufferedMessages()
        }
    }
    
    private func processBufferedMessages() {
        let lines = messageBuffer.components(separatedBy: "\n")
        messageBuffer = lines.last ?? ""
        
        for line in lines.dropLast() {
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                processMessage(line)
            }
        }
    }
    
    private func processMessage(_ message: String) {
        // Skip heartbeat_ack messages from logging
        if !message.contains("\"type\":\"heartbeat_ack\"") {
            print("Processing message: \(message)")
        }
        
        // Skip messages that look like debug output
        if message.contains("[D][") || message.contains("[I][") || message.contains("[W][") || message.contains("[E][") {
            print("Skipping debug message: \(message)")
            return
        }
        
        // Skip messages with ANSI color codes
        if message.contains("\u{001B}[") {
            print("Skipping ANSI message: \(message)")
            return
        }
        
        // Ensure message looks like JSON
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else {
            print("Message doesn't look like JSON: \(message)")
            return
        }
        
        do {
            guard let data = trimmed.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                print("Failed to parse JSON from message: \(message)")
                return
            }
            
            // Only log non-heartbeat message types
            if type != "heartbeat_ack" {
                print("Parsed message type: \(type)")
            }
            
            switch type {
            case "status":
                updateDeviceStatus(from: json)
            case "wake_word_options":
                updateWakeWordOptions(from: json)
            case "heartbeat_ack":
                let previousResponse = lastHeartbeatResponse
                lastHeartbeatResponse = Date()
                
                // Log if this is the first heartbeat after a connection issue
                if previousResponse == nil || Date().timeIntervalSince(previousResponse!) > 5.0 {
                    print("Device connection restored - heartbeat acknowledged")
                }
                // Don't log regular heartbeat acknowledgments
                return
            case "config_applied":
                print("Configuration was applied successfully")
                break
            case "config_received":
                print("Configuration was received")
                break
            case "wake_word_detected":
                print("Wake word detected!")
                // Could trigger additional UI feedback here
                break
            case "button_pressed":
                print("Center button pressed!")
                // Could trigger additional UI feedback here
                break
            case "wake_word_timeout":
                print("Wake word listening timed out")
                break
            case "button_timeout":
                print("Button listening timed out")
                break
            case "listening_timeout":
                print("Device listening timeout - no voice activity detected")
                break
            case "vad_start":
                print("Voice activity detected - user started speaking")
                // Could trigger recording start here if needed
                break
            case "vad_end":
                print("Voice activity ended - user stopped speaking")
                // Could trigger recording stop here if needed
                break
            case "processing_complete":
                print("Voice processing completed")
                break
            case "stop_listening":
                print("Device stopped listening (manual stop)")
                break
            case "start_audio_recording":
                print("Device started audio recording")
                startAudioRecording()
                break
            case "stop_audio_recording":
                print("Device stopped audio recording")
                stopAudioRecording()
                break
            case "audio_data":
                print("Received audio data from device")
                processAudioData(from: json)
                break
            case "audio_played":
                print("Device finished playing audio response")
                break
            case "batch_received":
                print("Device received audio batch (waiting for more)")
                break
            default:
                print("Unknown message type: \(type)")
            }
        } catch {
            lastError = "Failed to parse message: \(error.localizedDescription)"
            print("JSON parsing error: \(error)")
        }
    }
    
    private func updateDeviceStatus(from json: [String: Any]) {
        let status = DeviceStatus(
            timestamp: json["timestamp"] as? Int ?? 0,
            wakeWordActive: json["wake_word_active"] as? Bool ?? false,
            microphoneMuted: json["microphone_muted"] as? Bool ?? false,
            voiceAssistantPhase: json["voice_assistant_phase"] as? Int ?? 0,
            voiceAssistantRunning: json["voice_assistant_running"] as? Bool ?? false,
            timerActive: json["timer_active"] as? Bool ?? false,
            timerRinging: json["timer_ringing"] as? Bool ?? false,
            ledBrightness: json["led_brightness"] as? Double ?? 0.0,
            volume: json["volume"] as? Double ?? 0.0,
            wakeWord: json["wake_word"] as? String ?? "Okay Nabu",
            wakeWordSensitivity: json["wake_word_sensitivity"] as? String ?? "Moderately sensitive",
            wifiConnected: json["wifi_connected"] as? Bool ?? false,
            apiConnected: json["api_connected"] as? Bool ?? false
        )
        
        deviceStatus = status
        
        // Post notification to sync device configuration with current device settings
        NotificationCenter.default.post(
            name: .deviceStatusUpdated, 
            object: status
        )
    }
    
    private func updateWakeWordOptions(from json: [String: Any]) {
        print("Raw wake word options JSON: \(json)")
        if let options = json["options"] as? [String] {
            print("Received wake word options from device: \(options)")
            availableWakeWords = options
            
            // Post notification about wake word options update
            NotificationCenter.default.post(
                name: .wakeWordOptionsUpdated,
                object: options
            )
        } else {
            print("Failed to parse wake word options from JSON")
        }
    }
    
    nonisolated func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            print("Serial port was closed")
            self.connectionStatus = .disconnected
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.connectionTimeoutTimer?.invalidate()
            self.connectionTimeoutTimer = nil
            self.deviceStatus = nil
            self.lastHeartbeatResponse = nil
        }
    }
    
    nonisolated func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        Task { @MainActor in
            self.connectionStatus = .error(error.localizedDescription)
            self.lastError = error.localizedDescription
        }
    }
    
    nonisolated func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            self.connectionStatus = .disconnected
            // Just disconnect if we have any serial port
            if self.serialPort != nil {
                self.disconnect()
            }
        }
    }
    
    // MARK: - Audio Pipeline Methods
    
    private func startAudioRecording() {
        print("Starting audio recording in Swift app")
        audioBuffer.removeAll()
        isRecording = true
        
        // Start recording if STT manager is available
        if let stt = sttManager {
            stt.startRecording()
        }
    }
    
    private func stopAudioRecording() {
        print("Stopping audio recording in Swift app - processing \(audioBuffer.count) audio chunks")
        isRecording = false
        
        // Stop recording and transcribe complete audio
        if let stt = sttManager {
            stt.stopRecording()
            // The STT manager will handle the complete transcription
            // For now, still send echo response - later this would be processed by AI
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                self.sendEchoResponse()
            }
        } else {
            // Fallback to echo if no STT manager
            if !audioBuffer.isEmpty {
                sendEchoResponse()
            }
        }
    }
    
    private func processAudioData(from json: [String: Any]) {
        guard isRecording,
              let samples = json["samples"] as? [Int] else {
            return
        }
        
        // Convert Int array to Int16 array - Handle ESP32 audio format properly
        let audioSamples = samples.map { sample -> Int16 in
            // Convert and scale if ESP32 is sending in different bit depth
            let clampedSample: Int
            
            // Check if samples are coming in a different format (like 24-bit or 32-bit)
            if sample < Int(Int16.min) || sample > Int(Int16.max) {
                // Scale down if samples are in higher bit depth
                if sample > 32767 || sample < -32768 {
                    // Assume 24-bit or 32-bit samples, scale down properly
                    clampedSample = sample / (sample > 65535 ? 256 : 1) // Scale from 24-bit to 16-bit
                } else {
                    clampedSample = sample
                }
            } else {
                clampedSample = sample
            }
            
            return Int16(clamping: clampedSample)
        }
        audioBuffer.append(audioSamples)
        
        // Debug first chunk to see sample values and analyze noise
        if audioBuffer.count == 1 {
            let sampleValues = audioSamples.prefix(20).map { String($0) }.joined(separator: ", ")
            print("First audio chunk sample values: [\(sampleValues)]...")
            print("Raw int values: [\(samples.prefix(20).map { String($0) }.joined(separator: ", "))]...")
            
            // Check for static pattern in raw samples
            let maxSample = audioSamples.map { abs($0) }.max() ?? 0
            let avgSample = audioSamples.reduce(0) { $0 + abs(Int($1)) } / audioSamples.count
            print("First chunk stats - Max: \(maxSample), Avg: \(avgSample)")
            
            // Check if samples alternate rapidly (sign of digital noise)
            var signChanges = 0
            for i in 1..<min(100, audioSamples.count) {
                if (audioSamples[i-1] < 0 && audioSamples[i] >= 0) ||
                   (audioSamples[i-1] >= 0 && audioSamples[i] < 0) {
                    signChanges += 1
                }
            }
            print("Sign changes in first 100 samples: \(signChanges) (high values indicate noise)")
        }
        
        // Send to STT manager for streaming transcription
        if let stt = sttManager {
            stt.processAudioSamples(audioSamples)
        }
    }
    
    private func sendEchoResponse() {
        print("Sending echo response back to device")
        
        // First, ensure device is unmuted (without changing volume)
        let unmuteMessage: [String: Any] = [
            "type": "config",
            "unmute": true,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: unmuteMessage)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                print("Sending unmute command (\(jsonString.count) bytes)")
                sendMessage(jsonString)
            }
        } catch {
            print("Failed to serialize unmute command: \(error)")
        }
        
        // Wait a moment, then send the tone
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            let audioMessage: [String: Any] = [
                "type": "play_tone",
                "frequency": 880,
                "duration_ms": 2000,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: audioMessage)
                if var jsonString = String(data: jsonData, encoding: .utf8) {
                    jsonString += "\n"
                    print("Sending tone command (\(jsonString.count) bytes)")
                    self.sendMessage(jsonString)
                }
            } catch {
                print("Failed to serialize tone command: \(error)")
            }
        }
    }
    
    private func sendAudioBatch(_ samples: [Int16], batchNumber: Int, totalBatches: Int) {
        let audioMessage: [String: Any] = [
            "type": "play_audio",
            "audio_data": samples.map { Int($0) },
            "batch": batchNumber,
            "total_batches": totalBatches,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: audioMessage)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                print("Sending audio batch \(batchNumber)/\(totalBatches) (\(samples.count) samples, \(jsonString.count) bytes)")
                sendMessage(jsonString)
            }
        } catch {
            print("Failed to serialize audio batch: \(error)")
        }
    }
    
    private func sendStreamCommand(_ command: String) {
        let message: [String: Any] = [
            "type": command,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                print("Sending stream command: \(command)")
                sendMessage(jsonString)
            }
        } catch {
            print("Failed to serialize stream command: \(error)")
        }
    }
    
    private func sendAudioDataChunk(_ chunk: [UInt8], chunkIndex: Int, totalChunks: Int) {
        // Convert bytes to integers for JSON transmission
        let chunkInts = chunk.map { Int($0) }
        
        let message: [String: Any] = [
            "type": "audio_data_chunk",
            "data": chunkInts,
            "chunk_index": chunkIndex,
            "total_chunks": totalChunks,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                print("Sending audio chunk \(chunkIndex)/\(totalChunks) (\(chunk.count) bytes)")
                sendMessage(jsonString)
            }
        } catch {
            print("Failed to serialize audio chunk: \(error)")
        }
    }
    
    private func sendAudioChunk(chunkIndex: Int, totalChunks: Int, audioData: [Int16], isStart: Bool = false) {
        let audioMessage: [String: Any] = [
            "type": "play_audio_chunk",
            "chunk_index": chunkIndex,
            "total_chunks": totalChunks,
            "audio_data": audioData.map { Int($0) },
            "is_start": isStart,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: audioMessage)
            if var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString += "\n"
                print("Sending audio chunk \(chunkIndex)/\(totalChunks) (\(audioData.count) samples)")
                sendMessage(jsonString)
            }
        } catch {
            print("Failed to serialize audio chunk: \(error)")
        }
    }
}

struct DeviceStatus {
    let timestamp: Int
    let wakeWordActive: Bool
    let microphoneMuted: Bool
    let voiceAssistantPhase: Int
    let voiceAssistantRunning: Bool
    let timerActive: Bool
    let timerRinging: Bool
    let ledBrightness: Double
    let volume: Double
    let wakeWord: String
    let wakeWordSensitivity: String
    let wifiConnected: Bool
    let apiConnected: Bool
    
    var voiceAssistantPhaseDescription: String {
        switch voiceAssistantPhase {
        case 1: return "Idle"
        case 2: return "Waiting for Command"
        case 3: return "Listening"
        case 4: return "Thinking"
        case 5: return "Replying"
        case 10: return "Not Ready"
        case 11: return "Error"
        default: return "Unknown (\(voiceAssistantPhase))"
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}