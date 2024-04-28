//
//  ShaderManagere.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/26/24.
//

import Foundation
import AppKit

protocol ShaderProjectFileAccess {
}

class ShaderManager {
    var metallibURL: URL?
    var uniforms: [String: Any] = [:] // Define as per your data needs
    var filesToMonitor: [URL] = []
    var errorMessage: String?
    var rawShaderSource: String?
    var shaderURL: URL?
    var projectDirURL: URL? // Directory URL for the project with shader files, bitmaps, etc.  Writable by the application
    let bookmarkID = "net.wdoughty.metaltoy.projectdir" // Bookmark ID for sandboxed file access

    init() {}

    func loadShader(fileURL: URL) -> Bool {
        do {
            shaderURL = fileURL
            rawShaderSource = try getShaderSource()
            try parseFilesToMonitor()
            metallibURL = try metalToLib(srcURL: fileURL)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func parseFilesToMonitor() throws {
        // TODO: refactor this to use pre-processed source instead of shelling out again
        guard let srcURL = shaderURL else { throw "Must call loadShader() first" }

        // Get all the included file paths
        // cpp TestShaders.metal 2> /dev/null | egrep -e "# \d+\s+\"" | sed -n 's/.*"\(.*\)".*/\1/p' | grep -v '<' | sort | uniq | sed -e 's/\.\///g'

        let command = "cpp \(srcURL.path) 2> /dev/null | egrep -e \"# \\d+\\s+\\\"\" | sed -n 's/.*\"\\(.*\\)\".*/\\1/p' | grep -v '<' | sort | uniq"
        let execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            throw execResult.stdErr ?? "Unknown error running `\(command)`"
        }
        let paths = execResult.stdOut!.components(separatedBy: "\n")
        var urls: [URL] = []
        for path in paths {
            if path != "" {
                let url = URL(fileURLWithPath: path)
                urls.append(url)
            }
        }

        filesToMonitor = urls

    }

    // Get the shader source from a URL and parse it for uniform struct definitions
    private func getShaderSource() throws -> String?
    {
        guard let srcURL = shaderURL else { throw "Must call loadShader() first" }
        let command = "cpp \(srcURL.path) 2> /dev/null | cat" // hack to avoid error status on cpp
        let execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            let error = execResult.stdErr ?? "Unknown error pre-processing shader file \(srcURL.path)"
            throw error
        }
        return execResult.stdOut
    }

}


extension ShaderManager: ShaderProjectFileAccess {
    
    // Open a panel to select a directory for storing project files
    @MainActor
    private func selectProjectDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            let openPanel = NSOpenPanel()
            openPanel.title = "Choose a project directory"
            openPanel.message = "Select the directory containing your shader file"
            openPanel.showsResizeIndicator = true
            openPanel.showsHiddenFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = true
            openPanel.canChooseFiles = false
            openPanel.allowsMultipleSelection = false

            // Directly use main thread via MainActor
            Task {
                openPanel.begin { result in
                    if result == .OK, let selectedPath = openPanel.url {
                        print("Directory selected: \(selectedPath.path)")
                        self.storeSecurityScopedBookmark(for: selectedPath, withIdentifier: self.bookmarkID)
                        self.projectDirURL = selectedPath
//                        continuation.resume(returning: selectedPath)
                    } else {
                        print("User cancelled the open panel")
//                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    func getProjectDir() -> URL? {
        if let projectDirURL = projectDirURL {
            return projectDirURL
        }
        Task {
            await selectProjectDirectory()
        }
        return projectDirURL
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
//                selectProjectDirectory()
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
    
    func getProjectDirectoryBookmark() {
        let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(bookmarkID)")
        if( bookmarkData == nil ) {
            print("WARNING: no project directory bookmark found")
//            selectProjectDirectory()
        }
    }


}

extension ShaderManager {
    func metalToLib(srcURL: URL) throws -> URL {

        // From: https://developer.apple.com/documentation/metal/shader_libraries/generating_and_loading_a_metal_library_symbol_file
        // xcrun -sdk macosx metal -c -frecord-sources Shadow.metal
        // xcrun -sdk macosx metal -frecord-sources -o Shadow.metallib Shadow.air
        // xcrun -sdk macosx metal-dsymutil -flat -remove-source Shadow.metallib


        // Also: https://developer.apple.com/documentation/metal/shader_libraries/building_a_shader_library_by_precompiling_source_files

        // Get all the included file paths
        // cpp TestShaders.metal 2> /dev/null | egrep -e "# \d+\s+\"" | sed -n 's/.*"\(.*\)".*/\1/p' | grep -v '<' | sort | uniq | sed -e 's/\.\///g'


        let airURL = srcURL.deletingPathExtension().appendingPathExtension("air")
        let metalLibURL = srcURL.deletingPathExtension().appendingPathExtension("metallib")

        var command = "xcrun -sdk macosx metal -c -frecord-sources \(srcURL.path) -o \(airURL.path)"
        var execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            throw execResult.stdErr!
        }

        command = "xcrun -sdk macosx metal -frecord-sources -o \(metalLibURL.path) \(airURL.path)"
        execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            throw execResult.stdErr!
        }

        command = "xcrun -sdk macosx metal-dsymutil -flat -remove-source \(metalLibURL.path)"
        execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            throw execResult.stdErr!
        }
        
        return metalLibURL
    }
}
