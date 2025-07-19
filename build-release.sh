#!/bin/bash

# Voice Assistant App - Release Build Script
# This script builds a properly signed macOS app bundle from the Swift Package Manager project

set -e  # Exit on error

# Configuration
APP_NAME="VoiceAssistantApp"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR=".build/release"
DIST_DIR="dist"

echo "🏗️  Building Voice Assistant App Release..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$DIST_DIR"
rm -rf "$BUNDLE_NAME"
swift package clean

# Build release version
echo "🔨 Building release version with Swift Package Manager..."
swift build -c release

# Create distribution directory
mkdir -p "$DIST_DIR"

# Create app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUNDLE_NAME}/Contents/Resources"

# Copy executable
echo "📋 Copying executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_NAME}/Contents/MacOS/"

# Copy resources
echo "📋 Copying resources..."
if [ -f "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/ggml-base.bin" ]; then
    cp "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/ggml-base.bin" "${BUNDLE_NAME}/Contents/Resources/"
else
    echo "⚠️  Warning: ggml-base.bin not found in build bundle"
fi

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "${BUNDLE_NAME}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoiceAssistantApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.homeassistant.voice.local</string>
    <key>CFBundleName</key>
    <string>Voice Assistant</string>
    <key>CFBundleDisplayName</key>
    <string>Voice Assistant</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>This app needs to access devices on your local network to communicate with AI servers and voice assistant services.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Code sign the app
echo "🔏 Code signing the app..."
if [[ -n "$DEVELOPER_ID" ]]; then
    # If DEVELOPER_ID environment variable is set, use it
    echo "Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --deep --sign "$DEVELOPER_ID" "${BUNDLE_NAME}"
else
    # Otherwise use ad-hoc signing
    echo "Using ad-hoc signing (no Developer ID found)"
    codesign --force --deep --sign - "${BUNDLE_NAME}"
fi

# Verify code signature
echo "✅ Verifying code signature..."
codesign --verify --verbose "${BUNDLE_NAME}"

# Move to distribution directory
echo "📦 Moving to distribution directory..."
mv "${BUNDLE_NAME}" "${DIST_DIR}/"

# Create DMG (optional)
if command -v create-dmg &> /dev/null; then
    echo "💿 Creating DMG..."
    create-dmg \
        --volname "${APP_NAME}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 175 120 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 425 120 \
        "${DIST_DIR}/${APP_NAME}.dmg" \
        "${DIST_DIR}/${BUNDLE_NAME}"
else
    echo "ℹ️  Skipping DMG creation (install create-dmg with 'brew install create-dmg')"
fi

# Create ZIP for distribution
echo "🗜️  Creating ZIP archive..."
cd "$DIST_DIR"
zip -r "${APP_NAME}.zip" "${BUNDLE_NAME}"
cd ..

echo "✅ Build complete!"
echo "📍 Output location: ${DIST_DIR}/"
echo ""
echo "Available files:"
ls -la "$DIST_DIR/"
