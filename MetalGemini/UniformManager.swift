//
//  UniformManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/17/24.
//

import Foundation
import MetalKit
import AppKit
import SwiftOSC

/// Enum representing the style of a uniform variable.
enum UniformStyle {
    case vSlider, toggle
}

/// Struct representing a uniform variable.
struct UniformVariable {
    let name: String
    let type: String
    let style: UniformStyle
    var active: Bool
    var values: [Float]
    let range: (min: Float, max: Float)
}

/// Manages uniforms for Metal applications, ensuring they are thread-safe and properly managed.
class UniformManager: ObservableObject {
    
    /// Struct representing undo data for a uniform variable.
    struct UndoData {
        var oldValues: [Float]
        var timer: Timer?
    }
    
    @Published var activeUniforms: [UniformVariable] = []
    private var undoManager: UndoManager
    private var metalDevice: MTLDevice!
    private var parameterMap: [String: Int] = [:] // Map from uniform names to their indices
    private var uniformVariables: [UniformVariable] = []
    private var dirty = true // Flag to indicate if the buffer needs updating
    private var debug = false // Debug flag to enable logging
    private var uniformsTxtURL: URL? // URL for the uniforms file
    private var buffer: MTLBuffer? // Metal buffer for storing uniform data
    private var semaphore = DispatchSemaphore(value: 1) // Ensures thread-safe access to the dirty flag
    private var saveDebouncer = Debouncer(delay: 0.5, queueLabel: "net.wdoughty.metaltoy.saveUniformsQueue") // Debouncer for saving operations
    private var updateBufferDebouncer = Debouncer(delay: 0.005, queueLabel: "net.wdoughty.metaltoy.mapToBuffer") // Debouncer for updating buffer
    private var projectDirDelegate: ShaderProjectDirAccess!
    private var undoRecords: [String:UndoData] = [:]
    let UndoCommitDelay = 0.25 // seconds before committing undo

    /// Initializes a new UniformManager.
    /// - Parameters:
    ///   - projectDirDelegate: Delegate for accessing the project directory.
    ///   - undoManager: Instance of UndoManager for managing undo operations.
    ///   - debug: Boolean flag to enable debugging.
    init(projectDirDelegate: ShaderProjectDirAccess, undoManager: UndoManager, debug: Bool = false) {
        self.projectDirDelegate = projectDirDelegate
        self.undoManager = undoManager
        self.debug = debug
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
    }

    /// Retrieves undo data for a uniform.
    /// - Parameter name: Name of the uniform.
    /// - Returns: UndoData for the uniform.
    private func getUndoData(_ name: String ) -> UndoData {
        if let undoData = undoRecords[name] {
            return undoData
        } else {
            if debug { print("creating undoData for \(name)") }
            let undoData = UndoData(oldValues: [], timer: nil)
            undoRecords[name] = undoData
            return undoData
        }
    }
    
    /// Sets undo data for a uniform.
    /// - Parameters:
    ///   - name: Name of the uniform.
    ///   - data: UndoData to set.
    func setUndoData(_ name: String, data: UndoData) {
        undoRecords[name] = data
    }

    /// Truncates values to fit the uniform type.
    /// - Parameters:
    ///   - index: Index of the uniform variable.
    ///   - values: Values to truncate.
    /// - Returns: Truncated values.
    private func truncateValues( index: Int, values: [Float] ) -> [Float] {
        let uVar = uniformVariables[index]
        let type = uVar.type
        let values = values.map { max(uVar.range.min, min($0, uVar.range.max)) }
        switch type {
        case "float":
            return [values[0]]
        case "float2":
            return Array(values.prefix(2))
        case "float3":
            return Array(values.prefix(3))
        case "float4":
            return values
        default: // we shouldn't be here
            print("UniformManager: truncateValues() - Bad data type: \(type)")
            return []
        }
    }

    /// Updates a uniform value.
    /// - Parameters:
    ///   - name: Name of the uniform.
    ///   - values: New values for the uniform.
    ///   - suppressSave: Whether to suppress saving the changes to file.
    ///   - updateBuffer: Whether to update the Metal buffer.
    private func updateUniform( _ name: String, values: [Float], suppressSave:Bool, updateBuffer: Bool ) {
        guard let index = parameterMap[name] else {
            print("ERROR: updateUniform - No uniform named: \(name)")
            return
        }
        if debug { print("updateUniform: \(name) to \(values)") }
        if !suppressSave { semaphore.wait() }
        let values = truncateValues(index: index, values: values)
        uniformVariables[index].values = values
        // Find the index of the element that matches the condition
        if let index = activeUniforms.firstIndex(where: { $0.name == name }) {
            activeUniforms[index].values = values
        }
        if( !suppressSave ) {
            saveDebouncer.debounce { [weak self] in
                self?.saveUniformsToFile()
            }
        }
        dirty = true
        if updateBuffer {
            updateBufferDebouncer.debounce { [weak self] in
                self?.triggerRenderRefresh()
                self?.mapUniformsToBuffer()
            }
        }
        if !suppressSave { semaphore.signal() }
    }

    /// Sets a uniform value from an array of floats, optionally suppressing the file save operation.
    /// - Parameters:
    ///   - name: Name of the uniform.
    ///   - values: New values for the uniform.
    ///   - suppressSave: Whether to suppress saving the changes to file.
    ///   - updateBuffer: Whether to update the Metal buffer.
    func setUniformTuple( _ name: String, values: [Float], suppressSave:Bool = false, updateBuffer:Bool = false) {
        guard let index = parameterMap[name] else {
            print("ERROR: setUniformTuple - No uniform named: \(name)")
            return
        }
        let values = truncateValues(index: index, values: values)
        if debug { print("\nUniformManager: setUniformTuple(\(name), \(values)") }
        if uniformVariables[index].values == values {
            if debug { print("current values match new values. Skipping setUniformTuple") }
            return
        }
        if !suppressSave {
            var undoData = getUndoData(name)
            let timer = undoData.timer
            if timer == nil {
                undoData.oldValues = uniformVariables[index].values
                if debug { print("setUniformTuple - timer is nil, setting oldValues: \(undoData.oldValues)") }
            } else {
                if debug { print("setUniformTuple - timer is NOT nil - invalidating") }
            }
            timer?.invalidate()
            if debug { print("setting timer for \(UndoCommitDelay) seconds") }
            undoData.timer = Timer.scheduledTimer(withTimeInterval: UndoCommitDelay, repeats: false) { _ in
                if self.debug { print("timer popped - calling UniformManager::registerUnfo(\(name))") }
                self.registerUndo(name)
            }
            setUndoData(name, data: undoData)
        }
        updateUniform(name, values: values, suppressSave: suppressSave, updateBuffer: updateBuffer)
    }

    /// Registers an undo operation for a uniform.
    /// - Parameter name: Name of the uniform.
    private func registerUndo(_ name: String) {
        guard let index = parameterMap[name] else {
            print("ERROR: registerUndo - No uniform named: \(name)")
            return
        }
        let currentValues = uniformVariables[index].values
        var undoData = getUndoData(name)
        let oldValues = undoData.oldValues
        if currentValues == oldValues {
            if debug { print("old values match current values. Skipping undo") }
            return
        }
        if debug { print("UniformManager::registerUndo \(name), oldValues: \(oldValues) currentValues: \(currentValues)") }
        undoManager.registerUndo(withTarget: self) { target in
            if self.debug { print("Inside registerUndo closure: \(name), oldValues: \(oldValues) currentValues: \(currentValues)") }
            self.updateUniform(name, values: oldValues, suppressSave: false, updateBuffer: true)
            self.registerRedo(name: name, previousValues: currentValues)
        }
        undoManager.setActionName("Change '\(name)'")

        // Reset the timer to nil
        undoData.timer = nil
        setUndoData(name, data: undoData)
    }

    /// Registers a redo operation for a uniform.
    /// - Parameters:
    ///   - name: Name of the uniform.
    ///   - previousValues: Previous values to redo.
    private func registerRedo(name: String, previousValues: [Float]) {
        if debug { print("UniformManager::registerRedo \(name), previousValues: \(previousValues)") }
        undoManager.registerUndo(withTarget: self) { target in
            if self.debug { print("Inside registerUndo closure: \(name) previousValues: \(previousValues)") }
            self.updateUniform(name, values: previousValues, suppressSave: false, updateBuffer: true)
            self.registerUndo(name)
        }
        undoManager.setActionName("Change '\(name)'")
    }

    /// Returns the updated uniforms buffer if necessary.
    /// - Returns: Metal buffer containing uniform data.
    func getBuffer() -> MTLBuffer? {
        semaphore.wait()
        defer { semaphore.signal() }
        mapUniformsToBuffer()
        return buffer
    }

    /// Resets the mapping of uniform names to buffer indices and types, marking the system as needing an update.
    private func resetMapping() {
        parameterMap.removeAll()
        uniformVariables.removeAll()
        undoRecords.removeAll()
        dirty = true
    }

    /// Adds a new uniform with the given name and type, returning its new index.
    /// - Parameters:
    ///   - name: Name of the uniform.
    ///   - type: Type of the uniform.
    ///   - style: Style of the uniform.
    ///   - min: Minimum range value.
    ///   - max: Maximum range value.
    /// - Returns: Index of the new uniform.
    private func setIndex(name: String, type: String, style: UniformStyle, min: Float, max: Float ) -> Int {
        if debug { print("UniformManager: setIndex(\(name), \(type))") }
        dirty = true
        var values: [Float] = []
        switch type {
        case "float":
            values.append(0)
        case "float2":
            values = [0,0]
        case "float3":
            values = [0,0,0]
        case "float4":
            values = [0,0,0,0]
        default: // we shouldn't be here
            print("UniformManager: setIndex() - Bad data type: \(type)")
            return -1
        }
        let uVar = UniformVariable(name: name, type:type, style: style, active: false, values: values, range: (min:min, max:max))
        let index = uniformVariables.count
        uniformVariables.append(uVar)
        parameterMap[name] = index
        return index
    }

    /// Parses the shader file to look for a struct tagged with @uniform, which will define 
    /// which uniforms are managed by the application and sent to the fragment shader
    /// in a buffer.  Example struct in fragment.metal:
    ///
    ///    struct MyShaderData { // @uniform
    ///        float2 o_long;
    ///        float4 o_pan;
    ///        float o_col1r;
    ///    }
    ///
    /// - Parameters:
    ///   - srcURL: URL of the shader source file.
    ///   - shaderSource: Shader source code as a string.
    /// - Throws: Error if unable to create the Metal buffer.
    // TODO: improve documentation.  Add unit tests.  Add type checking (vectors only)
    @MainActor
    func setupUniformsFromShader(srcURL: URL, shaderSource: String) async throws {
        resetMapping()

        if debug { print("UniformManager: setupUniformsFromShader() starting") }

        let lines = shaderSource.components(separatedBy: "\n")

        let structRegex = /\s*struct\s+(\w+)\s*\{\s*\/\/\s*@uniform/
        let endStructRegex = /\s*\}\;/
        let metadataRegex = /^\s*(float\d?)\s+(\w+)/
        let rangeRegex = /.*\/\/\s+@range[\s:]+(-?\d+.?\d*)\s+\.\.\s+(-?\d+.?\d*)/
        let toggleRegex = /.*@toggle.*/
        var insideStruct = false
        for line in lines {
            if( insideStruct ) {
                if let firstMatch = line.firstMatch(of: metadataRegex) {
                    let name = String(firstMatch.2)
                    let type = String(firstMatch.1)
                    var min:Float=0.0, max:Float=1.0
                    var style: UniformStyle = .vSlider
                    if let secondMatch = line.firstMatch(of: rangeRegex) {
                        if let _min = Float(secondMatch.1) { min = _min }
                        if let _max = Float(secondMatch.2) { max = _max }
                        if debug { print("Found range \(min) .. \(max)") }
                    }
                    if (line.firstMatch(of: toggleRegex) != nil) {
                        if type == "float" {
                            style = .toggle
                        } else {
                            print("WARNING: Uniform \(name) can't be a toggle.  Only float types can be toggles.")
                        }
                    }
                    _ = setIndex(name: name, type: type, style: style, min: min, max: max)
                }
                if( line.firstMatch(of: endStructRegex) != nil ) {
                    break
                }
            }
            if( line.firstMatch(of: structRegex) != nil ) { insideStruct = true }
        }

        insideStruct = false
        for line in lines {
            if( line.firstMatch(of: structRegex) != nil ) { insideStruct = true }
            if insideStruct == true {
                if( line.firstMatch(of: endStructRegex) != nil ) {
                    insideStruct = false
                }
            } else {
                for i in uniformVariables.indices {
                    do {
                        let uv = uniformVariables[i]
                        let regexPattern = "\\b\(uv.name)\\b"
                        let uvRegex = try NSRegularExpression(pattern: regexPattern, options: [])
                        let matches = uvRegex.matches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count))

                        if !matches.isEmpty {
                            uniformVariables[i].active = true
                        }
                    } catch {
                        print("error creating regex: \(error)")
                    }

                }
            }

        }
        activeUniforms = uniformVariables.filter {
            $0.active == true
        }
        let numUniforms = uniformVariables.count
        let length = MemoryLayout<SIMD4<Float>>.size*numUniforms
        buffer = metalDevice.makeBuffer(length: length, options: .storageModeShared)
        dirty = true

        uniformsTxtURL = srcURL.deletingPathExtension().appendingPathExtension("uniforms").appendingPathExtension("txt")
        uniformsTxtURL = URL(fileURLWithPath: uniformsTxtURL!.path)

        loadUniformsFromFile()
        if debug {
            print("UniformManager: setupUniformsFromShader() finished processing \(uniformVariables.count) uniforms, \(activeUniforms.count) active")
        }
        if buffer == nil {
            throw "Unable to create metal buffer"
        }
    }

    /// Triggers a render refresh notification.
    func triggerRenderRefresh() {
        NotificationCenter.default.post(name: .updateRenderFrame, object: nil, userInfo: [:])
    }

    /// Updates the uniforms buffer if necessary, handling data alignment and copying.
    private func mapUniformsToBuffer() {
        if !dirty { return }
        dirty = false
        if debug { print("Updating uniforms buffer") }
        guard let buffer = self.buffer else { return }

        var offset = 0
        for i in 0..<uniformVariables.count {
            var values = uniformVariables[i].values
            let dataType = uniformVariables[i].type
            if values.count == 0 { values = [0,0,0,0] }
            switch dataType {
            case "float":
                var data = values[0]
                // Ensure the offset is aligned
                offset = (offset + MemoryLayout<Float>.alignment - 1) / MemoryLayout<Float>.alignment * MemoryLayout<Float>.alignment
                // Copy the data
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<Float>.size)
                // Update the offset
                offset += MemoryLayout<Float>.size
            case "float2":
                var data = Array(values.prefix(2))
                offset = (offset + MemoryLayout<SIMD2<Float>>.alignment - 1) / MemoryLayout<SIMD2<Float>>.alignment * MemoryLayout<SIMD2<Float>>.alignment
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                offset += MemoryLayout<SIMD2<Float>>.size
            case "float3":
                var data = Array(values.prefix(3))
                offset = (offset + MemoryLayout<SIMD3<Float>>.alignment - 1) / MemoryLayout<SIMD3<Float>>.alignment * MemoryLayout<SIMD3<Float>>.alignment
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                offset += MemoryLayout<SIMD3<Float>>.size
            case "float4":
                var data = values
                offset = (offset + MemoryLayout<SIMD4<Float>>.alignment - 1) / MemoryLayout<SIMD4<Float>>.alignment * MemoryLayout<SIMD4<Float>>.alignment
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD4<Float>>.size)
                offset += MemoryLayout<SIMD4<Float>>.size
            default: // we shouldn't be here
                print("UniformManager: mapUniformsToBuffer() - Bad data type: \(dataType)")
            }
        }
    }

    /// Prints current uniforms values.
    func printUniforms() {
        print(uniformsToString())
    }

    /// Converts uniforms to a string representation for debugging.
    /// - Returns: String representation of uniforms.
    func uniformsToString() -> String {
        let uniforms = uniformVariables.map { uVar in
            let values = uVar.values
            let name = uVar.name
            let joinedString = values.map { String($0) }.joined(separator: ", ")
            return "\(name), \(joinedString)"
        }.joined(separator: "\n")

        return uniforms
    }

    /// Saves uniforms to a file, checking if there's a need to prompt for a directory.
    func saveUniformsToFile() {
        if( uniformVariables.count == 0 ) { return }

        guard let fileUrl = uniformsTxtURL else { return }
        let uniforms = uniformsToString()

        // Accessing the bookmark to perform file operations
        projectDirDelegate.accessDirectory() { dirUrl in
            do {
                try uniforms.write(to: fileUrl, atomically: true, encoding: .utf8)
                if debug { print("Data written successfully to \(fileUrl.path)") }
            } catch {
                print("Failed to save uniforms: \(error)")
            }
        }

    }

    /// Loads uniforms from a file.
    private func loadUniformsFromFile() {
        let path = uniformsTxtURL
        guard let filePath = path else { return }

        do {
            let content = try String(contentsOf: filePath, encoding: .utf8)
            let lines = content.split(separator: "\n")
            var data:[(String,String,[Float])] = []
            for line in lines {
                var segs = line.split(separator: ",")
                segs = segs.map { seg in seg.filter { !$0.isWhitespace } }
                var dataType=""
                switch segs.count {
                case 2: dataType="float"
                case 3: dataType="float2"
                case 4: dataType="float3"
                case 5: dataType="float4"
                default: throw "invalid line: \(line)"
                }
                let name = String(segs[0])
                let floats = try segs[1...].map { s in
                    let float = Float(s)
                    if( float == nil ) { throw "invalid line: \(line)" }
                    return float!
                }
                data.append((name, dataType, floats))
            }

            for (name, _, floats) in data {
                DispatchQueue.main.async {
                    self.setUniformTuple(name, values: floats, suppressSave: true)
                }
            }
            DispatchQueue.main.async {
                if( self.debug ) { self.printUniforms() }
                print("Uniforms successfully loaded from file.")
            }
        } catch {
            print("Failed to read the \(uniformsTxtURL?.path(percentEncoded: false) ?? "") file: \(error)")
        }
    }

}

/// Extension to handle OSC messages.
extension UniformManager: OSCMessageDelegate {
    /// Handles OSC messages to update uniforms.
    /// - Parameter message: OSCMessage containing the update information.
    func handleOSCMessage(message: OSCMessage) {
        let oscRegex = /[\/\d]*?(\w+).*/
        if let firstMatch = message.address.string.firstMatch(of: oscRegex) {
            let name = String(firstMatch.1)
            var tuple:[Float] = []
            for argument in message.arguments {
                if let float = argument as? Float {
                    tuple.append(float)
                } else if let double = argument as? Double {
                    print("WARNING: \(name) sent \(double) as double")
                }

            }
            self.setUniformTuple(name, values: tuple, updateBuffer: true)
        }
    }
}
