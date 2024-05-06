//
//  UniformControlViewModel.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation

class UniformControlViewModel: ObservableObject {
    @Published var uniformVariables: [UniformVariable]

    init(variables: [UniformVariable]) {
        self.uniformVariables = variables
    }

    func updateValue(index: Int, valueIndex: Int, newValue: Float) {
        guard newValue >= uniformVariables[index].range.min &&
              newValue <= uniformVariables[index].range.max else { return }
        uniformVariables[index].values[valueIndex] = newValue
    }

    func getCurrentValues() -> [UniformVariable] {
        return uniformVariables
    }
}
