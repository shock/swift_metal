//
//  Extensions.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/29/24.
//

import Foundation

/// Extension to allow throwing String as an Error
extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

extension TimeInterval {
    func formattedMMSS() -> String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
