import SwiftUI
import AppKit

// Main entry point for executable
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Configure app for proper dock and menu bar behavior
app.setActivationPolicy(.regular)
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplication()
        Task { @MainActor in
            createMainWindow()
        }
    }
    
    @MainActor
    private func setupApplication() {
        // Ensure app appears in dock and has menu bar
        NSApp.setActivationPolicy(.regular)
        
        // Set application name
        ProcessInfo.processInfo.processName = "VoiceAssistant"
        
        // Create menu bar
        setupMenuBar()
        
        // Set app icon if available
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
        } else {
            // Create a simple default icon
            let icon = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Voice Assistant")
            icon?.size = NSSize(width: 512, height: 512)
            NSApp.applicationIconImage = icon
        }
    }
    
    @MainActor private func setupMenuBar() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About VoiceAssistant", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide VoiceAssistant", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").withModifierMask([.command, .option]))
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit VoiceAssistant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    @MainActor @objc private func showAbout() {
        let aboutPanel = NSAlert()
        aboutPanel.messageText = "VoiceAssistant"
        aboutPanel.informativeText = "Local voice assistant for Home Assistant Voice devices via USB communication.\n\nVersion 1.0\nBuilt with Swift and ESPHome"
        aboutPanel.alertStyle = .informational
        aboutPanel.runModal()
    }
    
    @MainActor private func createMainWindow() {
        let contentView = ContentView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "VoiceAssistant"
        window.center()
        window.setFrameAutosaveName("VoiceAssistant")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Remove toolbar setup for consistent SwiftUI TabView experience
        
        // Ensure window appears in front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure we disconnect from the device when the app terminates
        // This should be handled by the ContentView, but let's be safe
        print("Application terminating - ensuring device disconnection")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
}


extension NSMenuItem {
    func withModifierMask(_ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        self.keyEquivalentModifierMask = mask
        return self
    }
}

extension Notification.Name {
    static let deviceStatusUpdated = Notification.Name("deviceStatusUpdated")
    static let wakeWordOptionsUpdated = Notification.Name("wakeWordOptionsUpdated")
}