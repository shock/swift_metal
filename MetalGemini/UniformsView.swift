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
    @ObservedObject var viewModel: UniformManager

    var body: some View {
        VStack{
            ZStack{
                UniformOverlayUI(viewModel: viewModel)
                    .frame(height: 300) // Configurable
                    .opacity(0.8)
                    .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}
