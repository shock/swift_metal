//
//  KeyboardView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/18/24.
//

import Foundation
import Cocoa
import SwiftUI

/// A custom NSView subclass to handle keyboard and mouse events.
class KeyboardMouseView: NSView {
    
    /// Protocol for handling keyboard events.
    protocol KeyboardEventsDelegate: AnyObject {
        /// Called when a key is pressed down.
        func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when a key is released.
        func keyUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when modifier flags (e.g., Shift, Control) change state.
        func flagsChangedEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
    }
    
    /// Protocol for handling mouse events.
    protocol MouseEventsDelegate: AnyObject {
        /// Called when the left mouse button is pressed down.
        func mouseDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the left mouse button is released.
        func mouseUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the mouse is moved.
        func mouseMovedEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the mouse wheel is scrolled.
        func mouseScrolledEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the right mouse button is pressed down.
        func rightMouseDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the right mouse button is released.
        func rightMouseUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the mouse is dragged with the left button pressed.
        func mouseDraggedEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when the mouse is dragged with the right button pressed.
        func rightMouseDraggedEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when a pinch gesture is performed.
        func pinchGesture(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when a rotate gesture is performed.
        func rotateGesture(event: NSEvent, flags: NSEvent.ModifierFlags)
        /// Called when a swipe gesture is performed.
        func swipeGesture(event: NSEvent, flags: NSEvent.ModifierFlags)
    }

    /// Current state of modifier flags.
    var flags = NSEvent.ModifierFlags()
    /// Delegate to handle keyboard events.
    weak var keyboardDelegate: KeyboardEventsDelegate?
    /// Delegate to handle mouse events.
    weak var mouseDelegate: MouseEventsDelegate?
    /// Last known position of the cursor.
    var lastCursorPosition = NSPoint()
    /// Debug flag to enable or disable logging.
    var debug = true
    
    /// Indicates whether the view accepts first responder status.
    override var acceptsFirstResponder: Bool { return true }

    /// Handles the key down event.
    override func keyDown(with event: NSEvent) {
        if debug { print("Key down code: \(event.keyCode)") }
        keyboardDelegate?.keyDownEvent(event: event, flags: flags)
    }

    /// Handles the key up event.
    override func keyUp(with event: NSEvent) {
        if debug { print("Key up code: \(event.keyCode)") }
        keyboardDelegate?.keyUpEvent(event: event, flags: flags)
    }

    /// Handles changes in modifier flags.
    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.flags = flags
        keyboardDelegate?.flagsChangedEvent(event: event, flags: flags)
        var modifiers = ""
        if flags.contains(.shift) { modifiers += "Shift " }
        if flags.contains(.control) { modifiers += "Control " }
        if flags.contains(.option) { modifiers += "Option " }
        if flags.contains(.command) { modifiers += "Command " }
        if flags.contains(.capsLock) { modifiers += "Capslock " }
        if flags.contains(.function) { modifiers += "Function " }
        if debug { print("Current modifiers: \(modifiers)") }
    }

    /// Captures the mouse at a specific position, hiding the cursor.
    func captureMouse(_ position: NSPoint) {
        lastCursorPosition = position
        NSCursor.hide()  // Hide the cursor
    }

    /// Releases the mouse, showing the cursor and setting it to the last known position.
    func releaseMouse() {
        setCursorPosition(lastCursorPosition)
        NSCursor.unhide()  // Show the cursor
    }

    /// Sets the cursor position to the specified point.
    func setCursorPosition(_ position: NSPoint) {
        if let window = self.window {
            let windowPoint = self.convert(position, to: nil)
            var screenPoint = window.convertPoint(toScreen: windowPoint)

            // Adjust the y-coordinate to flip it for the screen's coordinate system
            let screenHeight = NSScreen.main?.frame.height ?? 0
            screenPoint.y = screenHeight - screenPoint.y  // Flip the y-coordinate

            CGWarpMouseCursorPosition(screenPoint)
        }
    }

    /// Centers the cursor within the view.
    func centerCursor() {
        let centerPoint = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        setCursorPosition(centerPoint)
    }

    /// Handles the mouse down event.
    override func mouseDown(with event: NSEvent) {
        if debug { print("Mouse down at \(event.locationInWindow)") }
        mouseDelegate?.mouseDownEvent(event: event, flags: flags)
    }

    /// Handles the mouse up event.
    override func mouseUp(with event: NSEvent) {
        if debug { print("Mouse up at \(event.locationInWindow)") }
        mouseDelegate?.mouseUpEvent(event: event, flags: flags)
    }

    /// Handles the mouse moved event.
    override func mouseMoved(with event: NSEvent) {
        if debug { print("Mouse moved to \(event.locationInWindow)") }
        mouseDelegate?.mouseMovedEvent(event: event, flags: flags)
    }

    /// Handles the scroll wheel event.
    override func scrollWheel(with event: NSEvent) {
        if debug { print("Scrolling at \(event.locationInWindow) with delta x: \(event.scrollingDeltaX), delta y: \(event.scrollingDeltaY)") }
        mouseDelegate?.mouseScrolledEvent(event: event, flags: flags)
    }

    /// Handles the right mouse down event.
    override func rightMouseDown(with event: NSEvent) {
        if debug { print("Right mouse button down at \(event.locationInWindow)") }
        mouseDelegate?.rightMouseDownEvent(event: event, flags: flags)
    }

    /// Handles the right mouse up event.
    override func rightMouseUp(with event: NSEvent) {
        if debug { print("Right mouse button up at \(event.locationInWindow)") }
        mouseDelegate?.rightMouseUpEvent(event: event, flags: flags)
    }

    /// Handles the mouse dragged event with the left button pressed.
    override func mouseDragged(with event: NSEvent) {
        if debug { print("Mouse dragged at \(event.locationInWindow) with left button") }
        mouseDelegate?.mouseDraggedEvent(event: event, flags: flags)
    }

    /// Handles the mouse dragged event with the right button pressed.
    override func rightMouseDragged(with event: NSEvent) {
        if debug { print("Mouse dragged at \(event.locationInWindow) with right button") }
        mouseDelegate?.rightMouseDraggedEvent(event: event, flags: flags)
    }

    /// Handles the pinch gesture event.
    override func magnify(with event: NSEvent) {
        if debug { print("Pinch with magnification: \(event.magnification)") }
        mouseDelegate?.pinchGesture(event: event, flags: flags)
    }

    /// Handles the rotate gesture event.
    override func rotate(with event: NSEvent) {
        if debug { print("Rotate with rotation: \(event.rotation)") }
        mouseDelegate?.rotateGesture(event: event, flags: flags)
    }

    /// Handles the swipe gesture event.
    override func swipe(with event: NSEvent) {
        if debug { print("Swipe with delta x: \(event.deltaX), delta y: \(event.deltaY)") }
        mouseDelegate?.swipeGesture(event: event, flags: flags)
    }

    /// Updates the tracking areas for mouse events.
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

/// A SwiftUI wrapper for the KeyboardMouseView to integrate with SwiftUI views.
struct KeyboardMouseCapture: NSViewRepresentable {
    weak var keyboardDelegate: KeyboardMouseView.KeyboardEventsDelegate?
    weak var mouseDelegate: KeyboardMouseView.MouseEventsDelegate?
    var debug = false
    
    /// Creates the KeyboardMouseView instance.
    func makeNSView(context: Context) -> KeyboardMouseView {
        let view = KeyboardMouseView()
        view.keyboardDelegate = keyboardDelegate
        view.mouseDelegate = mouseDelegate
        view.debug = debug
        return view
    }

    /// Updates the KeyboardMouseView instance when SwiftUI state changes.
    func updateNSView(_ nsView: KeyboardMouseView, context: Context) {
        // Update the delegates if needed, or handle other properties
        nsView.keyboardDelegate = keyboardDelegate
        nsView.mouseDelegate = mouseDelegate
    }
}
