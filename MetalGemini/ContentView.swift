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

struct ContentView: View {
    @State private var selectedURL: URL? = nil
    @Environment(\.appMenu) var appMenu // Property for holding menu reference
    @ObservedObject var model: RenderDataModel

    var body: some View {
        VStack{
            MetalView(model: model)
                .environment(\.appMenu, appDelegate.mainMenu) // Add menu to the environment
            Text(String(format: "FPS: %.2f", model.fps))
            .padding([.bottom],6)
        }
        .onChange(of: model.frameCount) {
            doFrame()
        }
        .onChange(of: selectedURL) {
            handleFileChange()
        }
        .onChange(of: model.openFileDialog) {
            if model.openFileDialog { fileDialog() }
            model.openFileDialog = false
        }
    }
    
    func fileDialog() {
        let fileDialog = FileDialog(selectedURL: $selectedURL)
        fileDialog.openDialog()
    }
    func handleFileChange() {
        model.loadShaderFile(selectedURL)
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
    ContentView(model: RenderDataModel())
}
