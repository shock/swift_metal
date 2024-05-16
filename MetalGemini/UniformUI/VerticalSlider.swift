//
//  VerticalSlider.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/6/24.
//

import Foundation
import SwiftUI
import EventKit // Ensure this is correctly imported if necessary for custom scroll handling

let DoubleClickTime = 0.25

struct VerticalSlider: View {
    @EnvironmentObject var keyboardHandler: GlobalKeyboardEventHandler
    @Environment(\.undoManager) private var undoManager
    @Binding var value: Float
    var range: ClosedRange<Float>
    @State var lastValue: Float = 0
    @StateObject var sliderUndoManager = ValueUndoWrapper<Float>(initialValue: 0, undoManager: nil)
    @State var lastClickTime = Date()
    @State var secondClick = false
    @State var clickDebouncer = Debouncer(delay: DoubleClickTime, queueLabel: "net.wdoughty.metaltoy.uniclick")
    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {

        VStack {
            if isEditing {
                TextField("", text: $textValue, onCommit: commitText)
                    .background(Color.gray.opacity(0.5))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onAppear {
                        textValue = String(format: "%.4f", value)
                        isTextFieldFocused = true
                    }
                    .onDisappear() {
                        isTextFieldFocused = false
                    }
                    .focusable()
                    .focused($isTextFieldFocused)
                    .onChange(of: isTextFieldFocused) {
                        if isTextFieldFocused {
                            keyboardHandler.suspendHandling()
                        }
                    }
                    .fixedSize()
                    .onKeyPress(action: { keyPress in
                        if keyPress.key.character == "\u{1B}" { // escape key
                            isTextFieldFocused = false // Ensure focus is moved away when committing
                            keyboardHandler.resumeHandling()
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
                        let newValue = value - Float(adjustment) * (range.upperBound - range.lowerBound)
                        value = newValue.clamped(to: range)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Make ScrollableArea cover the entire ZStack

                }
                .cornerRadius(2)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if gesture.translation.height == 0 { // click/tap - no drag
                            lastValue = value // record the value before actual drag movement, for undo later
                            if Date().timeIntervalSince(lastClickTime) < DoubleClickTime { // double click/tap occurred
                                clickDebouncer.cancelPending() // cancel pending single-click action
                                value = (range.upperBound - range.lowerBound) / 2 + range.lowerBound // set value to midway point
                                secondClick = true
                            } else {
                                secondClick = false
                            }
                            lastClickTime = Date() // start the double click timer
                        } else {
                            // we're dragging, not clicking
                            clickDebouncer.cancelPending()
                            incrementValue(change: gesture.translation.height, in: geometry.size.height)
                        }
                    }
                    .onEnded { gesture in  // user has let up on mouse button or touch screen
                        // we only care about clicks in this case, not drags
                        if gesture.translation.height == 0 { // gesture was a click/tap - no drag
                            if !secondClick {
                                if Date().timeIntervalSince(lastClickTime) < DoubleClickTime {
                                    clickDebouncer.debounce { // schedule single click action
                                        DispatchQueue.main.async {
                                            self.updateValue(from: gesture.location.y, in: geometry.size.height)
                                        }
                                    }
                                } else {
                                    // update right away since the double-click timer has elapsed
                                    self.updateValue(from: gesture.location.y, in: geometry.size.height)
                                }
                            }
                        }
                    }
                )
            }
            .frame(width: 40) // Control the width of the slider
        }
        .clipped()
        .onAppear {
            sliderUndoManager.undoManager = undoManager
        }
        .onChange(of: sliderUndoManager.valueUpdated) {
            if sliderUndoManager.valueUpdated {
                value = sliderUndoManager.getValue()
            }
        }
        .onChange(of: value) {
            sliderUndoManager.setValue(value)
        }

    }

    private func commitText() {
        lastValue = value
        if let newValue = Float(textValue), range.contains(newValue) {
            value = newValue
        }
        isTextFieldFocused = false // Ensure focus is moved away when committing
        keyboardHandler.resumeHandling()
        isEditing = false
    }

    private func incrementValue(change yDelta: CGFloat, in height: CGFloat ) {
        let lastYpos = Float(height) - Float(lastValue - range.lowerBound) / (range.upperBound - range.lowerBound) * Float(height)
        let newYpos = CGFloat(lastYpos) + yDelta
        updateValue(from: newYpos, in: height)
    }

    private func updateValue(from yPos: CGFloat, in height: CGFloat) {
        let sliderValue = Float(height - yPos) / Float(height) * (range.upperBound - range.lowerBound) + range.lowerBound
        let newValue = sliderValue.clamped(to: range)
        value = newValue
    }

}
