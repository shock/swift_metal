//
//  KeyboardView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/18/24.
//

import Foundation
import Cocoa
import SwiftUI

protocol KeyboardEventsDelegate: AnyObject {
    func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
}

protocol MouseEventsDelegate: AnyObject {
    func mouseDownEvent(event: NSEvent)
    func mouseUpEvent(event: NSEvent)
    func mouseMovedEvent(event: NSEvent)
    func mouseScrolledEvent(event: NSEvent)
    func rightMouseDownEvent(event: NSEvent)
    func rightMouseUpEvent(event: NSEvent)
    func mouseDraggedEvent(event: NSEvent)
    func rightMouseDraggedEvent(event: NSEvent)
    func pinchGesture(event: NSEvent)
    func rotateGesture(event: NSEvent)
    func swipeGesture(event: NSEvent)
}

class KeyboardMouseView: NSView {

    var flags = NSEvent.ModifierFlags()
    weak var keyboardDelegate: KeyboardEventsDelegate?
    weak var mouseDelegate: MouseEventsDelegate?

    override var acceptsFirstResponder: Bool { return true }

    override func keyDown(with event: NSEvent) {
        print("Key down code: \(event.keyCode)")
        keyboardDelegate?.keyDownEvent(event: event, flags: flags)
//        interpretKeyEvents([event])  // This seems to turn the event back over to the framework
    }

    override func keyUp(with event: NSEvent) {
        print("Key up code: \(event.keyCode)")
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.flags = flags
    }
    
    func captureMouse() {
//        CGAssociateMouseAndMouseCursorPosition(0)  // Lock the mouse cursor position
        NSCursor.hide()  // Hide the cursor
    }
    
    func releaseMouse() {
//        CGAssociateMouseAndMouseCursorPosition(1)  // Release the mouse cursor position
        NSCursor.unhide()  // Show the cursor
    }
    
    func centerCursor() {
        let centerPoint = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        if let window = self.window {
            let windowPoint = self.convert(centerPoint, to: nil)
            var screenPoint = window.convertPoint(toScreen: windowPoint)

            // Adjust the y-coordinate to flip it for the screen's coordinate system
            let screenHeight = NSScreen.main?.frame.height ?? 0
            screenPoint.y = screenHeight - screenPoint.y  // Flip the y-coordinate

            CGWarpMouseCursorPosition(screenPoint)
        }
    }

    override func mouseDown(with event: NSEvent) {
        print("Mouse down at \(event.locationInWindow)")
        mouseDelegate?.mouseDownEvent(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        print("Mouse up at \(event.locationInWindow)")
        mouseDelegate?.mouseUpEvent(event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        print("Mouse moved to \(event.locationInWindow)")
        mouseDelegate?.mouseMovedEvent(event: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        print("Scrolling at \(event.locationInWindow) with delta x: \(event.scrollingDeltaX), delta y: \(event.scrollingDeltaY)")
        mouseDelegate?.mouseScrolledEvent(event: event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        print("Right mouse button down at \(event.locationInWindow)")
        mouseDelegate?.rightMouseDownEvent(event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        print("Right mouse button down at \(event.locationInWindow)")
        mouseDelegate?.rightMouseUpEvent(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        print("Mouse dragged at \(event.locationInWindow) with left button")
        mouseDelegate?.mouseDraggedEvent(event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        print("Mouse dragged at \(event.locationInWindow) with right button")
        mouseDelegate?.rightMouseDraggedEvent(event: event)
    }
    
    override func magnify(with event: NSEvent) {
        print("Pinch with magnification: \(event.magnification)")
        mouseDelegate?.pinchGesture(event: event)
    }

    override func rotate(with event: NSEvent) {
        print("Rotate with rotation: \(event.rotation)")
        mouseDelegate?.rotateGesture(event: event)
    }

    override func swipe(with event: NSEvent) {
        print("Swipe with delta x: \(event.deltaX), delta y: \(event.deltaY)")
        mouseDelegate?.swipeGesture(event: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas if any
        self.trackingAreas.forEach { self.removeTrackingArea($0) }

        // Create and add a new tracking area
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }

}

struct KeyboardMouseViewRepresentable: NSViewRepresentable {
    weak var keyboardDelegate: KeyboardEventsDelegate?
    weak var mouseDelegate: MouseEventsDelegate?

    func makeNSView(context: Context) -> KeyboardMouseView {
        let view = KeyboardMouseView()
        view.keyboardDelegate = keyboardDelegate
        view.mouseDelegate = mouseDelegate
        view.becomeFirstResponder()  // Attempt to make the view the first responder
        return view
    }

    func updateNSView(_ nsView: KeyboardMouseView, context: Context) {
        // Update the delegates if needed, or handle other properties
        nsView.keyboardDelegate = keyboardDelegate
        nsView.mouseDelegate = mouseDelegate
    }
}

