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
    var uniformBuffer: MTLBuffer?
    var numBuffers: Int = -1
}

class MetalResourceManager {
    var metalDevice: MTLDevice!
    private var projectDirDelegate: ShaderProjectDirAccess!

    private var mtlTexturesDbl: [[MTLTexture]] = [[],[]]
    private var mtlTexturesCI = 0
    private var renderBuffersDbl: [[MTLTexture]] = [[],[]]
    private var renderBuffersCI = 0
    private var uniformBufferDbl: [MTLBuffer?]
    private var uniformBufferCI = 0
    private var numBuffersDbl: [Int] = [-1,-1]
    private var numBuffersCI = 0
    private var pipelineStatesDbl: [[MTLRenderPipelineState]] = [[],[]]
    private var pipelineStatesCI = 0
    private var serialRunner = SerialRunner()

    private var debug = true
    private var textureDictionary = [Int: MTLTexture]()  // Temporary dictionary to store textures with their index

    init(projectDirDelegate: ShaderProjectDirAccess) {
        self.projectDirDelegate = projectDirDelegate
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        } else {
            fatalError("Metal not supported on this computer.")
        }
        let buffer = metalDevice.makeBuffer(length: 16, options: .storageModeShared)
        uniformBufferDbl = [buffer, buffer]

    }

    func setUniformBuffer(_ buffer: MTLBuffer?) {
        if( buffer == nil ) {
            print("here")
        }
        uniformBufferDbl[1-uniformBufferCI] = buffer
    }

    func setError(_ err: String ) throws {
        numBuffersDbl[1-numBuffersCI] = -1
        print("BufferManager error: \(err)")
        throw err
    }

    func loadTextures(textureURLs: [URL]) async throws {
        textureDictionary = [Int: MTLTexture]()  // Temporary dictionary to store textures with their index
        let textureLoader = MTKTextureLoader(device: metalDevice)
        let options: [MTKTextureLoader.Option : Any] = [
            .origin : MTKTextureLoader.Origin.bottomLeft,
            .generateMipmaps: true,
            .SRGB : false
        ]

        var errors: [String] = []
        mtlTexturesDbl[1-mtlTexturesCI].removeAll()  // Clear existing textures

        await withTaskGroup(of: String?.self) { group in
            for (index, url) in textureURLs.enumerated() {
                group.addTask {
                    do {
                        let texture = try await textureLoader.newTexture(URL: url, options: options)
                        await self.serialRunner.run{
                            await self.addTexture(texture, at: index)
                        }
                        print("Texture loaded successfully: \(url.lastPathComponent)")
                        return nil
                    } catch {
                        let errorDescription = error.localizedDescription
                        if self.debug { print(errorDescription) }
                        return "Error loading texture: \(errorDescription)"
                    }
                }
            }

            // Collect non-nil results
            for await result in group {
                if let validString = result {
                    errors.append(validString)
                }
            }

        }

        updateTextureArray(sortedBy: textureURLs.count)

        if errors.isEmpty { return } else {
            throw errors.joined(separator: "\n")
        }
    }

    private func addTexture(_ texture: MTLTexture, at index: Int) async {
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

    func setupPipelines(metallibURL: URL?) async throws {
        guard let metalDevice = metalDevice else { throw "Metal Device not available." }
        print("BufferManager: setupPipelines() on thread")

        numBuffersDbl[1-numBuffersCI] = 0
        pipelineStatesDbl[1-pipelineStatesCI].removeAll()

        // Load the default Metal library
        guard var library = metalDevice.makeDefaultLibrary() else {
            let error = "Could not load default Metal library"
            try setError(error)
            return
        }
        
        // Load the default vertex shader
        guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
            let error = "Could not find 'vertexShader' function"
            try setError(error)
            return
        }

        if let metalLibURL = metallibURL {
            do {
                let tryLibrary = try metalDevice.makeLibrary(URL: metalLibURL)
                library = tryLibrary

                // asynchronously delete the metallib file now that we're done with it
                let command = "rm \(metalLibURL.path)"
                Task { let _ = shell_exec(command, cwd: nil) }
            } catch {
                 let error = "Couldn't load shader library at \(metalLibURL)\n\(error)"
                 try setError(error)
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
                 let error = "Shader must define at least one fragment shader named `fragmentShader0`"
                 try setError(error)
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
             let error = "Failed to setup shaders: \(error)"
             try setError(error)
        }
    }

    // swap the current index on all resources except
    // renderBuffers which swaps itself independently due to resize
    func swapCurrentResources() {
        DispatchQueue.main.async {
            self.mtlTexturesCI = 1 - self.mtlTexturesCI
            self.numBuffersCI = 1 - self.numBuffersCI
            self.pipelineStatesCI = 1 - self.pipelineStatesCI
            self.uniformBufferCI = 1 - self.uniformBufferCI
        }
    }

    func getCurrentResources() -> RenderResources {
        let result = RenderResources(renderBuffers: renderBuffersDbl[renderBuffersCI],
                                     mtlTextures: mtlTexturesDbl[mtlTexturesCI],
                                     pipelineStates: pipelineStatesDbl[pipelineStatesCI],
                                     uniformBuffer: uniformBufferDbl[uniformBufferCI],
                                     numBuffers: numBuffersDbl[numBuffersCI])
        return result
    }

}
