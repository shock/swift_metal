//
//  KeyboardView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/18/24.
//

import Foundation
import Cocoa

class KeyboardView: NSView {
    
    override var acceptsFirstResponder: Bool { return true }

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        print("Key down code: \(event.keyCode)")
//        interpretKeyEvents([event])  // This will trigger keyUp and keyDown
    }

    override func keyUp(with event: NSEvent) {
        print("Key up code: \(event.keyCode)")
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = ""
        if flags.contains(.shift) {
            modifiers += "Shift "
        }
        if flags.contains(.control) {
            modifiers += "Control "
        }
        if flags.contains(.option) {
            modifiers += "Option "
        }
        if flags.contains(.command) {
            modifiers += "Command "
        }
        print("Current modifiers: \(modifiers)")
    }
}
