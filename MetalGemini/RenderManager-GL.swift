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
    @Published var selectedFile: URL? = nil
    @Published var openFileDialog = false
    @Published var title: String? = nil
    @Published var shaderError: String? = nil

    private var reloadShaders = false
    public private(set) var size: CGSize = CGSize(width:0,height:0)
    private var fileDescriptors: [Int32] = []
    private var shaderURLs: [URL] = []
    private var fileMonitorSources: [DispatchSourceFileSystemObject] = []
    private var mtkVC: MetalView.Coordinator?
    public private(set) var startDate = Date()
    var uniformManager = UniformManager()
    private var shaderManager = ShaderManager()

    private var pauseTime = Date()

    init() {
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
        let file = "\(selectedFile?.lastPathComponent ?? "<no file>")"
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
        shaderURLs = filesToMonitor
        for fileDescriptor in fileDescriptors {
            if fileDescriptor != -1 {
                close(fileDescriptor)
            }
        }
        fileDescriptors.removeAll()

        for shaderURL in shaderURLs {
            let fileDescriptor = open(shaderURL.path, O_EVTONLY)
            if fileDescriptor == -1 {
                print("Unable to open file: \(shaderURL)")
                return
            }
            fileDescriptors.append(fileDescriptor)
        }

        for fileMonitorSource in fileMonitorSources {
            fileMonitorSource.cancel()
        }
        fileMonitorSources.removeAll()

        for fileDescriptor in fileDescriptors {
            let fileMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: DispatchQueue.main)
            fileMonitorSource.setEventHandler {
                self.reloadShaderFile()
            }
            fileMonitorSource.resume()
            fileMonitorSources.append(fileMonitorSource)
        }
    }

    func loadShaderFile(_ fileURL: URL?) {
        guard let selectedURL = fileURL else {
            print("Unable to set file: \(String(describing: fileURL))")
            return
        }

        shaderError = nil
        selectedFile = selectedURL
        reloadShaders = true
        reloadShaderFile()
    }

    func reloadShaderFile() {
        guard let coordinator = mtkVC else { return }
        guard let selectedFile = selectedFile else { return }

        self.shaderError = nil

        if shaderManager.loadShader(fileURL: selectedFile) {
            coordinator.metallibURL = shaderManager.metallibURL
            coordinator.reloadShaders()
            self.reloadShaders = false
            shaderError = uniformManager.setupUniformsFromShader(metalDevice: coordinator.metalDevice!, srcURL: selectedFile, shaderSource: shaderManager.rawShaderSource!)
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
        reloadShaders = false
    }
}

extension RenderManager: OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage) {
        self.uniformManager.handleOSCMessage(message: message)
    }
}