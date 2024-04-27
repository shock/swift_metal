//
//  ShaderManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/25/24.
//

import Foundation
import AppKit
import MetalKit

@objc protocol ShaderManagerDelegate {
    func shaderSource()
}

// Manages shader file loading, parsing, project folder access[
class ShaderManager_
{
    var debug = false    // Debug flag to enable logging
    var shaderURL: URL!  // URL to shader file
    var shaderSource: String?  // uncompiled source preprocessed with includes inlined
    var shaderError: String?   // stores error, messages, if shader can't be opened, compiled or parsed
    var projectDirURL: URL? // Directory URL for the project with shader files, bitmaps, etc.  Writable by the application
    var uniformManager: UniformManager!
    let bookmarkID = "net.wdoughty.metaltoy.projectdir" // Bookmark ID for sandboxed file access

    private var semaphore = DispatchSemaphore(value: 1) // Ensures thread-safe access to the dirty flag

    private var saveWorkItem: DispatchWorkItem? // Work item for saving uniforms
    private var saveQueue = DispatchQueue(label: "net.wdoughty.metaltoy.saveUniformsQueue") // Queue for saving operations

    init(shaderURL: URL) {
        self.shaderURL = shaderURL
        self.uniformManager = UniformManager()
//        loadShader()
    }

    // Open a panel to select a directory for storing project files
    func selectProjectDirectory() {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {

            let openPanel = NSOpenPanel()
            openPanel.title = "Choose a project directory"
            openPanel.message = "Select the directory containing your shader file"
            openPanel.showsResizeIndicator = true
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = true
            openPanel.canChooseFiles = false
            openPanel.allowsMultipleSelection = false

            openPanel.begin { (result) in
                if result == .OK {
                    if let selectedPath = openPanel.url {
                        print("Directory selected: \(selectedPath.path)")
                        self.storeSecurityScopedBookmark(for: selectedPath, withIdentifier: self.bookmarkID)
                        self.projectDirURL = selectedPath
                    }
                } else {
                    print("User cancelled the open panel")
                }
            }
            semaphore.signal()
        }
        // Wait for the async operation to finish
        semaphore.wait()
    }

    // Store a security-scoped bookmark to persist access to the directory across app launches
    private func storeSecurityScopedBookmark(for directory: URL, withIdentifier identifier: String) {
        do {
            let bookmarkData = try directory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(identifier)")
            print("Bookmark for \(identifier) saved successfully.")
        } catch {
            print("Failed to create bookmark for \(identifier): \(error)")
        }
    }

    // Access a directory using a stored bookmark, performing a file operation within the bookmark's scope
    func accessProjectDirectory(withIdentifier identifier: String, using fileOperation: (URL) -> Void) {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(identifier)") else {
            print("No bookmark data found for \(identifier).")
            return
        }

        var isStale = false
        do {
            let bookmarkedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                print("Bookmark for \(identifier) is stale, need to refresh")
                selectProjectDirectory()
            } else {
                if bookmarkedURL.startAccessingSecurityScopedResource() {
                    fileOperation(bookmarkedURL)
                    bookmarkedURL.stopAccessingSecurityScopedResource()
                }
            }
        } catch {
            print("Error resolving bookmark for \(identifier): \(error)")
        }
    }

}
