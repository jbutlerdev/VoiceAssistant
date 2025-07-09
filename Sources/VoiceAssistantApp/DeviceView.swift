import SwiftUI

struct DeviceView: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @ObservedObject var deviceConfig: DeviceConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "speaker.wave.2")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                Text("Device Configuration")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Divider()
            
            if case .connected = deviceManager.connectionStatus {
                ScrollView {
                    VStack(spacing: 20) {
                        // Wake Word Configuration
                        WakeWordConfigCard(
                            deviceManager: deviceManager,
                            deviceConfig: deviceConfig
                        )
                        
                        // Audio Configuration
                        AudioConfigCard(
                            deviceManager: deviceManager,
                            deviceConfig: deviceConfig
                        )
                        
                        // LED Configuration
                        LEDConfigCard(
                            deviceManager: deviceManager,
                            deviceConfig: deviceConfig
                        )
                        
                        // Device Status
                        if let status = deviceManager.deviceStatus {
                            DeviceStatusCard(status: status)
                        }
                    }
                }
            } else {
                Spacer()
                VStack {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Device Not Connected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Connect to a device to configure settings")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding()
    }
}

struct WakeWordConfigCard: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @ObservedObject var deviceConfig: DeviceConfiguration
    
    var body: some View {
        GroupBox(label: Text("Wake Word Configuration").font(.headline)) {
            VStack(alignment: .leading, spacing: 16) {
                // Wake Word Selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Wake Word:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(deviceConfig.wakeWord)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }
                    
                    Picker("Wake Word", selection: $deviceConfig.wakeWord) {
                        ForEach(deviceConfig.wakeWordOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: deviceConfig.wakeWord) { _ in
                        deviceConfig.apply(to: deviceManager)
                    }
                }
                
                Divider()
                
                // Sensitivity Configuration
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sensitivity:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(deviceConfig.wakeWordSensitivity)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }
                    
                    Picker("Wake Word Sensitivity", selection: $deviceConfig.wakeWordSensitivity) {
                        ForEach(deviceConfig.wakeWordSensitivityOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: deviceConfig.wakeWordSensitivity) { _ in
                        deviceConfig.apply(to: deviceManager)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wake Word Options:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Okay Nabu: Default Home Assistant wake word")
                        Text("• Hey Jarvis: AI assistant inspired wake word")
                        Text("• Hey Mycroft: Open source voice assistant wake word")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity Levels:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Slightly sensitive: Fewer false triggers, may miss some wake words")
                        Text("• Moderately sensitive: Balanced performance (recommended)")
                        Text("• Very sensitive: More responsive, may have false triggers")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

struct AudioConfigCard: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @ObservedObject var deviceConfig: DeviceConfiguration
    @State private var tempVolume: Double = 0.7
    
    var body: some View {
        GroupBox(label: Text("Audio Configuration").font(.headline)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(tempVolume * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $tempVolume,
                        in: 0.0...1.0,
                        step: 0.05
                    ) {
                        Text("Volume")
                    } onEditingChanged: { editing in
                        if !editing {
                            deviceConfig.volume = tempVolume
                            deviceConfig.apply(to: deviceManager)
                        }
                    }
                }
                
                if let status = deviceManager.deviceStatus {
                    HStack {
                        Image(systemName: status.microphoneMuted ? "mic.slash" : "mic")
                            .foregroundColor(status.microphoneMuted ? .red : .green)
                        Text("Microphone: \(status.microphoneMuted ? "Muted" : "Active")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding()
        }
        .onAppear {
            tempVolume = deviceConfig.volume
        }
        .onChange(of: deviceConfig.volume) { newValue in
            tempVolume = newValue
        }
    }
}

struct LEDConfigCard: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @ObservedObject var deviceConfig: DeviceConfiguration
    @State private var tempBrightness: Double = 0.66
    
    var body: some View {
        GroupBox(label: Text("LED Configuration").font(.headline)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Brightness:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(tempBrightness * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: $tempBrightness,
                        in: 0.0...1.0,
                        step: 0.05
                    ) {
                        Text("LED Brightness")
                    } onEditingChanged: { editing in
                        if !editing {
                            deviceConfig.ledBrightness = tempBrightness
                            deviceConfig.apply(to: deviceManager)
                        }
                    }
                }
                
                Text("LED Ring indicates device state and voice assistant activity")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            tempBrightness = deviceConfig.ledBrightness
        }
        .onChange(of: deviceConfig.ledBrightness) { newValue in
            tempBrightness = newValue
        }
    }
}

struct DeviceStatusCard: View {
    let status: DeviceStatus
    
    var body: some View {
        GroupBox(label: Text("Current Device Status").font(.headline)) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatusItem(
                    icon: "brain.head.profile",
                    label: "Voice Assistant",
                    value: status.voiceAssistantPhaseDescription,
                    color: status.voiceAssistantRunning ? .green : .secondary
                )
                
                StatusItem(
                    icon: "waveform.and.mic",
                    label: "Wake Word",
                    value: "\(status.wakeWord)\n\(status.wakeWordActive ? "Active" : "Inactive")",
                    color: status.wakeWordActive ? .green : .secondary
                )
                
                StatusItem(
                    icon: status.timerActive ? "timer" : "timer.slash",
                    label: "Timer",
                    value: status.timerActive ? "Active" : "Inactive",
                    color: status.timerActive ? .orange : .secondary
                )
                
                StatusItem(
                    icon: "wifi",
                    label: "WiFi",
                    value: status.wifiConnected ? "Connected" : "Disconnected",
                    color: status.wifiConnected ? .green : .red
                )
                
                StatusItem(
                    icon: "homekit",
                    label: "Home Assistant",
                    value: status.apiConnected ? "Connected" : "Disconnected", 
                    color: status.apiConnected ? .green : .red
                )
                
                StatusItem(
                    icon: "cable.connector",
                    label: "USB Mode",
                    value: "Local Control",
                    color: .blue
                )
            }
            .padding()
        }
    }
}

struct StatusItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// Preview removed for command-line build compatibility