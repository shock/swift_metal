//
//  UniformVariable.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation

struct UniformVariable {
    let name: String
    let type: String
    var values: [Float]
    let range: (min: Float, max: Float)
}
