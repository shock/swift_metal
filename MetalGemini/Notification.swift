//
//  Notification.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/24/24.
//

import Foundation

extension Notification.Name {
    static let vsyncStatusDidChange = Notification.Name("vsyncStatusDidChange")
    static let updateRenderFrame = Notification.Name("updateRenderFrame")
}
