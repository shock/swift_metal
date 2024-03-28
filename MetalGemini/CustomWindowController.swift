//
//  CustomWindowController.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/27/24.
//

import Foundation
import Cocoa
import SwiftUI

class CustomWindowController: NSWindowController {
    convenience init(rootView: ContentView) {
         let hostingController = NSHostingController(rootView: rootView)
         let window = NSWindow(contentViewController: hostingController)
         window.setContentSize(NSSize(width: 600, height: 450)) // Set initial size
         window.styleMask.remove(.resizable) // Optionally disable resizing
         self.init(window: window)
    }
}
