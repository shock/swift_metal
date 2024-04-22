//
//  MetalGeminiApp.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/27/24.
//

import SwiftUI

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
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: CustomWindowController! // Store window controller reference
    var mainMenu: NSMenu! // Store the main menu
    var viewModel = RenderDataModel() // Create the ViewModel instance here
    var resizeWindow: ((CGFloat, CGFloat) -> Void)?

    // Initialize a variable to track the VSync state
    var vsyncEnabled: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.viewModel.coordinator?.updateVSyncState(self.vsyncEnabled)
                UserDefaults.standard.set(self.vsyncEnabled, forKey: "VSyncEnabled")
                self.updateMenuState()
            }
        }
    }

    private func updateMenuState() {
        if let menu = NSApplication.shared.mainMenu {
            let vsyncItem = menu.item(withTitle: "Enable VSync")
            vsyncItem?.state = vsyncEnabled ? .on : .off
        }
    }

    @objc func toggleVSync(sender: NSMenuItem) {
        vsyncEnabled.toggle()
        sender.state = vsyncEnabled ? .on : .off
    }

    @objc func createNewFile() {
        viewModel.openFileDialog = true
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = CustomWindowController(rootView: ContentView(model: viewModel))
        windowController.showWindow(self)

        resizeWindow = { [weak self] width, height in
            DispatchQueue.main.async {
                self?.resizeMainWindow(width: width, height: height)
            }
        }

        // Load the saved VSync state if available
        if let savedVSyncEnabled = UserDefaults.standard.object(forKey: "VSyncEnabled") as? Bool {
            vsyncEnabled = savedVSyncEnabled
        }

        viewModel.coordinator?.updateVSyncState(vsyncEnabled)
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
        var newItem = NSMenuItem(title: "Open", action: #selector(createNewFile), keyEquivalent: "o")
        fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(fileMenuItem)

        let viewMenu = NSMenu(title: "View")
        // Add items to your file menu...
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        let vsyncItem = NSMenuItem(title: "Enable VSync", action: #selector(toggleVSync), keyEquivalent: "v")
        vsyncItem.state = vsyncEnabled ? .on : .off
        viewMenu.addItem(vsyncItem)
        viewMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(viewMenuItem)

        let windowMenu = NSMenu(title: "Window")
        // Add items to your file menu...
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        newItem = NSMenuItem(title: "Resize Window", action: #selector(promptForWindowSize), keyEquivalent: "r")
        windowMenu.addItem(newItem)
        windowMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(windowMenuItem)

        NSApp.windowsMenu = NSMenu(title: "Window") // Add a default Window menu

        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Let SwiftUI manage window closing
    }
}
