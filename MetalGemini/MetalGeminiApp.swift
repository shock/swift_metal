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
        .windowStyle(HiddenTitleBarWindowStyle())
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
        let appMenuItem = NSMenu(title: "MetalGemini")
        appMenuItem.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenu1 = NSMenuItem()
        appMenu1.submenu = appMenuItem
        mainMenu.addItem(appMenu1)

        // Create the application's submenus (File, Edit, etc.)
        let fileMenu = NSMenu(title: "File")
        // Add items to your file menu...
        let appMenu = NSMenuItem()
        appMenu.submenu = fileMenu
        mainMenu.addItem(appMenu)
        
        // File Menu
//        let fileMenu = NSMenu(title: "File")
        let newItem = NSMenuItem(title: "New", action: #selector(createNewFile), keyEquivalent: "n")
        fileMenu.addItem(newItem)
        fileMenu.addItem(NSMenuItem.separator()) // Add a separator
//        fileMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
//        mainMenu.addItem(fileMenu)


        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Let SwiftUI manage window closing
    }
}
