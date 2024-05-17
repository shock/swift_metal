//
//  GlobalKeyboardEventHandler.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/12/24.
//

import Foundation
import AppKit

/// A class that handles global keyboard events in a macOS application.
/// It monitors key presses, key releases, and modifier flag changes,
/// delegating the event handling to a specified delegate.
class GlobalKeyboardEventHandler: ObservableObject {
    
    /// Protocol defining methods for handling keyboard events.
    protocol KeyboardEventsDelegate: AnyObject {
        /// Handles key down events.
        /// - Parameters:
        ///   - event: The keyboard event.
        ///   - flags: The modifier flags at the time of the event.
        /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
        func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
        
        /// Handles key up events.
        /// - Parameters:
        ///   - event: The keyboard event.
        ///   - flags: The modifier flags at the time of the event.
        /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
        func keyUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
        
        /// Handles flags changed events.
        /// - Parameters:
        ///   - event: The keyboard event.
        ///   - flags: The modifier flags at the time of the event.
        /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
        func flagsChangedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
    }

    /// Holds references to the event monitors for cleanup.
    private var eventMonitors: [Any?] = []
    
    /// Stores the current state of the modifier flags.
    private var flags = NSEvent.ModifierFlags()
    
    /// Determines whether events should be handled.
    private var handleEvents = true
    
    /// A weak reference to the delegate that will handle the keyboard events.
    private weak var keyboardDelegate: KeyboardEventsDelegate?
    
    /// Enables or disables debug logging.
    private var  debug = false

    /// Initializes the event handler with the provided delegate and sets up the event monitoring.
    /// - Parameter keyboardDelegate: The delegate that will handle the keyboard events.
    init(keyboardDelegate: KeyboardEventsDelegate, debug: Bool = false) {
        self.keyboardDelegate = keyboardDelegate
        self.debug = debug
        setupKeyboardEventMonitoring()
    }

    /// Sets up local event monitors for key down, key up, and flags changed events.
    private func setupKeyboardEventMonitoring() {
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.handleEvents else { return event }
            return self.handleKeyDownEvent(event: event)
        })
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self, self.handleEvents else { return event }
            return self.handleKeyUpEvent(event: event)
        })
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self, self.handleEvents else { return event }
            return self.handleFlagsChangedEvent(event: event)
        })
    }

    /// Handles key down events, optionally logging the key code if debugging is enabled, and delegates the event to `keyboardDelegate`.
    /// - Parameter event: The keyboard event.
    /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
    private func handleKeyDownEvent(event: NSEvent) -> NSEvent? {
        if debug { print("Key down code: \(event.keyCode)") }
        return keyboardDelegate?.keyDownEvent(event: event, flags: flags)
    }

    /// Handles key up events, optionally logging the key code if debugging is enabled, and delegates the event to `keyboardDelegate`.
    /// - Parameter event: The keyboard event.
    /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
    private func handleKeyUpEvent(event: NSEvent) -> NSEvent?  {
        if debug { print("Key up code: \(event.keyCode)") }
        return keyboardDelegate?.keyUpEvent(event: event, flags: flags)
    }

    /// Handles modifier flags changed events, updates the `flags` property, logs the current modifiers if debugging is enabled, and delegates the event to `keyboardDelegate`.
    /// - Parameter event: The keyboard event.
    /// - Returns: The event to propagate, or `nil` to consume the event and stop propagation.
    private func handleFlagsChangedEvent(event: NSEvent) -> NSEvent?  {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.flags = flags
        var modifiers = ""
        if flags.contains(.shift) { modifiers += "Shift " }
        if flags.contains(.control) { modifiers += "Control " }
        if flags.contains(.option) { modifiers += "Option " }
        if flags.contains(.command) { modifiers += "Command " }
        if flags.contains(.capsLock) { modifiers += "Capslock " }
        if flags.contains(.function) { modifiers += "Function " }
        if debug { print("Current modifiers: \(modifiers)") }
        return keyboardDelegate?.flagsChangedEvent(event: event, flags: flags)
    }

    /// Disables event handling by setting `handleEvents` to `false`.
    func suspendHandling() {
        handleEvents = false
    }

    /// Enables event handling by setting `handleEvents` to `true`.
    func resumeHandling() {
        handleEvents = true
    }

    /// Cleans up the event monitors by removing them when the instance is deallocated.
    deinit {
        for eventMonitor in eventMonitors {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        eventMonitors.removeAll()
    }
}
