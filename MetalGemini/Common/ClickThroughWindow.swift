//
//  ClickThroughWindow.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/11/24.
//

import Foundation

import Cocoa

class ClickThroughWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // Check if the window is already key, if not, make it key and perform click-through
            if !self.isKeyWindow {
                self.makeKeyAndOrderFront(self)
                let localPoint = self.convertPoint(fromScreen: event.locationInWindow)
                if let _ = self.contentView?.hitTest(localPoint) {
                    super.sendEvent(event)  // Ensure the event is processed by the target view
                }
                return
            }
        }
        // For all other events, just pass them through the default handler
        super.sendEvent(event)
    }
}
