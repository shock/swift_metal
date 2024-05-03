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
class UniformManager
{
    var metalDevice: MTLDevice!
    var parameterMap: [String: Int] = [:] // Map from uniform names to their indices
    var indexMap: [(String,String)] = [] // Tuple storing uniform names and their types
    var float4dict = Float4Dictionary() // Dictionary to store uniform values
    var dirty = true // Flag to indicate if the buffer needs updating
    private var buffer: MTLBuffer? // Metal buffer for storing uniform data
    var debug = false // Debug flag to enable logging
    var uniformsTxtURL: URL? // URL for the uniforms file
    private var semaphore = DispatchSemaphore(value: 1) // Ensures thread-safe access to the dirty flag

    private var saveWorkItem: DispatchWorkItem? // Work item for saving uniforms
    private var saveQueue = DispatchQueue(label: "net.wdoughty.metaltoy.saveUniformsQueue") // Queue for saving operations
    private var projectDirDelegate: ShaderProjectDirAccess!

    init(projectDirDelegate: ShaderProjectDirAccess) {
        self.projectDirDelegate = projectDirDelegate
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
    }

    // Schedule a task to save the uniforms to a file, cancelling any previous scheduled task
    private func requestSaveUniforms() {
        saveWorkItem?.cancel() // Cancel the previous task if it exists
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveUniformsToFile()
        }

        // Schedule the save after a delay (e.g., 500 milliseconds)
        if let saveWorkItem = saveWorkItem {
            saveQueue.asyncAfter(deadline: .now() + 0.5, execute: saveWorkItem)
        }
    }

    // Reset mapping of uniform names to buffer indices and types, marking the system as needing an update
    private func resetMapping() {
        parameterMap.removeAll()
        indexMap.removeAll()
        dirty = true
    }

    // Add a new uniform with the given name and type, returning its new index
    private func setIndex(name: String, type: String ) -> Int
    {
        if debug { print("UniformManager: setIndex(\(name), \(type))") }
        indexMap.append((name,type))
        let index = indexMap.count-1
        parameterMap[name] = index
        dirty = true
        return index
    }

    // Set a uniform value from an array of floats, optionally suppressing the file save operation
    func setUniformTuple( _ name: String, values: [Float], suppressSave:Bool = false, updateBuffer:Bool = false)
    {
        if !suppressSave { semaphore.wait() }
        if debug { print("UniformManager: setUniformTuple(\(name), \(values)") }
        float4dict.setTuple(name, values: values)
        dirty = true
        if( !suppressSave ) {
            requestSaveUniforms()
            if( debug ) { printUniforms() }
        }
        if !suppressSave { semaphore.signal() }
        if updateBuffer { mapUniformsToBuffer() }
    }

    // Update the uniforms buffer if necessary and return it
    func getBuffer() -> MTLBuffer? {
        semaphore.wait()
        defer { semaphore.signal() }
        mapUniformsToBuffer()
        return buffer
    }

    var insideSetUniform = false
    // Update the uniforms buffer if necessary, handling data alignment and copying
    private func mapUniformsToBuffer() {
        if !dirty { return }
//        print("UniformManager: mapUniformsToBuffer() - dirty - insideSetUniform: \(insideSetUniform) on thread \(Thread.current)")
        dirty = false
        if debug { print("Updating uniforms buffer") }
        guard let buffer = self.buffer else { return }

        var offset = 0
        for i in 0..<indexMap.count {
            let (key, dataType) = indexMap[i]
            switch dataType {
            case "float":
                var data = float4dict.getAsFloat(key)
                // Ensure the offset is aligned
                offset = (offset + MemoryLayout<Float>.alignment - 1) / MemoryLayout<Float>.alignment * MemoryLayout<Float>.alignment
                // Copy the data
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<Float>.size)
                // Update the offset
                offset += MemoryLayout<Float>.size
            case "float2":
                var data = float4dict.getAsFloat2(key)
                offset = (offset + MemoryLayout<SIMD2<Float>>.alignment - 1) / MemoryLayout<SIMD2<Float>>.alignment * MemoryLayout<SIMD2<Float>>.alignment
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                offset += MemoryLayout<SIMD2<Float>>.size
            case "float3":
                var data = float4dict.getAsFloat3(key)
                offset = (offset + MemoryLayout<SIMD3<Float>>.alignment - 1) / MemoryLayout<SIMD3<Float>>.alignment * MemoryLayout<SIMD3<Float>>.alignment
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                offset += MemoryLayout<SIMD3<Float>>.size
            case "float4":
                var data = float4dict.get(key)
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
        guard parameterMap[name] != nil else {
            return nil
        }
        let data = float4dict.get(name)
        return data
    }

    // Convert uniforms to a string representation for debugging
    func uniformsToString() -> String {
        let uniforms = Array(indexMap.indices).map { i in
            let (key, dataType) = indexMap[i]
            switch dataType {
            case "float":
                let data = float4dict.getAsFloat(key)
                return "\(key), \(data)"
            case "float2":
                let data = float4dict.getAsFloat2(key)
                return "\(key), \(data.x), \(data.y)"
            case "float3":
                let data = float4dict.getAsFloat3(key)
                return "\(key), \(data.x), \(data.y), \(data.z),"
            default: // Assuming default is "float4"
                let data = float4dict.get(key)
                return "\(key), \(data.x), \(data.y), \(data.z), \(data.w)"
            }
        }.joined(separator: "\n")

        return uniforms
    }

    // Save uniforms to a file, checking if there's a need to prompt for a directory
    func saveUniformsToFile() {
        if( indexMap.count == 0 ) { return }

        guard let fileUrl = uniformsTxtURL else { return }
        let uniforms = uniformsToString()

//        let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(bookmarkID)")
//        if( bookmarkData == nil ) {
//            print("no bookmark")
//        }

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
                setUniformTuple(name,values: floats, suppressSave: true)
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
    func setupUniformsFromShader(srcURL: URL, shaderSource: String) async throws {
//        semaphore.wait()
        resetMapping()

        print("UniformManager: setupUniformsFromShader()")
        insideSetUniform = true

        let lines = shaderSource.components(separatedBy: "\n")

        let structRegex = /\s*struct\s+(\w+)\s*\{\s*\/\/\s*@uniform/
        let endStructRegex = /\s*\}\;/
        let metadataRegex = /\s?(float\d?)\s+(\w+)/

        var index = 0
        var insideStruct = false
        for line in lines {
            if( insideStruct ) {
                if let firstMatch = line.firstMatch(of: metadataRegex) {
                    index = setIndex(name: String(firstMatch.2), type: String(firstMatch.1))
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

        if( debug ) {
            printUniforms()
        }
        uniformsTxtURL = srcURL.deletingPathExtension().appendingPathExtension("uniforms").appendingPathExtension("txt")
        uniformsTxtURL = URL(fileURLWithPath: uniformsTxtURL!.path)

//        let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(bookmarkID)")
//        if( bookmarkData == nil ) {
//            print("WARNING: no project directory bookmark found")
//            Task {
//                await projectDirDelegate.selectDirectory()
//            }
//        }

        loadUniformsFromFile()
        print("UniformManager: setupUniformsFromShader()")
        insideSetUniform = false
        defer { semaphore.signal() }
        guard let buffer = buffer else {
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
