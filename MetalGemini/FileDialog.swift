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
    @Binding var selectedURL: URL? // Binding for communication with SwiftUI view

    // Required initializer
    init(selectedURL: Binding<URL?>) {
        _selectedURL = selectedURL // Initialize the Binding
    }

    func openDialog() {
        if( FileDialogOpen.shared.isOpen ) { return }
        FileDialogOpen.shared.isOpen = true
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.metal] // see UTType above and Info.plist Imported Type Identifiers

        panel.begin { (result) in
            if result == .OK {
                self.selectedURL = panel.url // Do something with the selected URL
            }
            FileDialogOpen.shared.isOpen = false
        }
    }
}
