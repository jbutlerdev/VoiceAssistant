# Building Voice Assistant App

This document explains how to build and release the Voice Assistant App for macOS.

## Prerequisites

- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 5.9 or later
- Git

## Development Setup

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/home-assistant-voice-pe.git
cd home-assistant-voice-pe/VoiceAssistantApp
```

### 2. Install Dependencies
The project uses Swift Package Manager, so dependencies are automatically resolved:
```bash
swift package resolve
```

### 3. Development Build
For development and testing:
```bash
swift build
swift run
```

## Release Build Process

### Automated Build (Recommended)

Use the provided build script to create a properly signed macOS app bundle:

```bash
./build-release.sh
```

This script will:
1. Clean previous builds
2. Build the release version with optimizations
3. Create a proper macOS app bundle structure
4. Add the required Info.plist with local network permissions
5. Copy all resources (including the Whisper model)
6. Code sign the app (ad-hoc or with Developer ID)
7. Create a ZIP archive for distribution
8. Optionally create a DMG if `create-dmg` is installed

The output will be in the `dist/` directory:
- `VoiceAssistantApp.app` - The signed application bundle
- `VoiceAssistantApp.zip` - ZIP archive for distribution
- `VoiceAssistantApp.dmg` - DMG installer (if create-dmg is available)

### Manual Build Process

If you need to build manually:

1. **Build Release Version**
   ```bash
   swift build -c release
   ```

2. **Create App Bundle Structure**
   ```bash
   mkdir -p VoiceAssistantApp.app/Contents/MacOS
   mkdir -p VoiceAssistantApp.app/Contents/Resources
   ```

3. **Copy Executable**
   ```bash
   cp .build/release/VoiceAssistantApp VoiceAssistantApp.app/Contents/MacOS/
   ```

4. **Copy Resources**
   ```bash
   cp .build/release/VoiceAssistantApp_VoiceAssistantApp.bundle/ggml-base.bin \
      VoiceAssistantApp.app/Contents/Resources/
   ```

5. **Create Info.plist**
   Create `VoiceAssistantApp.app/Contents/Info.plist` with the content from the build script.

6. **Code Sign**
   ```bash
   # Ad-hoc signing
   codesign --force --deep --sign - VoiceAssistantApp.app
   
   # Or with Developer ID
   codesign --force --deep --sign "Developer ID Application: Your Name" VoiceAssistantApp.app
   ```

## Code Signing

### Ad-hoc Signing
The build script uses ad-hoc signing by default, which works for local distribution but shows warnings when downloaded from the internet.

### Developer ID Signing
For distribution outside the App Store:
```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
./build-release.sh
```

### Notarization
For wider distribution, notarize the app:
```bash
xcrun notarytool submit dist/VoiceAssistantApp.zip \
  --apple-id "your-apple-id@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait
```

## Local Network Permission

The app requires local network permission to communicate with AI servers on your network. This is handled automatically through:

1. **Info.plist Entry**: `NSLocalNetworkUsageDescription` explains why the app needs local network access
2. **Permission Request**: The app uses `NWBrowser` and `NWListener` to trigger the system permission dialog
3. **System Settings**: Users can manage the permission in System Settings > Privacy & Security > Local Network

## Troubleshooting

### Build Errors

1. **"bad CPU type in executable"** on Apple Silicon
   ```bash
   softwareupdate --install-rosetta
   ```

2. **Missing Dependencies**
   ```bash
   swift package resolve
   swift package update
   ```

3. **Code Signing Issues**
   - Ensure Xcode Command Line Tools are installed
   - Check your Developer ID is valid: `security find-identity -v -p codesigning`

### Runtime Issues

1. **Local Network Permission Not Appearing**
   - The app must be properly signed
   - Launch from Finder, not Terminal
   - Check Console.app for permission errors

2. **Whisper Model Not Found**
   - Ensure `ggml-base.bin` is in the Resources directory
   - Check the build log for resource copying errors

## Creating a DMG

Install create-dmg for prettier distribution:
```bash
brew install create-dmg
```

Then the build script will automatically create a DMG with:
- Custom window layout
- Application shortcut to /Applications
- Background image (if provided)

## CI/CD Integration

For GitHub Actions:
```yaml
name: Build Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Release
        run: |
          cd VoiceAssistantApp
          ./build-release.sh
      - name: Upload Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: VoiceAssistantApp
          path: VoiceAssistantApp/dist/*
```

## Distribution

1. **Direct Download**: Share the ZIP file from `dist/`
2. **GitHub Releases**: Upload the ZIP/DMG to GitHub Releases
3. **Homebrew**: Create a formula for `brew install`
4. **Mac App Store**: Requires additional entitlements and review

## Version Management

Update version numbers in:
1. `Package.swift` - Update package version
2. `build-release.sh` - Update CFBundleShortVersionString
3. Create a git tag: `git tag v1.0.0 && git push --tags`