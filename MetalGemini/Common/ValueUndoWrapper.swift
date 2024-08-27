//
//  ValueUndoWrapper.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/15/24.
//

import Foundation

/// A class to manage a generic value with undo capability in a SwiftUI application.
/// Enables values that aren't attributes of a class to be wrapped in a class for use with
/// UndoManager.registerUndo(withTarget:)
class ValueUndoWrapper<Value: Equatable>: ObservableObject {

    /// Indicates if the value was recently updated, published to allow SwiftUI to react to changes.
    @Published var valueUpdated: Bool = false

    /// The current value.
    private var value: Value

    /// The value prior to the current value, used for undo operations.
    private var lastValue: Value

    /// Optional undo manager to handle undo operations.
    var undoManager: UndoManager?

    /// Initializes a new manager with a specified initial value and an optional undo manager.
    /// - Parameters:
    ///   - initialValue: The initial value.
    ///   - undoManager: An optional UndoManager to register undo operations.
    init(initialValue: Value, undoManager: UndoManager? = nil) {
        self.value = initialValue
        self.lastValue = initialValue // Initialize lastValue with initialValue
        self.undoManager = undoManager
    }

    /// Commits a potential undo operation when the value changes.
    /// - Parameters:
    ///   - newValue: The new value to commit.
    ///   - lastValue: The last value before the change, default is current value.
    ///   - msg: Message for undo operation
    func commitUndo(_ newValue: Value, lastValue: Value? = nil, msg: String = "Change Value") {
        let lastValue = lastValue ?? self.value
        undoManager?.registerUndo(withTarget: self, handler: { (target) in
            target.commitUndo(lastValue, msg: msg)
            target.valueUpdated = true // notify the View that the value has changed
        })
        undoManager?.setActionName(msg)
        self.lastValue = self.value
        self.value = newValue
    }

    /// Returns the current value and resets the `valueUpdated` flag. Used to consume an undo / redo
    /// value change.
    /// - Returns: The current value.
    func getValue() -> Value {
        valueUpdated = false
        return value
    }

    /// Sets the current value without registering an undo operation.  Used to keep wrapper in sync
    /// with the wrapped value.
    /// - Parameter newValue: The new value.
    func setValue(_ newValue: Value) {
        value = newValue
    }
}
