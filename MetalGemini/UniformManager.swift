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

// Manages uniforms for Metal applications, ensuring they are thread-safe and properly managed
class UniformManager: ObservableObject {
    var metalDevice: MTLDevice!
    var parameterMap: [String: Int] = [:] // Map from uniform names to their indices
    var indexMap: [(String,String)] = [] // Tuple storing uniform names and their types
//    var float4dict = Float4Dictionary() // Dictionary to store uniform values
    @Published var uniformVariables: [UniformVariable] = []
    var dirty = true // Flag to indicate if the buffer needs updating
    private var buffer: MTLBuffer? // Metal buffer for storing uniform data
    var debug = false // Debug flag to enable logging
    var uniformsTxtURL: URL? // URL for the uniforms file
    private var semaphore = DispatchSemaphore(value: 1) // Ensures thread-safe access to the dirty flag

    private var saveDebouncer = Debouncer(delay: 0.5, queueLabel: "net.wdoughty.metaltoy.saveUniformsQueue") // Debouncer for saving operations
    private var updateBufferDebouncer = Debouncer(delay: 0.005, queueLabel: "net.wdoughty.metaltoy.mapToBuffer") // Debouncer for updating buffer
    private var projectDirDelegate: ShaderProjectDirAccess!

    func updateValue(index: Int, valueIndex: Int, newValue: Float) {
        guard newValue >= uniformVariables[index].range.min &&
              newValue <= uniformVariables[index].range.max else { return }
        dirty = true
        uniformVariables[index].values[valueIndex] = newValue
        updateBufferDebouncer.debounce { [weak self] in
            self?.triggerRenderRefresh()
            self?.mapUniformsToBuffer()
        }
    }

    func getCurrentValues() -> [UniformVariable] {
        return uniformVariables
    }

    init(projectDirDelegate: ShaderProjectDirAccess) {
        self.projectDirDelegate = projectDirDelegate
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
    }

    // Reset mapping of uniform names to buffer indices and types, marking the system as needing an update
    private func resetMapping() {
        parameterMap.removeAll()
        uniformVariables.removeAll()
        indexMap.removeAll()
        dirty = true
    }

    private func truncateValues( index: Int, values: [Float] ) -> [Float] {
        let uVar = uniformVariables[index]
        let (_, type) = indexMap[index]
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

    // Add a new uniform with the given name and type, returning its new index
    private func setIndex(name: String, type: String, min: Float, max: Float ) -> Int
    {
        if debug { print("UniformManager: setIndex(\(name), \(type))") }
        indexMap.append((name,type))
        let index = indexMap.count-1
        parameterMap[name] = index
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
        let uVar = UniformVariable(name: name, values: values, range: (min:min, max:max))
        uniformVariables.append(uVar)
        return index
    }
    
//    // Add to a float uniform value by name, optionally suppressing the file save operation
//    func incrementFloatUniform( _ name: String, increment: Float, min: Float, max: Float, suppressSave:Bool = false, updateBuffer:Bool = true)
//    {
//        var value = float4dict.getAsFloat(name)
//        value += increment
//        value += -min
//        value = value.truncatingRemainder(dividingBy: max-min)
//        if value < 0 { value = max-min+value } // wrap around negative
//        value -= -min
//        print(value)
//        let values:[Float] = [value]
//        setUniformTuple(name, values: values, suppressSave: suppressSave, updateBuffer: updateBuffer)
//    }
    
//    func getUniformTuple(_ name: String) -> [Float] {
//        let index = parameterMap[name]!
//        let (_,type) = indexMap[index]
//        var tuple = uniformVariables[index].values
//        return tuple
//    }
//
    
    func triggerRenderRefresh() {
        NotificationCenter.default.post(name: .updateRenderFrame, object: nil, userInfo: [:])
    }
    
    // Set a uniform value from an array of floats, optionally suppressing the file save operation
    func setUniformTuple( _ name: String, values: [Float], suppressSave:Bool = false, updateBuffer:Bool = false)
    {
        guard let index = parameterMap[name] else {
            print("No uniform named: \(name)")
            return
        }
        let values = truncateValues(index: index, values: values)
        if !suppressSave { semaphore.wait() }
        if debug { print("UniformManager: setUniformTuple(\(name), \(values)") }
        uniformVariables[index].values = values
        dirty = true
        if( !suppressSave ) {
            saveDebouncer.debounce { [weak self] in
                self?.saveUniformsToFile()
            }
            if( debug ) { printUniforms() }
        }
        if !suppressSave { semaphore.signal() }
        if updateBuffer {
            updateBufferDebouncer.debounce { [weak self] in
                self?.triggerRenderRefresh()
                self?.mapUniformsToBuffer()
            }
        }
    }

    // Update the uniforms buffer if necessary and return it
    func getBuffer() -> MTLBuffer? {
        semaphore.wait()
        defer { semaphore.signal() }
        mapUniformsToBuffer()
        return buffer
    }

    // Update the uniforms buffer if necessary, handling data alignment and copying
    private func mapUniformsToBuffer() {
        if !dirty { return }
        dirty = false
        if debug { print("Updating uniforms buffer") }
        guard let buffer = self.buffer else { return }

        var offset = 0
        for i in 0..<indexMap.count {
            let (_, dataType) = indexMap[i]
            var values = uniformVariables[i].values
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

    // Print current uniforms values
    func printUniforms() {
        print(uniformsToString())
    }

    func getUniformFloat4( _ name: String ) -> SIMD4<Float>? {
        guard let index = parameterMap[name] else {
            return nil
        }
        let data = uniformVariables[index].values.toSIMD4()
        return data
    }

    // Convert uniforms to a string representation for debugging
    func uniformsToString() -> String {
        let uniforms = Array(indexMap.indices).map { i in
            let (key, _) = indexMap[i]
            let values = uniformVariables[i].values
            let joinedString = values.map { String($0) }.joined(separator: ", ")
            return "\(key), \(joinedString)"
        }.joined(separator: "\n")

        return uniforms
    }

    // Save uniforms to a file, checking if there's a need to prompt for a directory
    func saveUniformsToFile() {
        if( indexMap.count == 0 ) { return }

        guard let fileUrl = uniformsTxtURL else { return }
        let uniforms = uniformsToString()

        // Accessing the bookmark to perform file operations
        projectDirDelegate.accessDirectory() { dirUrl in
            do {
                try uniforms.write(to: fileUrl, atomically: true, encoding: .utf8)
                print("Data written successfully to \(fileUrl.path)")
            } catch {
                print("Failed to save uniforms: \(error)")
            }
        }

    }

    // Load uniforms from a file
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
            print("Uniforms successfully loaded from file.")

        } catch {
            print("Failed to read the \(uniformsTxtURL?.path(percentEncoded: false) ?? "") file: \(error)")
        }
    }

    // parses the shader file to look for a struct tagged
    // with @uniform, which will define which uniforms
    // are managed by the application and sent to the fragment
    // shader in a buffer.  Example struct in fragment.metal:
    //
    //    struct MyShaderData { // @uniform
    //        float2 o_long;
    //        float4 o_pan;
    //        float o_col1r;
    //    }
    //
    // TODO: improve documentation.  Add unit tests.  Add type checking (vectors only)
    @MainActor
    func setupUniformsFromShader(srcURL: URL, shaderSource: String) async throws {
        resetMapping()

        print("UniformManager: setupUniformsFromShader() starting")

        let lines = shaderSource.components(separatedBy: "\n")

        let structRegex = /\s*struct\s+(\w+)\s*\{\s*\/\/\s*@uniform/
        let endStructRegex = /\s*\}\;/
        let metadataRegex = /^\s*(float\d?)\s+(\w+)/
        let rangeRegex = /.*\/\/\s+@range[\s:]+(-?\d+.?\d*)\s+\.\.\s+(-?\d+.?\d*)/
        var index = 0
        var insideStruct = false
        for line in lines {
            if( insideStruct ) {
                if let firstMatch = line.firstMatch(of: metadataRegex) {
                    var min:Float=0.0, max:Float=1.0
                    if let secondMatch = line.firstMatch(of: rangeRegex) {
                        if let _min = Float(secondMatch.1) { min = _min }
                        if let _max = Float(secondMatch.2) { max = _max }
                        print("Found range \(min) .. \(max)")
                    }
                    index = setIndex(name: String(firstMatch.2), type: String(firstMatch.1), min: min, max: max)
                }
                if( line.firstMatch(of: endStructRegex) != nil ) {
                    break
                }
            }
            if( line.firstMatch(of: structRegex) != nil ) { insideStruct = true }
        }
        let numUniforms = index + 1
        let length = MemoryLayout<SIMD4<Float>>.size*numUniforms
        buffer = metalDevice.makeBuffer(length: length, options: .storageModeShared)
        dirty = true

        if( debug ) { printUniforms() }
        uniformsTxtURL = srcURL.deletingPathExtension().appendingPathExtension("uniforms").appendingPathExtension("txt")
        uniformsTxtURL = URL(fileURLWithPath: uniformsTxtURL!.path)

        loadUniformsFromFile()
        print("UniformManager: setupUniformsFromShader() finished")
        defer { semaphore.signal() }
        if buffer == nil {
            throw "Unable to create metal buffer"
        }
    }
}

extension UniformManager: OSCMessageDelegate {
    func handleOSCMessage(message: OSCMessage) {
        let oscRegex = /[\/\d]*?(\w+).*/
        if let firstMatch = message.address.string.firstMatch(of: oscRegex) {
            let name = firstMatch.1
            var tuple:[Float] = []
            for argument in message.arguments {
                if let float = argument as? Float {
                    tuple.append(float)
                } else if let double = argument as? Double {
                    print("WARNING: \(name) sent \(double) as double")
                }

            }
            self.setUniformTuple(String(name), values: tuple, updateBuffer: true)

        }
    }
}
