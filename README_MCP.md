# MCP Integration for Voice Assistant

## Overview

The Voice Assistant app now includes Model Context Protocol (MCP) integration, allowing users to extend the AI assistant's capabilities with external tools and resources.

## Features

- **MCP Server Management**: Add, edit, and remove MCP servers through the GUI
- **Tool Selection**: Select which tools from each MCP server to expose to the AI
- **Persistent Configuration**: MCP server configurations are saved and restored automatically
- **System Prompt Enhancement**: Selected MCP tools are automatically included in the AI system prompt

## How to Use

1. **Open the MCP Tab**: Launch the app and navigate to the "MCP" tab
2. **Add a Server**: Click "Add Server" and enter:
   - Server name
   - Command to launch the MCP server
   - Command arguments (optional)
3. **Enable Tools**: Expand the server entry to see available tools and toggle which ones to enable
4. **Integration**: Enabled tools will be automatically included in the AI's system prompt

## Implementation Status

### Completed ✅
- Swift 6.0 upgrade and MCP SDK integration
- Complete UI for MCP server management
- Tool selection and persistence
- Integration with OpenAI service for enhanced prompts
- Mock implementation for testing

### TODO 🔄
- Replace mock implementation with real MCP server subprocess spawning
- Add proper tool execution when function calling is implemented
- Handle MCP server connection errors and retries

## Technical Details

The implementation includes:
- `MCPManager.swift`: Manages MCP server connections and tool discovery
- `MCPModels.swift`: Data models for server configuration and tool information
- `MCPConfigurationView.swift`: SwiftUI interface for server management
- Integration with `OpenAIService.swift` to enhance system prompts

## Building

```bash
swift build
./.build/arm64-apple-macosx/debug/VoiceAssistantApp
```

The project now requires Swift 6.0+ due to the MCP SDK dependency.