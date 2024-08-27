//
//  ToggleButton.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/8/24.
//

import Foundation
import SwiftUI

struct ToggleButton: View {
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle() // Slider Track
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 40)

                Rectangle() // Slider Thumb
                    .fill(Color.init(red: 0.75, green: 0.5, blue: 1.0).opacity(0.7))
                    .frame(width: 40, height: max(0, value * geometry.size.height))

                Rectangle() // Invisible Interactive Layer
                    .fill(Color.clear)
                    .contentShape(Rectangle()) // Ensure the entire area is interactive
            }
            .cornerRadius(6)
            .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                value = 1 - value
            })
        }
        .frame(width: 40) // Control the width of the slider    
        .clipped()
    }
}
