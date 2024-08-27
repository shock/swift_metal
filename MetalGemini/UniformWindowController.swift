//
//  UniformWindowController.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/7/24.
//

import Foundation
import Cocoa
import SwiftUI

class UniformWindowController: NSWindowController, NSWindowDelegate {
    var contentView: any View
    var windowGroup: NSWindowDelegate
    private var windowId: Int = 0

    init<Content: View>(contentView: Content, windowId: Int, windowGroup: NSWindowDelegate ) {
        self.contentView = contentView
        let hostingController = NSHostingController(rootView: contentView)
        let window = ClickThroughWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 840, height: 436))
        window.title = "Uniforms"
        self.windowGroup = windowGroup
        super.init(window: window)
        window.delegate = self
        self.windowId = windowId
        setupWindowProperties()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindowProperties() {
        window?.delegate = self
        loadWindowFrame()
    }

    func setWindowId(_ windowId: Int) {
        self.windowId = windowId
    }

    private func windowKey() -> String {
        let key = "LastUniWindowFrame\(windowId)"
        print(key)
        return key
    }

    private func loadWindowFrame() {
        let key = windowKey()
        if let frameString = UserDefaults.standard.string(forKey: key) {
            print("loading window data")
            let frame = NSRectFromString(frameString)
            window?.setFrame(frame, display: true)
        }
    }

    private func updateBackgroundColor() {
        if window?.isKeyWindow ?? false {
            window?.backgroundColor = NSColor.black.blended(withFraction: 0.1   , of: NSColor.white) // Color when window is key
        } else {
            window?.backgroundColor = NSColor.black.withAlphaComponent(0.9) // Color when window is not key
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        windowGroup.windowDidBecomeKey?(notification)
        updateBackgroundColor()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateBackgroundColor()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = window {
            windowGroup.windowWillClose?(notification)
            let key = windowKey()
            print("saving window data")
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: key)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Allow uniform windows to close
        return true
    }

}
