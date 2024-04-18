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
    var map: [String: SIMD4<Float>] = [:]

    init() {}

    func setTuple( _ key: String, values: [Float])
    {
        var value = values.toSIMD4()
        map[key] = value
    }

    func set( _ key: String, _ simd4: SIMD4<Float> )
    {
        map[key] = simd4
    }

    func get( _ key: String, _ defaultValue: SIMD4<Float> = SIMD4<Float>(0,0,0,0) ) -> SIMD4<Float>
    {
        return map[key, default: defaultValue]
    }

    func delete( _ key: String ) -> SIMD4<Float>?
    {
        return map.removeValue(forKey: key)
    }

    func clear() {
        map.removeAll()
    }
}

class UniformManager
{
    var parameterMap: [String: Int] = [:]
    var indexMap: [String] = []
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

    private func setIndex(name: String ) -> Int
    {
        indexMap.append(name)
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

    func mapUniformsToBuffer()
    {
        if( !dirty ) {return}
        dirty = false
        if( debug ) { print("Updating uniforms buffer") }
        guard let buffer = self.buffer else { return }
        let bufferContents = buffer.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        for i in 0..<indexMap.count  {
            let key = indexMap[i]
            let float4 = float4dict.get(key)
            bufferContents[i] = float4
        }
    }

    func printUniforms() {
        for i in 0..<indexMap.count  {
            let key = indexMap[i]
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

        let metadataRegex = /\s?(\w+)\s+(\w+).+@uniform/

        var index = 0
        for line in lines {
            if let firstMatch = line.firstMatch(of: metadataRegex) {
                index = setIndex(name: String(firstMatch.2))
            }
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
