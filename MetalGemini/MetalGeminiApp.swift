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
    
    @objc func createNewFile() {}
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = CustomWindowController(rootView: ContentView())
        windowController.showWindow(nil)

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
        let newItem = NSMenuItem(title: "New", action: #selector(createNewFile), keyEquivalent: "n")
        fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem.separator()) // Add a separator
        mainMenu.addItem(fileMenuItem)
        
//        let windowMenu = NSMenu(title: "Window")
//        let windowMenuItem = NSMenuItem()
//        let showWindowItem = NSMenuItem(title: "Show", action: #selector(showRenderWindow), keyEquivalent: "n")
//        windowMenu.addItem(showWindowItem)
//        windowMenu.addItem(NSMenuItem.separator()) // Add a separator
//        windowMenuItem.submenu = windowMenu
//        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = NSMenu(title: "Window") // Add a default Window menu

        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true // Let SwiftUI manage window closing
    }
}

