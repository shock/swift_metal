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
    convenience init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 450)) // Set the frame size
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 450)) // Set initial size
//        window.styleMask.remove(.resizable) // Optionally disable resizing
        self.init(window: window)
        window.title = "MetalGemini"  // Set the title
    }
}
