//
//  UniformManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/17/24.
//

import Foundation
import MetalKit
import AppKit

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
    var uniformsTxtURL: URL?
    var uniformProjectDirURL: URL?
    let bookmarkID = "com.wdoughty.metaltoy.projectdir"
    
    private var saveWorkItem: DispatchWorkItem?
    private var saveQueue = DispatchQueue(label: "net.wdoughty.saveUniformsQueue")

    init() {
    }
    
    func selectDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose a directory"
        openPanel.message = "Select a directory your project"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false

        openPanel.begin { (result) in
            if result == .OK {
                if let selectedPath = openPanel.url {
                    // Use this URL to access the directory
                    print("Directory selected: \(selectedPath.path)")
                    // Here you could store the URL as a security-scoped bookmark if needed
                    self.storeSecurityScopedBookmark(for: selectedPath, withIdentifier: self.bookmarkID)
                    self.uniformProjectDirURL = selectedPath
                }
            } else {
                print("User cancelled the open panel")
            }
        }
    }

    func storeSecurityScopedBookmark(for directory: URL, withIdentifier identifier: String) {
        do {
            let bookmarkData = try directory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(identifier)")
            print("Bookmark for \(identifier) saved successfully.")
        } catch {
            print("Failed to create bookmark for \(identifier): \(error)")
        }
    }

    func accessBookmarkedDirectory(withIdentifier identifier: String, using fileOperation: (URL) -> Void) {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(identifier)") else {
            print("No bookmark data found for \(identifier).")
            return
        }

        var isStale = false
        do {
            let bookmarkedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                print("Bookmark for \(identifier) is stale, need to refresh")
                // Optionally, handle refresh here or notify user
            } else {
                if bookmarkedURL.startAccessingSecurityScopedResource() {
                    // Execute the passed in file operation
                    fileOperation(bookmarkedURL)
                    bookmarkedURL.stopAccessingSecurityScopedResource()
                }
            }
        } catch {
            print("Error resolving bookmark for \(identifier): \(error)")
        }
    }


    func requestSaveUniforms() {
        saveWorkItem?.cancel() // Cancel the previous task if it exists
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveUniformsToFile()
        }

        // Schedule the save after a delay (e.g., 500 milliseconds)
        if let saveWorkItem = saveWorkItem {
            saveQueue.asyncAfter(deadline: .now() + 0.5, execute: saveWorkItem)
        }
    }

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

    func setUniformTuple( _ name: String, values: [Float], suppressSave:Bool = false)
    {
        float4dict.setTuple(name, values: values)
        dirty = true
        if( !suppressSave ) {
            // This debounces and schedules a save operation
            requestSaveUniforms()
        }
        if( debug ) { printUniforms() }
    }

    func setUniform( _ name: String, _ simd4: SIMD4<Float> )
    {
        float4dict.set(name, simd4)
        dirty = true
        requestSaveUniforms() // This debounces and schedules a save operation
    }

    func mapUniformsToBuffer() throws {
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
                throw "Bad data type: \(dataType)"
            }
        }
    }

    func printUniforms() {
        print(uniformsToString())
    }

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

    func saveUniformsToFile() {
        if( indexMap.count == 0 ) { return }
            
        guard let fileUrl = uniformsTxtURL else { return }
        let uniforms = uniformsToString()

        let bookmarkData = UserDefaults.standard.data(forKey: "bookmark_\(bookmarkID)")
        if( bookmarkData == nil ) {
            selectDirectory()
        }

        // Accessing the bookmark to perform file operations
        accessBookmarkedDirectory(withIdentifier: bookmarkID) { dirUrl in
            do {
                try uniforms.write(to: fileUrl, atomically: true, encoding: .utf8)
                print("Data written successfully to \(fileUrl.path)")
            } catch {
                print("Failed to save uniforms: \(error)")
                selectDirectory()
            }
        }

    }
    
    func loadUniformsFromFile() {
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

    private func getShaderSource(srcURL: URL) -> String?
    {
        let command = "cpp \(srcURL.path) 2> /dev/null"
        let execResult = shell_exec(command, cwd: nil)
        if execResult.exitCode != 0 {
            return nil
        }
        return execResult.stdOut
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
    func setupUniformsFromShader(metalDevice: MTLDevice, srcURL: URL) -> String?
    {
        resetMapping()
        guard
            let shaderSource = getShaderSource(srcURL: srcURL)
            else { return "Failed to read shader file: \(srcURL)" }

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
        loadUniformsFromFile()
        return nil
    }
}

//
//func promptUserForFileSave(completion: @escaping (URL?) -> Void) {
//    let savePanel = NSSavePanel()
//    savePanel.title = "Save Uniforms File"
//    savePanel.message = "Select a location to save the uniforms data:"
//    savePanel.showsResizeIndicator = true
//    savePanel.showsHiddenFiles = false
//    savePanel.canCreateDirectories = true
//    savePanel.allowedContentTypes = [.txt]  // Specify the file type
//    savePanel.nameFieldStringValue = "uniforms.txt"  // Default file name
//
//    savePanel.begin { response in
//        if response == .OK, let url = savePanel.url {
//            completion(url)
//        } else {
//            completion(nil)  // User canceled the save operation
//        }
//    }
//}
//
