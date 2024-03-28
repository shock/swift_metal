//
//  ContentView.swift
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

import SwiftUI
import MetalKit

struct AppMenuKey: EnvironmentKey {
    static let defaultValue: NSMenu? = nil // Default value of nil
}

// Add an extension for your environment key:
extension EnvironmentValues {
    var appMenu: NSMenu? {
        get { self[AppMenuKey.self] }
        set { self[AppMenuKey.self] = newValue }
    }
}

class SharedDataModel: ObservableObject {
    @Published var frameCount: UInt32 = 0
    @Published var lastFrame: UInt32 = 0
    @Published var fps: Double = 0
    @Published var lastTime: TimeInterval = Date().timeIntervalSince1970
    @Published var selectedFile: URL? = nil
    @Published var reloadShaders = false

    func resetFrame() {
        frameCount = 0
        lastFrame = 0
        fps = 0
        lastTime = Date().timeIntervalSince1970
    }
}

struct ContentView: View {
    @State private var selectedURL: URL? = nil
    @Environment(\.appMenu) var appMenu // Property for holding menu reference
    @StateObject var model = SharedDataModel()
    @State var fileMonitorSource: DispatchSourceFileSystemObject?
    @State var fileDescriptor: Int32 = -1

    var body: some View {
        VStack{
            MetalView(model: model)
                .environment(\.appMenu, appDelegate.mainMenu) // Add menu to the environment
            Text("FPS: \(model.fps)")
            Text("Reload: \(model.reloadShaders)")
            Text("File: \(String(describing: model.selectedFile))")
            Button("Open File") {
                let fileDialog = FileDialog(selectedURL: $selectedURL)
                fileDialog.openDialog()
            }
            .padding([.bottom],6)
        }
        .onChange(of: model.frameCount) {
            doFrame()
        }
        .onChange(of: selectedURL) {
            handleFileChange()
        }
    }

    func handleFileChange() {
        guard let selectedURL = selectedURL else {
            print("Unable to set file: \(String(describing: selectedURL))")
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
        model.selectedFile = selectedURL
        fileMonitorSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: DispatchQueue.main)
        fileMonitorSource?.setEventHandler {
             model.reloadShaders = true
        }
        fileMonitorSource?.resume()
    }

    func doFrame() {
        let now = Date().timeIntervalSince1970
        let delta = now - model.lastTime
        if( delta ) > 1 {
            model.lastTime = now
            let frames = model.frameCount - model.lastFrame
            model.lastFrame = model.frameCount
            model.fps = Double(frames) / delta
        }
     }

}

#Preview {
    ContentView()
}
