//
//  ScrollableArea.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/8/24.
//

import Foundation
import Cocoa
import SwiftUI

class ScrollableAreaView: NSView {
    var onScrollY: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            if event.scrollingDeltaY != 0 {
                self.onScrollY?(event.scrollingDeltaY)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }

    override var isFlipped: Bool {
        return true // Ensure coordinate system matches SwiftUI's default
    }
}

struct ScrollableArea: NSViewRepresentable {
    var onScrollY: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollableAreaView {
        ScrollableAreaView()
    }

    func updateNSView(_ nsView: ScrollableAreaView, context: Context) {
        nsView.onScrollY = onScrollY
    }
}
