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
    @ObservedObject var renderMgr: RenderManager

    var body: some View {
        VStack{
            if renderMgr.shaderError == nil {
                VStack{
                    MetalView(renderMgr: renderMgr)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.appMenu, appDelegate.mainMenu) // Add menu to the environment
                    // Button to start rendering
                }
            } else {
                ScrollView {
                    VStack {
                        Text(renderMgr.shaderError!)
//                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .font(.system(size: 13, weight: .medium, design: .monospaced)) // Using a monospaced medium font
                            .multilineTextAlignment(.leading) // Set text alignment to leading (left-justified)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .onChange(of: renderMgr.frameCount) {
            doFrame()
        }
//        .onChange(of: selectedURL) {
//            handleFileChange()
//        }
//        .onChange(of: renderMgr.openFileDialog) {
//            if renderMgr.openFileDialog { fileDialog() }
//            renderMgr.openFileDialog = false
//        }
    }

//    func fileDialog() {
//        let fileDialog = FileDialog(selectedURL: $selectedURL)
//        fileDialog.openDialog()
//    }
//    func handleFileChange() {
//        Task {
//            await renderMgr.loadShaderFile(selectedURL)
//        }
//    }

    func doFrame() {
        let now = Date().timeIntervalSince1970
        let delta = now - renderMgr.lastTime
        if( delta ) > 1 {
            renderMgr.lastTime = now
            if( renderMgr.frameCount < renderMgr.lastFrame ) {
                renderMgr.lastFrame = renderMgr.frameCount
            }
            let frames = renderMgr.frameCount - renderMgr.lastFrame
            renderMgr.lastFrame = renderMgr.frameCount
            renderMgr.fps = Double(frames) / delta
            renderMgr.updateTitle()
        }
     }

}

#Preview {
    ContentView(renderMgr: RenderManager())
}
