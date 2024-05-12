//
//  UniformControlView.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI

struct UniformControlView: View {
    @Binding var uVar: UniformVariable
    let viewModel: UniformManager

    var body: some View {
        VStack {
            Spacer()
            switch uVar.style {
            case .vSlider:
                VStack {
                    HStack {
                        ForEach(0..<uVar.values.count, id: \.self) { valueIndex in
                            VerticalSlider(value: Binding(
                                get: { Double(uVar.values[valueIndex]) },
                                set: { newValue in
                                    uVar.values[valueIndex] = Float(newValue)
                                    viewModel.valueUpdated(name: uVar.name, valueIndex: valueIndex, value: Float(newValue))
                                }),
                                           range: Double(uVar.range.min)...Double(uVar.range.max)
                            )
                            .frame(height: 300) // Set the height of the custom slider
                        }
                    }
                    Text(uVar.name)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .border(Color.gray, width: 1)
            case .toggle:
                VStack {
                    ToggleButton(value: Binding(
                        get: { Double(uVar.values[0]) },
                        set: { newValue in
                            uVar.values[0] = Float(newValue)
                            viewModel.valueUpdated(name: uVar.name, valueIndex: 0, value: Float(newValue))
                        }),
                                 range: Double(uVar.range.min)...Double(uVar.range.max)
                    )
                    .frame(height: 40)
                    Text(uVar.name)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .border(Color.gray, width: 1)
            }
        }
    }
}
