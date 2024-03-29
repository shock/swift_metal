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
    @Published var reloadShaders = false
    @Published var openFileDialog = false
    
    var fileDescriptor: Int32 = -1
    var fileMonitorSource: DispatchSourceFileSystemObject?

    func resetFrame() {
        frameCount = 0
        lastFrame = 0
        fps = 0
        lastTime = Date().timeIntervalSince1970
    }

    func loadShaderFile(_ fileURL: URL?) {
        guard let selectedURL = fileURL else {
            print("Unable to set file: \(String(describing: fileURL))")
            return
        }
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
        fileDescriptor = open(selectedURL.path, O_EVTONLY)
        if fileDescriptor == -1 {
            print("Unable to open file: \(selectedURL)")
            return
        }

        fileMonitorSource?.cancel()
        selectedFile = selectedURL
        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: DispatchQueue.main)
        fileMonitorSource?.setEventHandler {
            self.reloadShaders = true
        }
        fileMonitorSource?.resume()

    }
}
