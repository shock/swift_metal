//
//  ShaderManagere.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/26/24.
//

import Foundation

class ShaderManager {
    var metallibURL: URL?
    var uniforms: [String: Any] = [:] // Define as per your data needs
    var filesToMonitor: [URL] = []
    var errorMessage: String?
    var rawShaderSource: String?
    var shaderURL: URL?

    init() {}

    func loadShader(fileURL: URL) -> Bool {
        do {
            rawShaderSource = try getShaderSource()
            try parseFilesToMonitor()
            metallibURL = try metalToLib(srcURL: fileURL)
            shaderURL = fileURL
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

        throw "Unknown error compiling \(srcURL.path) to \(metalLibURL.path)"
    }
}
