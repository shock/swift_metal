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

let uniformData = [
    UniformVariable(name: "o_distance", values: [0.5], range: (min: 0.0, max: 1.0)),
    UniformVariable(name: "o_color", values: [0.2, 0.3, 0.4], range: (min: 0.0, max: 1.0))
]

let uniformViewModel = UniformControlViewModel(variables: uniformData)


struct ContentView: View {
    @State private var selectedURL: URL? = nil
    @Environment(\.appMenu) var appMenu // Property for holding menu reference
    @ObservedObject var renderMgr: RenderManager
    @State private var metalView: MetalView?

    var body: some View {
        VStack{
            if renderMgr.shaderError == nil {

                ZStack{
                    metalView?
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.appMenu, appDelegate.mainMenu) // Add menu to the environment
                        .zIndex(0)
                    KeyboardMouseViewRepresentable(
                        keyboardDelegate: renderMgr,
                        mouseDelegate: renderMgr
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)  // Allows events to pass through
                        .zIndex(1)
                    if renderMgr.uniformOverlayVisible {
                        UniformOverlayUI(viewModel: renderMgr.uniformManager)
                            .frame(height: 300) // Configurable
                            .opacity(0.9) // Assuming there's a toggle to show/hide
                            .zIndex(2)
                    }
                }
            } else {
                ScrollView {
                    VStack {
                        Text(renderMgr.shaderError!)
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
        .onAppear {
            // Only create MetalView if it hasn't been created yet
            if metalView == nil {
                metalView = MetalView(renderMgr: renderMgr)
            }
        }
        .onChange(of: renderMgr.frameCount) {
            doFrame()
        }
    }

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
