//
//  MetalResourceManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/30/24.
//

import Foundation
import MetalKit

struct RenderResources {
    var renderBuffers: [MTLTexture] = []
    var mtlTextures: [MTLTexture] = []
    var pipelineStates: [MTLRenderPipelineState] = []
    var numBuffers: Int = -1
}
        
class MetalResourceManager {
    var metalDevice: MTLDevice!
    private var projectDirDelegate: ShaderProjectDirAccess!

    private var mtlTexturesDbl: [[MTLTexture]] = [[],[]]
    private var mtlTexturesCI = 0
    private var renderBuffersDbl: [[MTLTexture]] = [[],[]]
    private var renderBuffersCI = 0
    private var numBuffersDbl: [Int] = [0,0]
    private var numBuffersCI = 0
    private var pipelineStatesDbl: [[MTLRenderPipelineState]] = [[],[]]
    private var pipelineStatesCI = 0

    private var debug = true
    private var textureDictionary = [Int: MTLTexture]()  // Temporary dictionary to store textures with their index
    
    init(projectDirDelegate: ShaderProjectDirAccess) {
        self.projectDirDelegate = projectDirDelegate
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
    }

    func setError(_ err: String ) -> String {
        numBuffersDbl[1-numBuffersCI] = -1
        print("BufferManager error: \(err)")
        return err
    }

//    func loadTextures(textureURLs: [URL]) -> String? {
//        var errors:[String] = []
//
//        let textureLoader = MTKTextureLoader(device: metalDevice)
//        let options: [MTKTextureLoader.Option : Any] = [
//            .origin : MTKTextureLoader.Origin.bottomLeft,
//            .SRGB : false
//        ]
//
//        mtlTextures.removeAll()
//        for url in textureURLs {
//            projectDirDelegate.accessDirectory() { dirUrl in
//                textureLoader.newTexture(URL: url, options: options) { (texture, error) in
//                    guard let texture = texture else {
//                        errors.append("Error loading texture: \(error?.localizedDescription ?? "Unknown error")")
//                        if self.debug { print(error?.localizedDescription as Any) }
//                        return
//                    }
//
//                    self.mtlTextures.append(texture)
//                }
//            }
//        }
//        if errors.count > 0 { return errors.joined(separator: "\n") }
//        return nil
//    }

    func loadTextures(textureURLs: [URL]) -> String? {
        textureDictionary = [Int: MTLTexture]()  // Temporary dictionary to store textures with their index
        let textureLoader = MTKTextureLoader(device: metalDevice)
        let options: [MTKTextureLoader.Option : Any] = [
            .origin : MTKTextureLoader.Origin.bottomLeft,
            .generateMipmaps: true,
            .SRGB : false
        ]

        var errors: [String] = []
        let group = DispatchGroup()

        mtlTexturesDbl[1-mtlTexturesCI].removeAll()  // Clear existing textures
        
        for (index, url) in textureURLs.enumerated() {
            group.enter()
            projectDirDelegate.accessDirectory() { dirUrl in
                textureLoader.newTexture(URL: url, options: options) { (texture, error) in
                    defer { group.leave() }
                    if let texture = texture {
                        self.addTexture(texture, at: index)
                        print("Texture loaded successfully: \(url.lastPathComponent)")
                    } else {
                        let errorDescription = error?.localizedDescription ?? "Unknown error"
                        errors.append("Error loading texture: \(errorDescription)")
                        if self.debug { print(errorDescription) }
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.updateTextureArray(sortedBy: textureURLs.count)
        }

        if errors.count > 0 { return errors.joined(separator: "\n") }
        return nil
    }
    
    private func addTexture(_ texture: MTLTexture, at index: Int) {
        textureDictionary[index] = texture
    }
    
    private func updateTextureArray(sortedBy count: Int) {
        mtlTexturesDbl[1-mtlTexturesCI] = (0..<count).compactMap { textureDictionary[$0] }
    }

    func createRenderBuffer(_ size: CGSize) -> MTLTexture {
        let offscreenTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm,
                                                                            width: Int(size.width),
                                                                            height: Int(size.height),
                                                                            mipmapped: false)
        offscreenTextureDescriptor.usage = [.renderTarget, .shaderRead]
        let buffer = metalDevice.makeTexture(descriptor: offscreenTextureDescriptor)!
        return buffer
    }

    func createBuffers(numBuffers: Int, size: CGSize) {
        // Deallocate old buffers
        
        renderBuffersDbl[1-renderBuffersCI].removeAll()

        // Create new buffers
        for _ in 0..<numBuffers {
            renderBuffersDbl[1-renderBuffersCI].append(createRenderBuffer(size))
        }
        DispatchQueue.main.async {
            self.renderBuffersCI = 1 - self.renderBuffersCI
        }
    }

//    func getBuffers() -> ([MTLTexture], Int) {
//        return (renderBuffers, numBuffers)
//    }
//
    func setupPipelines(metallibURL: URL?) async -> String? {
        guard let metalDevice = metalDevice else { return "Metal Device not available." }
        print("BufferManager: setupPipelines() on thread")
//            stopRendering() // ensure offline rendering is disabled

        numBuffersDbl[1-numBuffersCI] = 0
        pipelineStatesDbl[1-pipelineStatesCI].removeAll()

        // Load the default Metal library
        guard var library = metalDevice.makeDefaultLibrary() else {
            return setError("Could not load default Metal library")
        }
        // Load the default vertex shader
        guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
            return setError("Could not find 'vertexShader' function")
        }

        if let metalLibURL = metallibURL {
            do {
                let tryLibrary = try metalDevice.makeLibrary(URL: metalLibURL)
                library = tryLibrary

                // asynchronously delete the metallib file now that we're done with it
                let command = "rm \(metalLibURL.path)"
                Task { let _ = shell_exec(command, cwd: nil) }
            } catch {
                return setError("Couldn't load shader library at \(metalLibURL)\n\(error)")
            }
        }

        var fragmentFunctions: [MTLFunction] = []

        do {
            for i in 0...MAX_RENDER_BUFFERS {

                guard let fragmentFunction = library.makeFunction(name: "fragmentShader\(i)") else {
                    print("Could not find fragmentShader\(i)")
                    print("Stopping search.")
                    continue
                }
                fragmentFunctions.append(fragmentFunction)
                print("fragmentShader\(i) found")
            }
            if fragmentFunctions.count < 1 {
                return setError("Shader must define at least one fragment shader named `fragmentShader0`")
            }
            numBuffersDbl[1-numBuffersCI] = fragmentFunctions.count-1
            print("numBuffers: \(numBuffersDbl[1-numBuffersCI])")
            assert(numBuffersDbl[1-numBuffersCI] >= 0)
            for i in 0..<numBuffersDbl[1-numBuffersCI] {
                // Create a render pipeline state
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunctions[i]
                pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Unorm

                pipelineStatesDbl[1-pipelineStatesCI].append( try await metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )
            }
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunctions[numBuffersDbl[1-numBuffersCI]]
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineStatesDbl[1-pipelineStatesCI].append( try await metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )

            print("MetalView: setupShaders() - shaders loaded")
        } catch {
            numBuffersDbl[1-numBuffersCI] = -1
            return setError("Failed to setup shaders: \(error)")
        }
        return nil
    }
    
    func swapNonBufferResources() {
        DispatchQueue.main.async {
            self.mtlTexturesCI = 1 - self.mtlTexturesCI
            self.numBuffersCI = 1 - self.numBuffersCI
            self.pipelineStatesCI = 1 - self.pipelineStatesCI
        }
    }

    func getCurrentResources() -> RenderResources {
        let result = RenderResources(renderBuffers: renderBuffersDbl[renderBuffersCI],
                                     mtlTextures: mtlTexturesDbl[mtlTexturesCI],
                                     pipelineStates: pipelineStatesDbl[pipelineStatesCI],
                                     numBuffers: numBuffersDbl[numBuffersCI])
        return result
    }

}

