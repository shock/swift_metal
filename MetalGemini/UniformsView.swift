//
//  UniformsView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/7/24.
//

import Foundation
import SwiftUI

struct UniformsView: View {
    @Environment(\.appMenu) var appMenu // Property for holding menu reference
    @ObservedObject var renderMgr: RenderManager

    var body: some View {
        VStack{
            ZStack{
                KeyboardMouseViewRepresentable( keyboardDelegate: renderMgr, mouseDelegate: renderMgr )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)  // Allows events to pass through
                    .zIndex(1)
                UniformOverlayUI(viewModel: renderMgr.uniformManager)
                    .frame(height: 300) // Configurable
                    .opacity(0.8)
                    .zIndex(2)
            }
        }
        .onAppear {
        }
        .onChange(of: renderMgr.frameCount) {
        }
    }

}

#Preview {
    UniformsView(renderMgr: RenderManager())
}

