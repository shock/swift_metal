//
//  CustomWindowController.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/27/24.
//

import Foundation
import Cocoa
import SwiftUI
import Combine

class CustomWindowController: NSWindowController, NSWindowDelegate  {
    private var viewModel: RenderDataModel?
    private var cancellables: Set<AnyCancellable> = []

    convenience init(rootView: ContentView) {
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 450)) // Set the frame size
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 450)) // Set initial size
        self.init(window: window)
        window.title = "Metal Shader: <default>"  // Set the default title

        // Call the setup method immediately after initialization
        setupWindowProperties()
        setupObservers()
    }

    private func setupObservers() {
        viewModel = (NSApp.delegate as? AppDelegate)?.viewModel

        // add a listener to the model's selectedFile attribute
        // if it changes, run the closure
        viewModel?.$title.sink { [weak self] (newTitle: String?) in

            // DispatchQueue.main.async may not be necessary, but the window
            // title may only be updated by the main thread.
            DispatchQueue.main.async {
                self?.window?.title = "\(newTitle ?? "<no file>")"
            }
        }
        .store(in: &cancellables)
        // stores in cancellables so it gets cleaned up when the controller is torn
        // down.  This doesn't matter here, but in a more dynamic class, it would.
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }

    private func setupWindowProperties() {
        window?.delegate = self
        loadWindowFrame()
    }

    private func loadWindowFrame() {
        if let frameString = UserDefaults.standard.string(forKey: "LastWindowFrame") {
            let frame = NSRectFromString(frameString)
            window?.setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = window {
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: "LastWindowFrame")
        }
    }

}
