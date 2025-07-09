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
        createMainWindow()
    }
    
    private func setupApplication() {
        // Ensure app appears in dock and has menu bar
        NSApp.setActivationPolicy(.regular)
        
        // Set application name
        ProcessInfo.processInfo.processName = "Home Assistant Voice - Local"
        
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
    
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Home Assistant Voice - Local", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Home Assistant Voice - Local", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").withModifierMask([.command, .option]))
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Home Assistant Voice - Local", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
    
    @objc private func showAbout() {
        let aboutPanel = NSAlert()
        aboutPanel.messageText = "Home Assistant Voice - Local"
        aboutPanel.informativeText = "Local voice assistant for Home Assistant Voice devices via USB communication.\n\nVersion 1.0\nBuilt with Swift and ESPHome"
        aboutPanel.alertStyle = .informational
        aboutPanel.runModal()
    }
    
    private func createMainWindow() {
        let contentView = ContentView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Home Assistant Voice - Local"
        window.center()
        window.setFrameAutosaveName("HomeAssistantVoiceLocal")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Configure window toolbar
        setupWindowToolbar()
        
        // Ensure window appears in front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupWindowToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.delegate = self
        window.toolbar = toolbar
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
    
    // MARK: - Toolbar Actions
    @objc private func showConnectionTab() {
        // Send notification to switch to connection tab
        NotificationCenter.default.post(name: .switchToTab, object: 0)
    }
    
    @objc private func showDeviceTab() {
        // Send notification to switch to device tab
        NotificationCenter.default.post(name: .switchToTab, object: 1)
    }
    
    @objc private func showAITab() {
        // Send notification to switch to AI tab
        NotificationCenter.default.post(name: .switchToTab, object: 2)
    }
}

// MARK: - Toolbar Delegate
extension AppDelegate: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
        case NSToolbarItem.Identifier("connection"):
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Connection"
            item.paletteLabel = "Device Connection"
            item.toolTip = "View device connection status"
            item.target = self
            item.action = #selector(showConnectionTab)
            if let image = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: "Connection") {
                image.size = NSSize(width: 32, height: 32)
                item.image = image
            }
            return item
            
        case NSToolbarItem.Identifier("device"):
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Device"
            item.paletteLabel = "Device Settings"
            item.toolTip = "Configure device settings"
            item.target = self
            item.action = #selector(showDeviceTab)
            if let image = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "Device") {
                image.size = NSSize(width: 32, height: 32)
                item.image = image
            }
            return item
            
        case NSToolbarItem.Identifier("ai"):
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "AI Config"
            item.paletteLabel = "AI Configuration"
            item.toolTip = "Configure AI settings"
            item.target = self
            item.action = #selector(showAITab)
            if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "AI Config") {
                image.size = NSSize(width: 32, height: 32)
                item.image = image
            }
            return item
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("connection"),
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier("device"),
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier("ai")
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("connection"),
            NSToolbarItem.Identifier("device"),
            NSToolbarItem.Identifier("ai"),
            NSToolbarItem.Identifier.flexibleSpace,
            NSToolbarItem.Identifier.space
        ]
    }
}

extension NSMenuItem {
    func withModifierMask(_ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        self.keyEquivalentModifierMask = mask
        return self
    }
}

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
    static let deviceStatusUpdated = Notification.Name("deviceStatusUpdated")
    static let wakeWordOptionsUpdated = Notification.Name("wakeWordOptionsUpdated")
}