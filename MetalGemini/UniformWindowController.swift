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
    var contentView: UniformsView

    init(contentView: UniformsView) {
        self.contentView = contentView
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.title = "Uniforms"
        super.init(window: window)
        window.delegate = self
        setupWindowProperties()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindowProperties() {
        window?.delegate = self
        loadWindowFrame()
    }

    private func loadWindowFrame() {
        if let frameString = UserDefaults.standard.string(forKey: "LastUniWindowFrame") {
            let frame = NSRectFromString(frameString)
            window?.setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = window {
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: "LastUniWindowFrame")
        }
    }


}
