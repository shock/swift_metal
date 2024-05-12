//
//  UniformOverlayUI.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI

struct UniformOverlayUI: View {
    @ObservedObject var viewModel: UniformManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if viewModel.activeUniforms.count > 0 {
                HStack {
                    // since lazy doesn't establish geometry we have to establish it with one non-lazy view first
                    UniformControlView(uVar: $viewModel.activeUniforms[0], viewModel: viewModel)
                    LazyHStack {
                        ForEach(1..<viewModel.activeUniforms.count, id: \.self) { index in
                            if index < viewModel.activeUniforms.count {
                                UniformControlView(uVar: $viewModel.activeUniforms[index], viewModel: viewModel)
                            } else {
                                Text("Shouldn't be here")
                            }
                        }
                    }
                }
                .padding(1)
            }
        }
        .background(Color.clear)
        .padding()

    }
}
