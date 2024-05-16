//
//  GlobalKeyboardEventHandler.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/12/24.
//

import Foundation
import AppKit

class GlobalKeyboardEventHandler: ObservableObject, Observable {

    protocol KeyboardEventsDelegate: AnyObject {
        /// return the `event` to propogate event handling.  return `nil` to consume the event and stop propogation
        func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
        /// return the `event` to propogate event handling.  return `nil` to consume the event and stop propogation
        func keyUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
        /// return the `event` to propogate event handling.  return `nil` to consume the event and stop propogation
        func flagsChangedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) -> NSEvent?
    }

    private var eventMonitors: [Any?] = []
    private var flags = NSEvent.ModifierFlags()
    private var handleEvents = true
    weak var keyboardDelegate: KeyboardEventsDelegate?
    let debug = false

    init(keyboardDelegate: KeyboardEventsDelegate) {
        self.keyboardDelegate = keyboardDelegate
        setupKeyboardEventMonitoring()
    }

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

    private func handleKeyDownEvent(event: NSEvent) -> NSEvent? {
        if debug { print("Key down code: \(event.keyCode)") }
        return keyboardDelegate?.keyDownEvent(event: event, flags: flags)
    }

    private func handleKeyUpEvent(event: NSEvent) -> NSEvent?  {
        if debug { print("Key up code: \(event.keyCode)") }
        return keyboardDelegate?.keyUpEvent(event: event, flags: flags)
    }

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

    func suspendHandling() {
        handleEvents = false
    }

    func resumeHandling() {
        handleEvents = true
    }

    deinit {
        for eventMonitor in eventMonitors {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        eventMonitors.removeAll()
    }
}
    
