//
//  ShellExec.swift
//  MetalGemini
//
//  Created by Bill Doughty on 3/29/24.
//

import Foundation

struct ShellExecResult {
    var command: String!
    var stdOut: String?
    var stdErr: String?
    var exitCode: Int32 = 0
}

@discardableResult
func shell_exec(_ command: String, cwd: String?, waitUntilExit: Bool = true ) -> ShellExecResult {
    let task = Process()
    let pipeOut = Pipe()
    let pipeErr = Pipe()

    var cmd = command
    if cwd != nil {
        cmd = "cd \(cwd!) && \(command)"
    }

    task.standardError = pipeErr
    task.standardOutput = pipeOut
    task.arguments = ["-c", cmd]
    task.launchPath = "/bin/bash"
    task.standardInput = nil
    task.launch()
    if waitUntilExit { task.waitUntilExit() } // Wait for the process to finish

    // print("executing command: \(cmd)")
    var execResult = ShellExecResult()
    execResult.exitCode = task.terminationStatus
    var data = pipeOut.fileHandleForReading.readDataToEndOfFile()
    execResult.stdOut = String(data: data, encoding: .utf8)!
    data = pipeErr.fileHandleForReading.readDataToEndOfFile()
    execResult.stdErr = String(data: data, encoding: .utf8)!
    if execResult.stdErr == "" {
        execResult.stdErr = nil;
    }
    execResult.command = cmd

    return execResult

}
