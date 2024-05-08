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
        // shouldn't have to do this, but there is a race condition when reloading that I can't solve despite trying.
        // basically the uniformVariables is getting switched in the middle of these nested view calls, and the
        // indices are from the older shader's uniforms, but the uniformVariables is already set for the new shader,
        // causing out of bounds errors.
        if variableIndex < viewModel.uniformVariables.count {
            VStack {
                HStack {
                    ForEach(0..<viewModel.uniformVariables[variableIndex].values.count, id: \.self) { valueIndex in
                        VStack {
                            Text(String(format: "%.2f", viewModel.uniformVariables[variableIndex].values[valueIndex]))
                                .fixedSize()
                            VerticalSlider(value: Binding(
                                get: {
                                    var value:Double = 0
                                    // shouldn't need to be doing this
                                    if variableIndex < viewModel.uniformVariables.count {
                                        // shouldn't need to be doing this
                                        if valueIndex < viewModel.uniformVariables[variableIndex].values.count {
                                            value = Double(viewModel.uniformVariables[variableIndex].values[valueIndex])
                                        } else {
                                            value = 0
                                            print("valueIndex \(valueIndex) out of bounds for \(viewModel.uniformVariables[variableIndex])")
                                        }
                                    } else {
                                        value = 0
                                        print("variableIndex \(variableIndex) out of bounds for \(viewModel.uniformVariables)")
                                    }
                                    return value
                                },
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
            .background(Color.black.opacity(0.5))
            .border(Color.gray, width: 1)
        }
    }
}
