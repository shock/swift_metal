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
            if viewModel.uniformVariables.count > 0 {
                HStack {
                    // since lazy doesn't establish geometry we have to establish it with one non-lazy view first
                    UniformControlView(viewModel: viewModel, variableIndex: 0)
                    LazyHStack {
                        ForEach(1..<viewModel.uniformVariables.count, id: \.self) { index in
                            if index < viewModel.uniformVariables.count {
                                UniformControlView(viewModel: viewModel, variableIndex: index)
                            } else {
                                Text("Shouldn't be here")
                            }
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .padding()

    }
}
