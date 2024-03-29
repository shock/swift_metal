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
