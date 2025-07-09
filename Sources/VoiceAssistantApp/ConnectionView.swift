import SwiftUI
import ORSSerial

struct ConnectionView: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @State private var selectedPortPath: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "cable.connector")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                Text("USB Connection")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Divider()
            
            // Connection Status
            ConnectionStatusCard(deviceManager: deviceManager)
            
            // Device Selection
            DeviceSelectionCard(
                deviceManager: deviceManager,
                selectedPortPath: $selectedPortPath
            )
            
            // Device Information
            if let status = deviceManager.deviceStatus {
                DeviceInfoCard(status: status)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectionStatusCard: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    
    var body: some View {
        GroupBox(label: Text("Connection Status").font(.headline)) {
            HStack {
                Circle()
                    .fill(Color(deviceManager.connectionStatus.color))
                    .frame(width: 12, height: 12)
                
                Text(deviceManager.connectionStatus.description)
                    .font(.system(.body, design: .monospaced))
                
                Spacer()
                
                if case .connected = deviceManager.connectionStatus {
                    Button("Disconnect") {
                        deviceManager.disconnect()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}

struct DeviceSelectionCard: View {
    @ObservedObject var deviceManager: VoiceDeviceManager
    @Binding var selectedPortPath: String
    
    var body: some View {
        GroupBox(label: Text("Device Selection").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                if deviceManager.availablePorts.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(deviceManager.availablePorts, id: \.path) { port in
                        DeviceRow(
                            port: port,
                            isSelected: selectedPortPath == port.path,
                            onSelect: {
                                selectedPortPath = port.path
                                deviceManager.selectedPort = port
                            }
                        )
                    }
                }
                
                HStack {
                    Button("Refresh") {
                        deviceManager.startDeviceDiscovery()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Connect") {
                        deviceManager.connectToDevice()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(deviceManager.selectedPort == nil)
                }
            }
            .padding()
        }
    }
}

struct DeviceRow: View {
    let port: ORSSerialPort
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    
                    VStack(alignment: .leading) {
                        Text(port.name)
                            .font(.system(.body, design: .monospaced))
                        Text(port.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

struct DeviceInfoCard: View {
    let status: DeviceStatus
    
    var body: some View {
        GroupBox(label: Text("Device Information").font(.headline)) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                InfoRow(label: "Voice Assistant", value: status.voiceAssistantPhaseDescription)
                InfoRow(label: "Wake Word", value: status.wakeWordActive ? "Active" : "Inactive")
                InfoRow(label: "Microphone", value: status.microphoneMuted ? "Muted" : "Active")
                InfoRow(label: "Volume", value: String(format: "%.0f%%", status.volume * 100))
                InfoRow(label: "LED Brightness", value: String(format: "%.0f%%", status.ledBrightness * 100))
                InfoRow(label: "Wake Word Sensitivity", value: status.wakeWordSensitivity)
            }
            .padding()
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Preview removed for command-line build compatibility