//
//  VerticalSlider.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI
import EventKit // Ensure this is correctly imported if necessary for custom scroll handling

struct VerticalSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Rectangle() // Slider Track
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 40)

                Rectangle() // Slider Thumb
                    .fill(Color.init(red: 0, green: 0.55, blue: 1.0).opacity(0.7))
                    .frame(width: 40, height: max(0,CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * geometry.size.height))

                ScrollableArea { deltaY in
                    let adjustment = deltaY / 7000 // Adjust this scale factor as necessary
                    let newValue = value - adjustment * (range.upperBound - range.lowerBound)
                    value = newValue.clamped(to: range)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Make ScrollableArea cover the entire ZStack

            }
            .cornerRadius(2)
            .gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
                print("gesture.startLocation.y \(gesture.startLocation.y)")
                print("gesture.location.y \(gesture.location.y)")
                updateValue(from: gesture.location.y, in: geometry.size.height)
            })
            .onTapGesture(count: 2) { location in
                value = (range.upperBound - range.lowerBound) / 2 + range.lowerBound
            }
            .onTapGesture { location in
                updateValue(from: location.y, in: geometry.size.height)
            }
        }
        .frame(width: 40) // Control the width of the slider
        .clipped()
    }

    private func updateValue(from yPos: CGFloat, in height: CGFloat) {
        let sliderValue = Double(height - yPos) / Double(height) * (range.upperBound - range.lowerBound) + range.lowerBound
        value = sliderValue.clamped(to: range)
    }

}
