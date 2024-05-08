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
    @Published var doOneFrame = false
    @Published var uniformOverlayVisible: Bool = false

    public private(set) var size: CGSize = CGSize(width:0,height:0)
    var mtkVC: MetalView.Coordinator?
    public private(set) var startDate = Date()
    var uniformManager: UniformManager!
    private var textureManager: TextureManager!
    private var shaderManager: ShaderManager!
    private var pauseTime = Date()
    private var fileMonitor = FileMonitor()
    public private(set) var renderSync = SerialRunner()
    private(set) var resourceMgr: MetalResourceManager!

    init() {
        self.shaderManager = ShaderManager()
        self.uniformManager = UniformManager(projectDirDelegate: shaderManager)
        self.textureManager = TextureManager()
        self.resourceMgr = MetalResourceManager(projectDirDelegate: shaderManager)
    }

    func setViewSize(_ size: CGSize) {
        self.size.width = size.width
        self.size.height = size.height
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

    func renderTime() -> TimeInterval {
        if renderingPaused {
            return pauseTime.timeIntervalSince(startDate)
        }
        return -startDate.timeIntervalSinceNow
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

    func updateFrame() {
        if renderingPaused { doOneFrame = true }
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

            mtkVC.stopRendering() // this must be here for reloading with vsync off!
            var shaderError: String? = nil

//            self.shaderError = "Loading '\(selectedURL.absoluteString)'"

            if shaderManager.loadShader(fileURL: selectedURL) {
                do {
                    let shaderSource = shaderManager.rawShaderSource!
                    let textureURLs = textureManager.loadTexturesFromShader(srcURL: selectedURL, shaderSource: shaderSource)


                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await uniformManager.setupUniformsFromShader(srcURL: selectedURL, shaderSource: shaderSource)
                        }
                        group.addTask {
                            try await resourceMgr.loadTextures(textureURLs: textureURLs)
                        }
                        group.addTask {
                            try await resourceMgr.setupPipelines(metallibURL: shaderManager.metallibURL)
                        }

                        try await group.waitForAll()
                    }
                    // Execute completion code after all concurrent group tasks have succeeded
                    resourceMgr.setUniformBuffer(uniformManager.getBuffer())
                    resourceMgr.createBuffers(numBuffers: MAX_RENDER_BUFFERS, size: self.size)
                    resourceMgr.swapCurrentResources()
                } catch {
                    shaderError = error.localizedDescription
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

    var lastMousePosition = CGPoint()
}

extension RenderManager: KeyboardEventsDelegate {
    func keyUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags) { }

    func flagsChangedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) { }

    func keyDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {
        //        if event.isARepeat { return }

        let keyCode = event.keyCode
        switch keyCode {
        case 49:  // Space bar
            break
        case 125: // Down arrow
            resetFrame()
            updateFrame()
        case 126: // Up arrow
            renderingPaused.toggle()
        case 123: // Left arrow
            rewind()
            updateFrame()
        case 124: // Right arrow
            fforward()
            updateFrame()
        default:
            break // Do nothing for other key codes
        }
    }

    func shutDown() {
        renderingPaused = true
        mtkVC?.stopRendering()
    }
}

extension RenderManager: MouseEventsDelegate {

    func getMouseDelta( event: NSEvent ) -> NSPoint {
        let x = event.locationInWindow.x - lastMousePosition.x
        let y = event.locationInWindow.y - lastMousePosition.y
        lastMousePosition.x = event.locationInWindow.x
        lastMousePosition.y = event.locationInWindow.y
        return NSPoint(x:x,y:y)
    }

    func mouseDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func mouseUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func mouseMovedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func mouseScrolledEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func rightMouseDownEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func rightMouseUpEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func mouseDraggedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {
//        let deltaP = getMouseDelta(event: event)
//        let delta = deltaP.y/300
//        uniformManager.incrementFloatUniform("o_distance", increment: Float(delta), min: -1, max: 1)
        updateFrame()
    }

    func rightMouseDraggedEvent(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func pinchGesture(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func rotateGesture(event: NSEvent, flags: NSEvent.ModifierFlags) {}

    func swipeGesture(event: NSEvent, flags: NSEvent.ModifierFlags) {}
}


extension RenderManager: OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage) {
        self.uniformManager.handleOSCMessage(message: message)
//        updateFrame()
    }
}
