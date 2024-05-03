//
//  SerialRunner.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/29/24.
//

import Foundation

// Actor used to queue blocks of asynchronous code for serial execution
actor SerialRunner {
    public private(set) var isRunning = false
    
    func run(using block: @escaping () async -> Void) async {
        self.isRunning = true
        defer { self.isRunning = false }
        await block()
    }
}
