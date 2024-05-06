//
//  UniformControlView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI

struct UniformControlView: View {
    @ObservedObject var viewModel: UniformManager
    let variableIndex: Int
    
    var body: some View {
        VStack {
            HStack {
                ForEach(0..<viewModel.uniformVariables[variableIndex].values.count, id: \.self) { valueIndex in
                    VStack {
                        Text(String(format: "%.2f", viewModel.uniformVariables[variableIndex].values[valueIndex]))
                                                .fixedSize()
                        VerticalSlider(value: Binding(
                            get: { Double(viewModel.uniformVariables[variableIndex].values[valueIndex]) },
                            set: { newValue in
                                viewModel.updateValue(index: variableIndex, valueIndex: valueIndex, newValue: Float(newValue))
                            }),
                            range: Double(viewModel.uniformVariables[variableIndex].range.min)...Double(viewModel.uniformVariables[variableIndex].range.max)
                        )
                        .frame(height: 300) // Set the height of the custom slider
                    }
                }
            }
            Text(viewModel.uniformVariables[variableIndex].name)
        }
        .padding()
        .border(Color.gray, width: 1)
    }
}
