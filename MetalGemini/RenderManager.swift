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
    @Published var openFileDialog = false
    @Published var title: String? = nil
    @Published var shaderError: String? = nil

    public private(set) var size: CGSize = CGSize(width:0,height:0)
    private var mtkVC: MetalView.Coordinator?
    public private(set) var startDate = Date()
    var uniformManager = UniformManager()
    private var shaderManager = ShaderManager()
    private var pauseTime = Date()
    private var fileMonitor = FileMonitor()

    init() {
    }

    var metalDevice: MTLDevice? {
        get {
            return mtkVC?.metalDevice
        }
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
            self.mtkVC?.updateVSyncState(self.vsyncOn)
            NotificationCenter.default.post(name: .vsyncStatusDidChange, object: nil, userInfo: ["enabled": vsyncOn])
        }
    }

    var renderingPaused: Bool = false {
        didSet {
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
        DispatchQueue.main.async {
            self.startDate = Date()
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
            self.reloadShaderFile()
        }
    }

    func loadShaderFile(_ fileURL: URL?) {
        guard let selectedURL = fileURL else {
            print("Unable to set file: \(String(describing: fileURL))")
            return
        }

        shaderError = nil
        selectedShaderURL = selectedURL
        reloadShaderFile()
    }

    func reloadShaderFile() {
        guard let mtkVC = mtkVC else { return }
        guard let selectedURL = selectedShaderURL else { return }

        self.shaderError = nil
        self.resetFrame()

        if shaderManager.loadShader(fileURL: selectedURL) {
            mtkVC.loadShader(metallibURL: shaderManager.metallibURL)
            shaderError = uniformManager.setupUniformsFromShader(metalDevice: metalDevice!, srcURL: selectedURL, shaderSource: shaderManager.rawShaderSource!)
        } else {
            shaderError = shaderManager.errorMessage
        }

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
