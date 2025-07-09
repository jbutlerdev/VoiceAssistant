#!/bin/bash
echo "Testing Home Assistant Voice - Local App"
echo "========================================"

# Build the app
echo "Building the app..."
swift build

if [ $? -eq 0 ]; then
    echo "✅ App built successfully"
else
    echo "❌ App build failed"
    exit 1
fi

# Check for USB devices
echo ""
echo "Checking for USB devices..."
if ls /dev/cu.usbmodem* 1> /dev/null 2>&1; then
    echo "✅ ESP32 device found: $(ls /dev/cu.usbmodem*)"
else
    echo "⚠️  No ESP32 device found"
fi

echo ""
echo "Run 'swift run' to start the app"
echo "The app should now have:"
echo "  ✅ Single top tab navigation (no left sidebar)"
echo "  ✅ Functional toolbar icons"
echo "  ✅ USB device auto-connection"
echo "  ✅ Dock icon and menu bar"