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
    @State var lastValue: Double = 0
    @State var lastClickTime = Date()
    @State var clickDebouncer = Debouncer(delay: 0.25, queueLabel: "net.wdoughty.metaltoy.uniclick")

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
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if gesture.translation.height == 0 { // click/tap - no drag
                        lastValue = value
                        if Date().timeIntervalSince(lastClickTime) < 0.25 { // double click/tap if less than 250 ms
                            clickDebouncer.cancelPending()
                            value = (range.upperBound - range.lowerBound) / 2 + range.lowerBound // set value to midway point
                        } else {
                            clickDebouncer.debounce {
                                DispatchQueue.main.async {
                                    self.updateValue(from: gesture.location.y, in: geometry.size.height)
                                    lastValue = value
                                }
                            }
                        }
                        lastClickTime = Date()
                    } else {
                        clickDebouncer.cancelPending()
                        incrementValue(change: gesture.translation.height, in: geometry.size.height)
                    }
                }
                .onEnded { gesture in
                    // commit Undo action here
                }
            )
        }
        .frame(width: 40) // Control the width of the slider
        .clipped()
    }

    private func incrementValue(change yDelta: CGFloat, in height: CGFloat ) {
        let lastYpos = Double(height) - Double(lastValue - range.lowerBound) / (range.upperBound - range.lowerBound) * height
        let newYpos = lastYpos + yDelta
        updateValue(from: newYpos, in: height)
    }

    private func updateValue(from yPos: CGFloat, in height: CGFloat) {
        let sliderValue = Double(height - yPos) / Double(height) * (range.upperBound - range.lowerBound) + range.lowerBound
        value = sliderValue.clamped(to: range)
    }

}
