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
    @Published private(set) var shaderError: String? = nil

    public private(set) var size: CGSize = CGSize(width:0,height:0)
    private var mtkVC: MetalView.Coordinator?
    public private(set) var startDate = Date()
    private var uniformManager: UniformManager!
    private var textureManager: TextureManager!
    private var shaderManager: ShaderManager!
    private var pauseTime = Date()
    private var fileMonitor = FileMonitor()
    public private(set) var renderSync = MutexRunner()
    private(set) var resourceMgr: MetalResourceManager!

    init() {
        self.shaderManager = ShaderManager()
        self.uniformManager = UniformManager(projectDirDelegate: shaderManager)
        self.textureManager = TextureManager()
        self.resourceMgr = MetalResourceManager(projectDirDelegate: shaderManager)
    }

    var metalDevice: MTLDevice? {
        get {
            return mtkVC?.metalDevice
        }
    }

    func uniformBuffer() throws -> MTLBuffer? {
        do {
            let buffer = try uniformManager.getBuffer()
            return buffer
        } catch {
            shaderError = "failed to get uniform buffer: \(error.localizedDescription)"
            throw error
        }
    }

    func setViewSize(_ size: CGSize) {
        self.size.width = size.width
        self.size.height = size.height
        uniformManager.setUniformTuple("u_resolution", values: [Float(size.width), Float(size.height)], suppressSave: true)
    }

    func setViewCoordinator(_ mtkVC: MetalView.Coordinator ) {
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
        await reloadShaderFile()
    }

    @MainActor
    func reloadShaderFile() async {
        await renderSync.run {
            print("\n\nRenderManager: reloadShaderFile()")
            guard let mtkVC = self.mtkVC else { return }
            guard let selectedURL = self.selectedShaderURL else { return }
            let shaderManager = self.shaderManager!
            let uniformManager = self.uniformManager!
            let textureManager = self.textureManager!
            let resourceMgr = self.resourceMgr!
            guard let metalDevice = self.metalDevice else {
                self.shaderError = "CRITICAL ERROR: metalDevice is nil"
                return
            }

            mtkVC.stopRendering() // this must be here for reloading with vsync off!
            var shaderError: String? = nil

            self.shaderError = "Loading '\(selectedURL.absoluteString)'"

            if shaderManager.loadShader(fileURL: selectedURL) {
                shaderError = shaderError ?? uniformManager.setupUniformsFromShader(metalDevice: metalDevice, srcURL: selectedURL, shaderSource: shaderManager.rawShaderSource!)
                if shaderError == nil {
                    let textureURLs = textureManager.loadTexturesFromShader(srcURL: selectedURL, shaderSource: shaderManager.rawShaderSource!)
                    shaderError = resourceMgr.loadTextures(textureURLs: textureURLs)
                    if shaderError == nil {
                        shaderError = await mtkVC.loadShader(metallibURL: shaderManager.metallibURL)
                        resourceMgr.swapNonBufferResources()
                    }
                }
            } else {
                shaderError = shaderManager.errorMessage
            }
            
            self.shaderError = shaderError

            self.resetFrame()
            //        renderingPaused = false
            // monitor files even if there's an error, so if the file is corrected, we'll reload it
            self.monitorShaderFiles(shaderManager.filesToMonitor)
            
            if shaderError != nil { return }

            if !self.vsyncOn {
                mtkVC.startRendering() // renable offline rendering if vsync is false
            }

        }
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
