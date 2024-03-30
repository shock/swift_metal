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
    @Published var shaderError: String? = nil
    @Published var title: String? = nil

    var size: CGSize = CGSize(width:0,height:0)
    var fileDescriptors: [Int32] = []
    var shaderURLs: [URL] = []
    var fileMonitorSources: [DispatchSourceFileSystemObject] = []

    func updateTitle() {
        let file = "\(selectedFile?.lastPathComponent ?? "<no file>")"
        let size = String(format: "%.0fx%.0f", size.width, size.height)
        title = "\(file) - \(size) - \(String(format: "%.1f FPS", fps))"
    }

    func resetFrame() {
        frameCount = 0
        lastFrame = 0
        fps = 0
        lastTime = Date().timeIntervalSince1970
        updateTitle()
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
