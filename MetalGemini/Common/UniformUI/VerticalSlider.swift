//
//  VerticalSlider.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI

struct VerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle() // Slider Track
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40)

                Rectangle() // Slider Thumb
                    .fill(Color.init(red: 0, green: 0.6, blue: 0.85).opacity(0.7))
                    .frame(width: 40, height: max(0,CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * geometry.size.height))

                Rectangle() // Invisible Interactive Layer
                    .fill(Color.clear)
                    .contentShape(Rectangle()) // Ensure the entire area is interactive
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let y = gesture.location.y
                // Convert y position to a value in the range
                let sliderValue = Double(geometry.size.height - y) / Double(geometry.size.height) * (range.upperBound - range.lowerBound) + range.lowerBound
                value = sliderValue.clamped(to: range)
//                print("Gesture y: \(y), Value: \(value)") // Debug output
            })
        }
        .frame(width: 40) // Control the width of the slider
        .clipped()
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
