//
//  FileDialog.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/28/24.
//

import SwiftUI
import UniformTypeIdentifiers

// https://stackoverflow.com/questions/75971785/how-to-use-allowedcontenttypes-for-the-nsopenpanel-in-macos
extension UTType {
    public static let metal = UTType(importedAs: "com.apple.metal")
}

private class FileDialogOpen {
    static let shared = FileDialogOpen()
    var isOpen = false

    private init() { }
}

@MainActor
class FileDialog {
    init() {}

    func openDialog() async -> URL? {
        guard !FileDialogOpen.shared.isOpen else { return nil }
        FileDialogOpen.shared.isOpen = true

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.metal]

        let result = await panel.begin()
        defer { FileDialogOpen.shared.isOpen = false }

        if result == .OK, let url = panel.url {
            return url
        }
        return nil
    }
}
