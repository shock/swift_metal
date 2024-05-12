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
    @State var secondClick = false
    @State var clickDebouncer = Debouncer(delay: 0.25, queueLabel: "net.wdoughty.metaltoy.uniclick")
    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {

        VStack {
            if isEditing {
                TextField("", text: $textValue, onCommit: {
                    if let newValue = Double(textValue), range.contains(newValue) {
                        value = newValue
                    }
                    isTextFieldFocused = false // Ensure focus is moved away when committing
                    isEditing = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                //                .keyboardType(.decimalPad)
                .onAppear {
                    textValue = String(format: "%.3f", value)
                    isTextFieldFocused = true
                }
                .onDisappear() {
                    isTextFieldFocused = false
                }
//                    .frame(width: geometry.size.width)
                .focusable()
                .focused($isTextFieldFocused)
                .onKeyPress(action: { keyPress in
                    if keyPress.key.character == "\u{1B}" { // escape key
                        isTextFieldFocused = false // Ensure focus is moved away when committing
                        isEditing = false
                        return .handled
                    }
                    return .ignored
                })
            } else {
                Text(String(format: "%.3f", value))
                    .fixedSize()
                    .onTapGesture {
                        isEditing = true
                    }
            }
                
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
                                secondClick = true
                            } else {
                                secondClick = false
                            }
                        } else {
                            clickDebouncer.cancelPending()
                            incrementValue(change: gesture.translation.height, in: geometry.size.height)
                        }
                    }
                    .onEnded { gesture in
                        if gesture.translation.height == 0 { // click/tap - no drag
                            if !secondClick {
                                if Date().timeIntervalSince(lastClickTime) < 0.25 {
                                    clickDebouncer.debounce {
                                        DispatchQueue.main.async {
                                            self.updateValue(from: gesture.location.y, in: geometry.size.height)
                                            lastValue = value
                                        }
                                    }
                                } else {
                                    self.updateValue(from: gesture.location.y, in: geometry.size.height)
                                }
                            }
                            lastClickTime = Date()
                        } else {
                            // commit Undo for drag action here
                        }
                    }
                )
            }
            .frame(width: 40) // Control the width of the slider
        }
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
