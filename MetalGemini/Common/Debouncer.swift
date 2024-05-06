//
//  Debouncer.swift
//  MetalGemini
//
//  Created by Bill Doughty on 5/3/24.
//

import Foundation

class Debouncer {
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval
    
    /// Initializes a debouncer with a specified delay and an optional custom dispatch queue label.
    /// - Parameters:
    ///   - delay: The delay time interval for debouncing.
    ///   - queueLabel: An optional string to label the custom dispatch queue. If nil, the main queue is used.
    init(delay: TimeInterval, queueLabel: String? = nil) {
        self.delay = delay
        // Create a dispatch queue with the given label or use the main queue if no label is provided.
        if let label = queueLabel {
            self.queue = DispatchQueue(label: label)
        } else {
            self.queue = DispatchQueue.main
        }
    }
    
    /// Debounces a block of code, ensuring it is executed no more than once per the specified delay.
    /// The closure should capture `self` weakly if used inside to avoid retain cycles.
    /// - Parameter block: The closure to execute after the delay.
    func debounce(_ block: @escaping () -> Void) {
        // Cancel the current work item if it exists.
        workItem?.cancel()
        
        // Create a new work item and assign it to the variable.
        let item = DispatchWorkItem { block() }
        self.workItem = item
        
        // Schedule the new work item to execute after the specified delay.
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}