//
//  MetalGeminiApp.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/27/24.
//

import SwiftUI
import SwiftOSC

//@main
struct MetalGeminiApp: App {
    // Declare a window controller property
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // Empty content here; window will be managed in the AppDelegate
        }
//        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

// Separate AppDelegate class
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windowController: CustomWindowController! // Store window controller reference
    var uniformWindowController: UniformWindowController?
    // List to hold multiple uniform window controllers
    var uniformWindowControllers: [UniformWindowController] = []
    var mainMenu: NSMenu! // Store the main menu
    var renderMgr = RenderManager() // Create the ViewModel instance here
    var resizeWindow: ((CGFloat, CGFloat) -> Void)?
    private var oscServer: OSCServerManager!

    func setupOSCServer() {
        oscServer.startServer()
    }

    func findMenuItem(withTitle title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title {
                return item
            } else if let submenu = item.submenu {
                if let foundItem = findMenuItem(withTitle: title, in: submenu) {
                    return foundItem
                }
            }
        }
        return nil
    }

    func findMenuItem(byTag tag: Int, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.tag == tag {
                return item
            } else if let submenu = item.submenu {
                if let foundItem = findMenuItem(byTag: tag, in: submenu) {
                    return foundItem
                }
            }
        }
        return nil
    }

    private func updateMenuState() {
        if let menuItem = findMenuItem(withTitle: "Enable VSync", in: NSApplication.shared.mainMenu!) {
            DispatchQueue.main.async {
                menuItem.state = self.renderMgr.vsyncOn == true ? .on : .off
            }
        }
        if let menuItem = findMenuItem(withTitle: "Uniforms Overlay", in: NSApplication.shared.mainMenu!) {
            DispatchQueue.main.async {
                menuItem.state = self.renderMgr.uniformOverlayVisible == true ? .on : .off
            }
        }
        DispatchQueue.main.async {
            UserDefaults.standard.set(self.renderMgr.vsyncOn, forKey: "VSyncEnabled")
        }
    }

    @objc func toggleVSync(sender: NSMenuItem) {
        renderMgr.vsyncOn.toggle()
        sender.state = renderMgr.vsyncOn ? .on : .off
    }

    @objc func toggleUniformOverlay(sender: NSMenuItem) {
        renderMgr.uniformOverlayVisible.toggle()
        sender.state = renderMgr.uniformOverlayVisible ? .on : .off
    }

    @objc func toggleUniformWindows(sender: NSMenuItem) {
//        if uniformWindowController == nil {
//            // Lazily initializes the window only once
//            let overlayView = UniformsView(renderMgr: renderMgr)
//            uniformWindowController = UniformWindowController(contentView: overlayView)
//        }
//
//        // Toggle visibility of the window
//        if let window = uniformWindowController?.window {
//            if window.isVisible {
//                window.orderOut(nil)  // Hide the window
//                sender.state = .off
//            } else {
//                window.makeKeyAndOrderFront(nil)  // Show the window
//                sender.state = .on
//            }
//        }
    }

    @objc func openUniformWindow(sender: NSMenuItem) {
        let overlayView = UniformsView(renderMgr: renderMgr)
        let newWindowController = UniformWindowController(
            contentView: overlayView,
            windowId: uniformWindowControllers.count,
            windowGroup: self
        )
        uniformWindowControllers.append(newWindowController)
        newWindowController.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            // Remove the window controller from the list when window closes
            uniformWindowControllers.removeAll { $0.window === window }
            for (index, wc) in uniformWindowControllers.enumerated() {
                wc.setWindowId(index)
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            // Move the window controller for the active window to the end of the list
            let condition: (UniformWindowController) -> Bool = { $0.window == window }

            // Find the index of the element that matches the condition
            if let index = uniformWindowControllers.firstIndex(where: condition) {
                // Retrieve the element
                let element = uniformWindowControllers[index]

                // Remove the element from the array
                uniformWindowControllers.remove(at: index)
                uniformWindowControllers.append(element)
                for (index, wc) in uniformWindowControllers.enumerated() {
                    wc.setWindowId(index)
                }
            } else {
                print("No element found matching the condition")
            }
        }
    }


    @objc func openFile() {
        renderMgr.openFile()
    }

    @objc func promptForWindowSize() {
        let alert = NSAlert()
        alert.messageText = "Resize Window"
        alert.informativeText = "Enter the new width and height for the window."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let inputWidth = NSTextField(frame: NSRect(x: 0, y: 58, width: 200, height: 24))
        inputWidth.placeholderString = "Width"
        let inputHeight = NSTextField(frame: NSRect(x: 0, y: 32, width: 200, height: 24))
        inputHeight.placeholderString = "Height"

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 82))
        view.addSubview(inputWidth)
        view.addSubview(inputHeight)
        alert.accessoryView = view

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let width = CGFloat(Double(inputWidth.stringValue) ?? 600) // Default width if parsing fails
            let height = CGFloat(Double(inputHeight.stringValue) ?? 450) // Default height if parsing fails
            resizeMainWindow(width: width, height: height)
        }
    }

    func resizeMainWindow(width: CGFloat, height: CGFloat) {
        windowController.window?.setContentSize(NSSize(width: width, height: height))
//        windowController.window?.center()
    }

    @objc func updateRenderFrame(notification: Notification) {
        DispatchQueue.main.async {
            self.renderMgr.updateFrame()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(handleMenuStateChange(notification:)), name: .menuStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateRenderFrame(notification:)), name: .updateRenderFrame, object: nil)
        windowController = CustomWindowController(rootView: ContentView(renderMgr: renderMgr))
        windowController.showWindow(self)
        oscServer = OSCServerManager(delegate: self)
        setupOSCServer()

        resizeWindow = { [weak self] width, height in
            DispatchQueue.main.async {
                self?.resizeMainWindow(width: width, height: height)
            }
        }

        // Load the saved VSync state if available
        if let savedVSyncEnabled = UserDefaults.standard.object(forKey: "VSyncEnabled") as? Bool {
            renderMgr.vsyncOn = savedVSyncEnabled
        }

        // Create the main menu
        mainMenu = NSMenu(title: "MainMenu")
        let appMenu = NSMenu(title: "MetalGemini")
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Create the application's submenus (File, Edit, etc.)
        let fileMenu = NSMenu(title: "File")
        // Add items to your file menu...
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        var newItem = NSMenuItem(title: "Open", action: #selector(openFile), keyEquivalent: "o")
        fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(fileMenuItem)

        // Edit Menu
        let editMenu = NSMenu(title: "Edit")
        let copyMenuItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(copyMenuItem)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenu = NSMenu(title: "View")
        // Add items to your file menu...
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        let vsyncItem = NSMenuItem(title: "Enable VSync", action: #selector(toggleVSync), keyEquivalent: "v")
        viewMenu.addItem(vsyncItem)
        let toggleUniformOverlay = NSMenuItem(title: "Uniforms Overlay", action: #selector(toggleUniformOverlay), keyEquivalent: "u")
        viewMenu.addItem(toggleUniformOverlay)
//        let toggleUniformWindow = NSMenuItem(title: "Show Uniforms", action: #selector(toggleUniformWindow), keyEquivalent: "p")
//        viewMenu.addItem(toggleUniformWindow)
        let openUniformWindowItem = NSMenuItem(title: "Show Uniforms", action: #selector(openUniformWindow), keyEquivalent: "p")
        viewMenu.addItem(openUniformWindowItem)
        viewMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(viewMenuItem)

        let windowMenu = NSMenu(title: "Window")
        // Add items to your file menu...
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        newItem = NSMenuItem(title: "Resize Render Window", action: #selector(promptForWindowSize), keyEquivalent: "r")
        windowMenu.addItem(newItem)
        windowMenu.addItem(NSMenuItem.separator()) // Add a separator
        let closeMenuItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(closeMenuItem)
        windowMenu.addItem(NSMenuItem.separator())

        // If you have specific settings for your menu item like this, make sure it's set correctly
        closeMenuItem.target = nil  // Target is nil so that it uses the responder chain
        mainMenu.addItem(windowMenuItem)

        NSApp.windowsMenu = NSMenu(title: "Window") // Add a default Window menu

        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
        updateMenuState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Let SwiftUI manage window closing
    }

    @objc func handleMenuStateChange(notification: Notification) {
//        if let userInfo = notification.userInfo, let _ = userInfo["enabled"] as? Bool {
            DispatchQueue.main.async {
                self.updateMenuState()
            }
//        }
    }

}

extension AppDelegate: OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage) {
        self.renderMgr.handleOSCMessage(message: message)
    }
}
