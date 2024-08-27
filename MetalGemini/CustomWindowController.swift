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
    private var renderMgr: RenderManager?
    private var cancellables: Set<AnyCancellable> = []

    convenience init<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 450)) // Set the frame size
        let window = ClickThroughWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 450)) // Set initial size
        self.init(window: window)
        window.title = "Metal Shader: <default>"  // Set the default title

        renderMgr = (NSApp.delegate as? AppDelegate)?.renderMgr

        setupObservers()
        setupWindowProperties()
    }

    private func setupObservers() {

        // add a listener to the model's selectedFile attribute
        // if it changes, run the closure
        renderMgr?.$title.sink { [weak self] (newTitle: String?) in

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
        self.window?.delegate = self  // Ensure this controller is the delegate
    }

    private func setupWindowProperties() {
        window?.delegate = self
        loadWindowFrame()
        loadLastFileOpened()
        renderMgr?.renderingPaused = false
    }

    private func loadLastFileOpened() {
        if let fileURL = UserDefaults.standard.string(forKey: "LastFileOpened"),
           let renderMgr = renderMgr {
            Task {
                await renderMgr.loadShaderFile(URL(string:fileURL))
            }
        }
    }

    private func loadWindowFrame() {
        if let frameString = UserDefaults.standard.string(forKey: "LastWindowFrame") {
            let frame = NSRectFromString(frameString)
            window?.setFrame(frame, display: true)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Prevent the main window from closing with CMD-W
        if sender == self.window {
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if let window = window {
            let frameString = NSStringFromRect(window.frame)
            UserDefaults.standard.set(frameString, forKey: "LastWindowFrame")
        }
        if let renderMgr = renderMgr {
            renderMgr.shutDown()
            if let selectedShaderURL = renderMgr.selectedShaderURL {
                let path = selectedShaderURL.path(percentEncoded: false)
                UserDefaults.standard.set(path, forKey: "LastFileOpened")
            }
        }
        NSApplication.shared.terminate(self)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        print("Window will enter full-screen mode.")
        // Perform any necessary configurations before the window enters full-screen
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        print("Window has entered full-screen mode.")
        if let window = window {
            let size = window.frame.size
            if let renderMgr = renderMgr {
                renderMgr.mtkVC?.updateViewportSize(size)

            }
        }
        // Adjust any settings or perform actions after the window is in full-screen
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        print("Window will exit full-screen mode.")
        // Prepare your application for the window exiting full-screen
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        print("Window has exited full-screen mode.")
        // Restore any settings or clean up after exiting full-screen
    }

}
