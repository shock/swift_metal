//
//  KeyboardView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/18/24.
//

import Foundation
import Cocoa

protocol KeyboardViewDelegate: AnyObject {
    func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags)
}

class KeyboardView: NSView {

    var flags = NSEvent.ModifierFlags()
    weak var delegate: KeyboardViewDelegate?

    override var acceptsFirstResponder: Bool { return true }

    override func keyDown(with event: NSEvent) {
        print("Key down code: \(event.keyCode)")
        delegate?.keyDownEvent(event: event, flags: flags)
//        interpretKeyEvents([event])  // This seems to turn the event back over to the framework
    }

    override func keyUp(with event: NSEvent) {
        print("Key up code: \(event.keyCode)")
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.flags = flags
    }
}
