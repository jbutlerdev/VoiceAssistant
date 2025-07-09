#!/bin/bash

# Download Whisper Model Script
# This script downloads the required Whisper model for the Voice Assistant App

set -e  # Exit on error

MODEL_DIR="Sources/VoiceAssistantApp/Resources"
MODEL_FILE="ggml-base.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"

echo "🎤 Downloading Whisper model for Voice Assistant App..."

# Create the Resources directory if it doesn't exist
mkdir -p "$MODEL_DIR"

# Check if model already exists
if [ -f "$MODEL_PATH" ]; then
    echo "✅ Model already exists at $MODEL_PATH"
    echo "   Size: $(du -h "$MODEL_PATH" | cut -f1)"
    echo "   To re-download, delete the file and run this script again"
    exit 0
fi

# Download the model
echo "📥 Downloading model from: $MODEL_URL"
echo "   Destination: $MODEL_PATH"
echo "   Expected size: ~141MB"

# Use curl to download with progress bar
if command -v curl &> /dev/null; then
    curl -L --progress-bar -o "$MODEL_PATH" "$MODEL_URL"
elif command -v wget &> /dev/null; then
    wget --progress=bar -O "$MODEL_PATH" "$MODEL_URL"
else
    echo "❌ Error: Neither curl nor wget found. Please install one of them."
    exit 1
fi

# Verify the download
if [ -f "$MODEL_PATH" ]; then
    MODEL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null)
    if [ "$MODEL_SIZE" -gt 100000000 ]; then  # Should be > 100MB
        echo "✅ Model downloaded successfully!"
        echo "   Size: $(du -h "$MODEL_PATH" | cut -f1)"
        echo "   Location: $MODEL_PATH"
    else
        echo "❌ Error: Downloaded file seems too small ($MODEL_SIZE bytes)"
        echo "   Expected size: ~141MB"
        rm -f "$MODEL_PATH"
        exit 1
    fi
else
    echo "❌ Error: Download failed - file not found"
    exit 1
fi

echo ""
echo "🏗️  You can now build and run the Voice Assistant App:"
echo "   swift run              # Development mode"
echo "   ./build-release.sh     # Release build"