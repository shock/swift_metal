//
//  MutexRunner.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/29/24.
//

import Foundation

// Actor used to queue blocks of asynchronous code for serial execution
actor MutexRunner {
    func run(using block: @escaping () async -> Void) async {
        await block()
    }
}
