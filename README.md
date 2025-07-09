# Voice Assistant macOS App

A Swift-based macOS application that communicates with the Home Assistant Voice USB device for local voice processing and AI integration.

## Features

- **USB Communication**: Direct serial communication with ESP32-S3 voice device
- **Local Speech-to-Text**: Uses OpenAI Whisper for transcription
- **AI Integration**: Configurable OpenAI API integration
- **Real-time Processing**: Live audio processing and response
- **Configurable Settings**: System prompt, max tokens, and API settings

## Requirements

- macOS 12.0+
- Swift 5.7+
- Xcode 14.0+
- OpenAI API key (for AI features)

## Setup

### Download Whisper Model
Before building, you need to download the Whisper model for speech recognition:

```bash
./download-model.sh
```

This downloads the required `ggml-base.bin` file (~141MB) to the appropriate location.

## Build and Run

### Development Mode
```bash
swift run
```

### Release Build
```bash
./build-release.sh
```

This creates a properly signed app bundle in the `dist/` directory.

## Configuration

The app provides a settings interface to configure:
- OpenAI API settings (base URL, API key, model)
- System prompt for AI responses
- Maximum tokens for AI generation
- Wake word sensitivity
- Device connection settings

## Usage

1. Connect your Home Assistant Voice USB device
2. Launch the app
3. Configure your OpenAI API settings
4. Start speaking - the device will process wake words and transcribe speech
5. AI responses are automatically generated and can be played back

## Building for Distribution

See `BUILD.md` for detailed instructions on creating release builds and distribution packages.

## Architecture

- **Swift Package Manager**: Dependency management
- **SwiftUI**: User interface
- **AVFoundation**: Audio processing
- **Network**: USB/Serial communication
- **Combine**: Reactive programming patterns