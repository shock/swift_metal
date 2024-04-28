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

class FileDialog {
    // Required initializer
    init() {}

    @MainActor
    func openDialog(completion: @escaping (URL?) async -> Void) async {
        guard !FileDialogOpen.shared.isOpen else { return }
        FileDialogOpen.shared.isOpen = true
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.metal] // see UTType above and Info.plist Imported Type Identifiers

        let result = await panel.begin()
        if result == .OK, let url = panel.url {
            await completion(url)
        } else {
            await completion(nil)
        }
        FileDialogOpen.shared.isOpen = false
    }
}
