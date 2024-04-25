//
//  RenderDataModel.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/28/24.
//

import Foundation
class RenderDataModel: ObservableObject {
    @Published var frameCount: UInt32 = 0
    @Published var lastFrame: UInt32 = 0
    @Published var fps: Double = 0
    @Published var lastTime: TimeInterval = Date().timeIntervalSince1970
    @Published var selectedFile: URL? = nil
    @Published var openFileDialog = false
    @Published var title: String? = nil
    @Published var shaderError: String? = nil

    var reloadShaders = false
    var vsyncOn = true
    var size: CGSize = CGSize(width:0,height:0)
    var fileDescriptors: [Int32] = []
    var shaderURLs: [URL] = []
    var fileMonitorSources: [DispatchSourceFileSystemObject] = []
    var coordinator: MetalView.Coordinator?

    func updateTitle() {
        let file = "\(selectedFile?.lastPathComponent ?? "<no file>")"
        let size = String(format: "%.0fx%.0f", size.width, size.height)
        title = "\(file) - \(size) - \(String(format: "%.1f FPS", fps))"
    }

    func resetFrame() {
        DispatchQueue.main.async {
            self.frameCount = 0
            self.lastFrame = 0
            self.fps = 0
            self.lastTime = Date().timeIntervalSince1970
            self.updateTitle()
        }
    }

    func monitorShaderFiles() {
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
                self.shaderError = nil
                self.reloadShaders = true
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

    }
}

extension RenderDataModel: KeyboardViewDelegate {
    func keyDownEvent(keyCode: UInt16) {
        // Handle the key event, update the model
        // For example, toggle vsync based on a specific key
        if keyCode == 49 { // Space bar
            vsyncOn.toggle()
            coordinator?.updateVSyncState(vsyncOn)
        }
    }
}
