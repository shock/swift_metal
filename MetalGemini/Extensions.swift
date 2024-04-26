//
//  Extensions.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/29/24.
//

import Foundation

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
