//
//  main.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/27/24.
//

import Foundation
import SwiftUI
import AppKit

// Create App Delegate instance
let appDelegate = AppDelegate()

// Standard NSApplication setup
let app = NSApplication.shared
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
