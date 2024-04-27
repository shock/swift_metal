//
//  ThreadSafeFlag.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/27/24.
//

import Foundation

class ThreadSafeFlag {
    private var dirty: Bool = false
    private let queue = DispatchQueue(label: "net.wdoughty.metaltoy.dirtyAccessQueue")

    var isDirty: Bool {
        get {
            queue.sync { dirty }
        }
        set {
            queue.async { self.dirty = newValue }
        }
    }

    func setDirty() {
        queue.async { self.dirty = true }
    }

    func clearDirty() {
        queue.async { self.dirty = false }
    }
}
