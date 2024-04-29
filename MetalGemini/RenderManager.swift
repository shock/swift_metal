//
//  RenderDataModel.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/28/24.
//

import Foundation
import Cocoa
import SwiftOSC

class RenderManager: ObservableObject {
    @Published var frameCount: UInt32 = 0
    @Published var lastFrame: UInt32 = 0
    @Published var fps: Double = 0
    @Published var lastTime: TimeInterval = Date().timeIntervalSince1970
    @Published var selectedShaderURL: URL? = nil
    @Published var title: String? = nil
    @Published var shaderError: String? = nil

    public private(set) var size: CGSize = CGSize(width:0,height:0)
    private var mtkVC: MetalView.Coordinator?
    public private(set) var startDate = Date()
    private var uniformManager = UniformManager()
    private var shaderManager = ShaderManager()
    private var pauseTime = Date()
    private var fileMonitor = FileMonitor()
    var loadingSemaphore = DispatchSemaphore(value: 1) // Allows 1 concurrent access

    init() {
    }

    var metalDevice: MTLDevice? {
        get {
            return mtkVC?.metalDevice
        }
    }

    func uniformBuffer() throws -> MTLBuffer? {
        return try uniformManager.getBuffer()
    }

    func setViewSize(_ size: CGSize) {
        self.size.width = size.width
        self.size.height = size.height
        uniformManager.setUniformTuple("u_resolution", values: [Float(size.width), Float(size.height)], suppressSave: true)
    }

    func setCoordinator(_ mtkVC: MetalView.Coordinator ) {
        self.mtkVC = mtkVC
    }

    var vsyncOn: Bool = true {
        didSet {
            print("RenderManager: vsyncOn: didSet( \(self.vsyncOn) )")
            self.mtkVC?.updateVSyncState(self.vsyncOn)
            NotificationCenter.default.post(name: .vsyncStatusDidChange, object: nil, userInfo: ["enabled": vsyncOn])
        }
    }

    private var renderingWasPaused = true
    var renderingPaused: Bool = false {
        didSet {
            print("RenderManager: renderingPaused: didSet( \(self.renderingPaused) )")
            if renderingPaused {
                pauseTime = Date()
                mtkVC?.stopRendering()
            } else {
                startDate += Date().timeIntervalSince(pauseTime)
                mtkVC?.startRendering()
            }
            updateTitle()
        }
    }

    func updateTitle() {
        let file = "\(selectedShaderURL?.lastPathComponent ?? "<no file>")"
        let size = String(format: "%.0fx%.0f", size.width, size.height)
        var fps = String(format: "FPS: %.0f", fps)
        if renderingPaused {
            fps = "<PAUSED>"
        } else {
            pauseTime = Date()
        }
        let elapsedTime = pauseTime.timeIntervalSince(startDate);
        let avgFPS = Double(frameCount) / Date().timeIntervalSince(startDate)
        let avgStr = String(format: "FPS: %.0f", avgFPS)
        title = "\(file) - \(size) - \(fps) - \(elapsedTime.formattedMMSS()) - AVG: \(avgStr)"
    }

    func resetFrame() {
        print("RenderManager: resetFrame()")
        DispatchQueue.main.async {
            self.startDate = Date()
            self.pauseTime = Date()
            self.frameCount = 0
            self.lastFrame = 0
            self.fps = 0
            self.lastTime = Date().timeIntervalSince1970
            self.updateTitle()
        }
    }

    func monitorShaderFiles(_ filesToMonitor: [URL]) {
        fileMonitor = FileMonitor()
        fileMonitor.monitorShaderFiles(filesToMonitor) {
            Task {
                await self.reloadShaderFile()
            }
        }
    }

    func openFile() {
        print("RenderManager: openFile() on thread \(Thread.current)")
        renderingWasPaused = renderingPaused
        renderingPaused = true
        Task {
            let fileDialog = await FileDialog()
            do {
                guard let url = await fileDialog.openDialog() else {
                    await MainActor.run {
                        self.renderingPaused = self.renderingWasPaused
                    }
                    return
                }
                await self.loadShaderFile(url)
                await MainActor.run {
                    self.renderingPaused = self.renderingWasPaused
                }
            }
        }
    }

    @MainActor
    func loadShaderFile(_ fileURL: URL?) async {
        print("RenderManager: loadShaderFile()")
        guard let selectedURL = fileURL else {
            print("Unable to set file: \(String(describing: fileURL))")
            return
        }
        shaderError = nil
        selectedShaderURL = selectedURL
        reloadShaderFile()
    }

    @MainActor
    func reloadShaderFile() {
        loadingSemaphore.wait()
        defer { loadingSemaphore.signal() }
        print("RenderManager: reloadShaderFile()")
        guard let mtkVC = mtkVC else { return }
        guard let selectedURL = selectedShaderURL else { return }

        self.shaderError = nil

        if shaderManager.loadShader(fileURL: selectedURL) {
            shaderError = shaderError ?? uniformManager.setupUniformsFromShader(metalDevice: metalDevice!, srcURL: selectedURL, shaderSource: shaderManager.rawShaderSource!)
            shaderError = shaderError ?? mtkVC.loadShader(metallibURL: shaderManager.metallibURL)
        } else {
            shaderError = shaderManager.errorMessage
        }

        self.resetFrame()
//        renderingPaused = false
        // monitor files even if there's an error, so if the file is corrected, we'll reload it
        monitorShaderFiles(shaderManager.filesToMonitor)
    }

    func rewind() {
        startDate += 1
    }

    func fforward() {
        startDate -= 1
    }
}

extension RenderManager: KeyboardViewDelegate {
    func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {
        //        if event.isARepeat { return }

        let keyCode = event.keyCode
        switch keyCode {
        case 49:  // Space bar
            break
        case 125: // Down arrow
            resetFrame()
        case 126: // Up arrow
            renderingPaused.toggle()
        case 123: // Left arrow
            rewind()
        case 124: // Right arrow
            fforward()
        default:
            break // Do nothing for other key codes
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var modifiers = ""
        if flags.contains(.shift) { modifiers += "Shift " }
        if flags.contains(.control) { modifiers += "Control " }
        if flags.contains(.option) { modifiers += "Option " }
        if flags.contains(.command) { modifiers += "Command " }
        if flags.contains(.capsLock) { modifiers += "Capslock " }
        if flags.contains(.function) { modifiers += "Function " }
        print("Current modifiers: \(modifiers)")

    }

    func shutDown() {
        renderingPaused = true
        mtkVC?.stopRendering()
    }
}

extension RenderManager: OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage) {
        self.uniformManager.handleOSCMessage(message: message)
    }
}
