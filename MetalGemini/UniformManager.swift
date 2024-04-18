//
//  UniformManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/17/24.
//

import Foundation
import MetalKit

extension Array where Element == Float
{
    func toSIMD4() -> SIMD4<Float>? {
        var c = self
        while( c.count < 4 ) { c.append(0) }
        return SIMD4<Float>(c[0], c[1], c[2], c[3])
    }
}

class Float4Dictionary
{
    private var semaphore = DispatchSemaphore(value: 1) // Allows 1 concurrent access
    var map: [String: SIMD4<Float>] = [:]

    init() {}

    func setTuple( _ key: String, values: [Float])
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        let value = values.toSIMD4()
        map[key] = value
    }

    func set( _ key: String, _ simd4: SIMD4<Float> )
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        map[key] = simd4
    }

    func get( _ key: String, _ defaultValue: SIMD4<Float> = SIMD4<Float>(0,0,0,0) ) -> SIMD4<Float>
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        return map[key, default: defaultValue]
    }

    func getAsFloat( _ key: String, _ defaultValue: Float = 0 ) -> Float
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        guard let float4 = map[key] else { return defaultValue }
        return float4.x
    }

    func getAsFloat2( _ key: String, _ defaultValue: SIMD2<Float> = SIMD2<Float>(0,0)) -> SIMD2<Float>
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        guard let float4 = map[key] else { return defaultValue }
        return SIMD2<Float>(float4.x,float4.y)
    }

    func getAsFloat3( _ key: String, _ defaultValue: SIMD3<Float> = SIMD3<Float>(0,0,0)) -> SIMD3<Float>
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        guard let float4 = map[key] else { return defaultValue }
        return SIMD3<Float>(float4.x,float4.y,float4.z)
    }

    func delete( _ key: String ) -> SIMD4<Float>?
    {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        return map.removeValue(forKey: key)
    }

    func clear() {
        semaphore.wait()  // wait until the resource is free to use
        defer { semaphore.signal() }  // signal that the resource is free now
        map.removeAll()
    }
}

class UniformManager
{
    var parameterMap: [String: Int] = [:]
    var indexMap: [(String,String)] = []
    var float4dict = Float4Dictionary()
    var dirty = true
    var buffer: MTLBuffer?
    var debug = true

    func resetMapping() {
        parameterMap.removeAll()
        indexMap.removeAll()
        dirty = true
    }

    func clearUniforms() {
        float4dict.clear()
        dirty = true
    }

    private func setIndex(name: String, type: String ) -> Int
    {
        indexMap.append((name,type))
        let index = indexMap.count-1
        parameterMap[name] = index
        dirty = true
        return index
    }

    func setUniformTuple( _ name: String, values: [Float])
    {
        float4dict.setTuple(name, values: values)
        dirty = true
        if( debug ) { printUniforms() }
    }

    func setUniform( _ name: String, _ simd4: SIMD4<Float> )
    {
        float4dict.set(name, simd4)
        dirty = true
    }

    func mapUniformsToBuffer() {
        if !dirty { return }
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
                // Ensure the offset is aligned
                offset = (offset + MemoryLayout<SIMD2<Float>>.alignment - 1) / MemoryLayout<SIMD2<Float>>.alignment * MemoryLayout<SIMD2<Float>>.alignment
                // Rebind memory and copy the data
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                // Update the offset
                offset += MemoryLayout<SIMD2<Float>>.size
            case "float3":
                var data = float4dict.getAsFloat3(key)
                // Ensure the offset is aligned
                offset = (offset + MemoryLayout<SIMD3<Float>>.alignment - 1) / MemoryLayout<SIMD3<Float>>.alignment * MemoryLayout<SIMD3<Float>>.alignment
                // Rebind memory and copy the data
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD3<Float>>.size)
                // Update the offset
                offset += MemoryLayout<SIMD3<Float>>.size
            default: // Assuming default is "float4"
                var data = float4dict.get(key)
                // Ensure the offset is aligned
                offset = (offset + MemoryLayout<SIMD4<Float>>.alignment - 1) / MemoryLayout<SIMD4<Float>>.alignment * MemoryLayout<SIMD4<Float>>.alignment
                // Rebind memory and copy the data
                memcpy(buffer.contents().advanced(by: offset), &data, MemoryLayout<SIMD4<Float>>.size)
                // Update the offset
                offset += MemoryLayout<SIMD4<Float>>.size
            }
        }
    }

    func printUniforms() {
        for i in 0..<indexMap.count  {
            let (key,_) = indexMap[i]
            let float4 = float4dict.get(key)
            print("\(key),\(float4.x),\(float4.y),\(float4.z),\(float4.w)")
        }
    }

    private func getShaderSource(srcURL: URL) -> String?
    {
        let command = "cpp \(srcURL.path) 2> /dev/null"
        let execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            return nil
        }
        return execResult.stdOut
    }

    func setupUniformsFromShader(metalDevice: MTLDevice, srcURL: URL) -> String?
    {
        resetMapping()
        guard
            let shaderSource = getShaderSource(srcURL: srcURL)
            else { return "Failed to read shader file: \(srcURL)" }

        let lines = shaderSource.components(separatedBy: "\n")

        // example line:
        //   float myFloatValue;  // @uniform

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
        return nil
    }
}
