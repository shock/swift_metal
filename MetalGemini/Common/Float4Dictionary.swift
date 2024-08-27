//
//  Float4Dictionary.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/28/24.
//

import Foundation

// Extension for Array of Floats to easily convert array to SIMD4<Float>
extension Array where Element == Float
{
    // Convert the array to SIMD4<Float>, padding with zeros if necessary
    func toSIMD4() -> SIMD4<Float>? {
        var c = self
        while( c.count < 4 ) { c.append(0) } // Pad with zeros if less than 4 elements
        return SIMD4<Float>(c[0], c[1], c[2], c[3])
    }
}

extension SIMD4<Float> {
    func toArray() -> [Float] {
        return [self.x, self.y, self.z, self.w]
    }
}

// A thread-safe dictionary to manage SIMD4<Float> values with string keys
class Float4Dictionary
{
    private var semaphore = DispatchSemaphore(value: 1) // Ensures thread-safe access to the dictionary
    var map: [String: SIMD4<Float>] = [:]

    init() {}

    // Set a SIMD4<Float> value from an array of floats for the specified key
    func setTuple( _ key: String, values: [Float])
    {
        semaphore.wait()  // Lock access to ensure thread safety
        defer { semaphore.signal() }  // Unlock after operation
        let value = values.toSIMD4()
        map[key] = value
    }

    // Set a SIMD4<Float> value directly for the specified key
    func set( _ key: String, _ simd4: SIMD4<Float> )
    {
        semaphore.wait()
        defer { semaphore.signal() }
        map[key] = simd4
    }

    // Retrieve a SIMD4<Float> value for the specified key, or return a default value
    func get( _ key: String, _ defaultValue: SIMD4<Float> = SIMD4<Float>(0,0,0,0) ) -> SIMD4<Float>
    {
        semaphore.wait()
        defer { semaphore.signal() }
        return map[key, default: defaultValue]
    }

    // Retrieve the first component (Float) from a SIMD4<Float> for the specified key
    func getAsFloat( _ key: String, _ defaultValue: Float = 0 ) -> Float
    {
        semaphore.wait()
        defer { semaphore.signal() }
        guard let float4 = map[key] else { return defaultValue }
        return float4.x
    }

    // Retrieve the first two components (SIMD2<Float>) from a SIMD4<Float> for the specified key
    func getAsFloat2( _ key: String, _ defaultValue: SIMD2<Float> = SIMD2<Float>(0,0)) -> SIMD2<Float>
    {
        semaphore.wait()
        defer { semaphore.signal() }
        guard let float4 = map[key] else { return defaultValue }
        return SIMD2<Float>(float4.x,float4.y)
    }

    // Retrieve the first three components (SIMD3<Float>) from a SIMD4<Float> for the specified key
    func getAsFloat3( _ key: String, _ defaultValue: SIMD3<Float> = SIMD3<Float>(0,0,0)) -> SIMD3<Float>
    {
        semaphore.wait()
        defer { semaphore.signal() }
        guard let float4 = map[key] else { return defaultValue }
        return SIMD3<Float>(float4.x,float4.y,float4.z)
    }

    // Remove and return the SIMD4<Float> value for the specified key
    func delete( _ key: String ) -> SIMD4<Float>?
    {
        semaphore.wait()
        defer { semaphore.signal() }
        return map.removeValue(forKey: key)
    }

    // Clear all entries in the dictionary
    func clear() {
        semaphore.wait()
        defer { semaphore.signal() }
        map.removeAll()
    }
}
