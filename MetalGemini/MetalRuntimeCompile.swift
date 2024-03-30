//
//  MetalRuntimeCompile.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/29/24.
//

import Foundation

// This works, but loading with `makeLibrary(URL: "MetalGemini/TestShaders.air")` throws an invalid library file error
// let command = "xcrun metal -c MetalGemini/TestShaders.metal -o MetalGemini/TestShaders.air"

// From: https://developer.apple.com/documentation/metal/shader_libraries/generating_and_loading_a_metal_library_symbol_file
// xcrun -sdk macosx metal -c -frecord-sources Shadow.metal
// xcrun -sdk macosx metal -frecord-sources -o Shadow.metallib Shadow.air
// xcrun -sdk macosx metal-dsymutil -flat -remove-source Shadow.metallib


// Also: https://developer.apple.com/documentation/metal/shader_libraries/building_a_shader_library_by_precompiling_source_files


// Get all the included file paths
// cpp TestShaders.metal 2> /dev/null | egrep -e "# \d+\s+\"" | sed -n 's/.*"\(.*\)".*/\1/p' | grep -v '<' | sort | uniq | sed -e 's/\.\///g'

func metalToAir(srcURL: URL) -> ShellExecResult {

    let airURL = srcURL.deletingPathExtension().appendingPathExtension("air")
    let metalLibURL = srcURL.deletingPathExtension().appendingPathExtension("metallib")

    var command = "cpp \(srcURL.path) 2> /dev/null | egrep -e \"# \\d+\\s+\\\"\" | sed -n 's/.*\"\\(.*\\)\".*/\\1/p' | grep -v '<' | sort | uniq"
    print(command)
    var execResult = shell_exec(command, cwd: nil)
    if execResult.exitCode != 0 { return execResult }
    let filePaths = execResult.stdOut

    command = "xcrun -sdk macosx metal -c -frecord-sources \(srcURL.path) -o \(airURL.path)"
    execResult = shell_exec(command, cwd: nil)
    if execResult.exitCode != 0 {
        execResult.stdOut = filePaths
        return execResult
    }

    command = "xcrun -sdk macosx metal -frecord-sources -o \(metalLibURL.path) \(airURL.path)"
    execResult = shell_exec(command, cwd: nil)
    if execResult.exitCode != 0 {
        execResult.stdOut = filePaths
        return execResult
    }

    command = "xcrun -sdk macosx metal-dsymutil -flat -remove-source \(metalLibURL.path)"
    execResult = shell_exec(command, cwd: nil)
    if execResult.exitCode != 0 {
        execResult.stdOut = filePaths
        return execResult
    }

    execResult.stdOut = filePaths
    return execResult
}
