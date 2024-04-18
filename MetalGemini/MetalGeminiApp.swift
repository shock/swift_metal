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

    @objc func createNewFile() {
        viewModel.openFileDialog = true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = CustomWindowController(rootView: ContentView(model: viewModel))
        windowController.showWindow(self)

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
        let newItem = NSMenuItem(title: "Open", action: #selector(createNewFile), keyEquivalent: "o")
        fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(fileMenuItem)
        
        NSApp.windowsMenu = NSMenu(title: "Window") // Add a default Window menu

        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Let SwiftUI manage window closing
    }
}

