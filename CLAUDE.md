# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Swift-based macOS voice assistant application that communicates with Home Assistant Voice USB devices (ESP32-S3) for local voice processing and AI integration. The app provides a complete voice processing pipeline from USB communication to AI response generation.

## Development Commands

### Basic Development
```bash
# Run in development mode
swift run

# Build for development
swift build

# Clean build artifacts
swift package clean

# Resolve dependencies
swift package resolve

# Test the application
./test-app.sh
```

### Release Build
```bash
# Create signed release build with app bundle
./build-release.sh

# Manual release build
swift build -c release
```

The build script creates a properly signed macOS app bundle in the `dist/` directory, including Info.plist configuration for local network permissions, code signing, and optional DMG creation.

## Architecture Overview

### Core Components

**Main Application Structure:**
- `main.swift` - Entry point with AppKit integration, creates proper macOS app with dock presence and menu bar
- `ContentView.swift` - SwiftUI main view with tab-based navigation
- `VoiceDeviceManager.swift` - Core USB/Serial communication with ESP32-S3 device
- `SpeechToTextManager.swift` - Local Whisper-based speech recognition
- `OpenAIService.swift` - AI integration with OpenAI-compatible APIs
- `Configuration.swift` - Device and AI configuration management

### Data Flow Architecture

The application follows a pipeline architecture:

1. **USB Communication Layer** (`VoiceDeviceManager`):
   - Handles serial communication with ESP32-S3 device via ORSSerial
   - Manages device discovery, connection, and heartbeat monitoring
   - Processes JSON messages for device status, audio data, and configuration
   - Implements audio streaming pipeline for real-time voice processing

2. **Audio Processing Layer** (`SpeechToTextManager`):
   - Uses local Whisper model for speech-to-text conversion
   - Processes 16kHz audio samples from ESP32 device
   - Handles audio buffer management and noise reduction
   - Provides streaming and batch transcription capabilities

3. **AI Integration Layer** (`OpenAIService`):
   - OpenAI-compatible API integration for response generation
   - Handles local network permission requests for private AI servers
   - Supports various AI models and configurations

4. **Configuration Management** (`Configuration.swift`):
   - Device settings (wake word, sensitivity, LED brightness, volume)
   - AI settings (API keys, base URLs, models, system prompts)
   - Persistent storage via UserDefaults
   - Real-time synchronization with device state

### Key Design Patterns

**State Management:**
- Uses `@ObservableObject` and `@StateObject` for reactive UI updates
- Notification-based communication between components
- Real-time device status synchronization

**Concurrency:**
- Background thread processing for Whisper transcription
- Serial queue for USB communication
- Async/await for AI API calls
- Proper thread safety with main thread UI updates

**Error Handling:**
- Comprehensive error propagation with user-friendly messages
- Device connection timeout and retry logic
- Graceful degradation when components fail

## Key Dependencies

- **SwiftWhisper** - Local speech recognition using Whisper model
- **ORSSerial** - USB/Serial communication with ESP32 device
- **SwiftUI** - Modern UI framework
- **Combine** - Reactive programming for state management
- **Network** - Local network permission handling

## Common Development Patterns

### Adding New Device Commands
Device commands are JSON messages sent via `VoiceDeviceManager.sendMessage()`:
```swift
let command = ["type": "command_name", "param": value]
deviceManager.sendConfiguration(command)
```

### Processing Device Messages
Add new message types in `VoiceDeviceManager.processMessage()`:
```swift
case "new_message_type":
    // Handle new message type
    break
```

### Adding AI Features
Extend `OpenAIService` for new AI capabilities:
```swift
func newAIFeature(_ input: String) {
    // Use existing sendMessage pattern
    sendMessage(input, baseURL: baseURL, apiKey: apiKey, model: model)
}
```

## Important Notes

### Local Network Permissions
The app requires local network access for AI servers. The `OpenAIService` handles permission requests through NWListener/NWBrowser pattern and requires proper Info.plist configuration.

### Whisper Model
The app bundles a Whisper model (`ggml-base.bin`) for local speech recognition. The model is loaded asynchronously and processing is queued to prevent conflicts.

### Device Communication Protocol
Communication with ESP32 follows a JSON-based protocol with specific message types for status, configuration, audio data, and control commands. All messages are newline-terminated.

### Code Signing
The build process requires proper code signing for macOS security. The build script supports both ad-hoc and Developer ID signing.

## Build System

The project uses Swift Package Manager with custom build scripting:
- `Package.swift` defines dependencies and build configuration
- `build-release.sh` creates production-ready app bundles
- `test-app.sh` provides development testing workflow

The release build process includes app bundle creation, resource copying, Info.plist generation, code signing, and optional DMG creation for distribution.