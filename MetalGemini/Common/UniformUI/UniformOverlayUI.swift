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
            HStack {
                ForEach(0..<viewModel.uniformVariables.count, id: \.self) { index in
                    UniformControlView(viewModel: viewModel, variableIndex: index)
                }
            }
        }
        .background(Color.black.opacity(0.5))
        .padding()

    }
}
