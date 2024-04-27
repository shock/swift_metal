//
//  FileMonitor.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/27/24.
//

import Foundation

class FileMonitor {
    private var filesToMonitor: [URL]!
    private var fileDescriptors: [Int32] = []
    private var fileMonitorSources: [DispatchSourceFileSystemObject] = []

    init() {}

    func monitorShaderFiles(_ filesToMonitor: [URL], using closure: @escaping () -> Void) {
        self.filesToMonitor = filesToMonitor
        for fileDescriptor in fileDescriptors {
            if fileDescriptor != -1 {
                close(fileDescriptor)
            }
        }
        fileDescriptors.removeAll()

        for fileURL in filesToMonitor {
            let fileDescriptor = open(fileURL.path, O_EVTONLY)
            if fileDescriptor == -1 {
                print("Unable to open file: \(fileURL)")
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
                closure()
            }
            fileMonitorSource.resume()
            fileMonitorSources.append(fileMonitorSource)
        }
    }

    deinit {
        for fileDescriptor in fileDescriptors {
            if fileDescriptor != -1 {
                close(fileDescriptor)
            }
        }
        fileDescriptors.removeAll()
        
        for fileMonitorSource in fileMonitorSources {
            fileMonitorSource.cancel()
        }
        fileMonitorSources.removeAll()
    }

}
