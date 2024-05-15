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
    let ScrollActiveTimeout = 0.25 // seconds
    var onScrollY: ((CGFloat) -> Void)?
    var onScrollStart: (() -> Void)?
    var onScrollStop: (() -> Void)?
    var lastScrollTime = Date() - 10
    var stopDebouncer: Debouncer

    override init(frame: NSRect) {
        self.stopDebouncer = Debouncer(delay: ScrollActiveTimeout, queueLabel: "net.wdoughty.metaltoy.ScrollableAreaView")
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            if event.scrollingDeltaY != 0 {
                if !stopDebouncer.isPending() {
                    self.onScrollStart?()
                }
                self.onScrollY?(event.scrollingDeltaY)
                stopDebouncer.debounce { [weak self] in
                    self?.onScrollStop?()
                    self?.lastScrollTime = Date() - 10
                }
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
    var onScrollStart: (() -> Void)?
    var onScrollStop: (() -> Void)?

    func makeNSView(context: Context) -> ScrollableAreaView {
        ScrollableAreaView()
    }

    func updateNSView(_ nsView: ScrollableAreaView, context: Context) {
        nsView.onScrollY = onScrollY
        nsView.onScrollStart = onScrollStart
        nsView.onScrollStop = onScrollStop
    }
}
