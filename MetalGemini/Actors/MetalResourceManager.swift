//
//  MetalResourceManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/30/24.
//

import Foundation
import MetalKit

actor MetalResourceManager {
    var renderBuffers: [MTLTexture] = []
    var sysUniformBuffer: MTLBuffer?
    var version = 0
    var numBuffers = 0
    var metalDevice: MTLDevice!
    private var pipelineStates: [MTLRenderPipelineState] = []
    public private(set) var mtlTextures:[MTLTexture] = []

    init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
    }

    func setError(_ err: String ) -> String {
        numBuffers = -1
        print("BufferManager error: \(err)")
        return err
    }

    func setTextures( mtlTextures: [MTLTexture] ) {
        self.mtlTextures = mtlTextures
    }

    func clearTextures() {
        self.mtlTextures.removeAll()
    }

    func addTexture(mtlTexture: MTLTexture) {
        print("MetalResourceManager: adding texture")
        self.mtlTextures.append(mtlTexture)
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
        renderBuffers.removeAll()

        // Create new buffers
        for _ in 0..<numBuffers {
            renderBuffers.append(createRenderBuffer(size))
        }

        // Update version to indicate a new state of buffers
        version += 1
    }

    func getBuffers() -> ([MTLTexture], Int) {
        return (renderBuffers, numBuffers)
    }

    func setupPipelines(metallibURL: URL?) async -> String? {
        guard let metalDevice = metalDevice else { return "Metal Device not available." }
        print("BufferManager: setupPipelines() on thread")
//            stopRendering() // ensure offline rendering is disabled

        numBuffers = 0
        pipelineStates.removeAll()

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
            numBuffers = fragmentFunctions.count-1
            print("numBuffers: \(numBuffers)")
            assert(numBuffers >= 0)
            for i in 0..<numBuffers {
                // Create a render pipeline state
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunctions[i]
                pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Unorm

                pipelineStates.append( try await metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )
            }
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunctions[numBuffers]
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineStates.append( try await metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )

            print("MetalView: setupShaders() - shaders loaded")
        } catch {
            numBuffers = -1
            return setError("Failed to setup shaders: \(error)")
        }
        return nil
    }

    func getBuffersAndPipelines() -> ([MTLTexture], [MTLRenderPipelineState], Int) {
        return (renderBuffers, pipelineStates, numBuffers)
    }

}

