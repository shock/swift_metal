//
//  MetalView.swift
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

import SwiftUI
import MetalKit

struct ViewportSize {
    var width: Float
    var height: Float
}

public let MAX_RENDER_BUFFERS = 1

struct MetalView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60

        if let metalDevice = MTLCreateSystemDefaultDevice() {
            mtkView.device = metalDevice
        }
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.drawableSize = mtkView.frame.size
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        print("updateNSView called")
    }
    
    func sizeThatFits( _ proposal: ProposedViewSize, 
                       nsView: Self.NSViewType,
                       context: Self.Context ) -> CGSize? {
        return nil
//        return CGSizeMake(600,400)
    }


    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var pass1PipelineState: MTLRenderPipelineState!
        var pass2PipelineState: MTLRenderPipelineState!
        var viewportSizeBuffer: MTLBuffer?
        var frameCounter: UInt32
        var frameCounterBuffer: MTLBuffer?
        var startDate: Date!
        var timeIntervalBuffer: MTLBuffer?
        var renderBuffers: [MTLTexture?]

        init(_ parent: MetalView) {
            self.parent = parent
            self.startDate = Date()
            self.frameCounter = 0
            self.renderBuffers = []
            super.init()

            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!
            
            
            // Load the shader and create the pipeline state
            setupShaders() // You'll implement this function
        }

        func setupShaders() {
            // 1. Load the Metal library
            guard let library = metalDevice.makeDefaultLibrary() else {
                fatalError("Could not load default Metal library")
            }
            do {

                // 2. Get the shader function
                guard let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
                    fatalError("Could not find pixelShader function")
                }

                guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
                    fatalError("Could not find vertexShader function")
                }

                // 3. Create a render pipeline state
                var pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunction
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                pass1PipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)

                // 2. Get the shader function
                guard let fragmentFunction = library.makeFunction(name: "contrastFilter") else {
                    fatalError("Could not find contrastShader function")
                }

                guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
                    fatalError("Could not find vertexShader function")
                }

                // 3. Create a render pipeline state
                pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunction
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                pass2PipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                 print("Failed to setup shaders: \(error)")
            }
        }

        

        func createRenderBuffer(_ size: CGSize) -> MTLTexture {
            let offscreenTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                                width: Int(size.width), 
                                                                                height: Int(size.height), 
                                                                                mipmapped: false)
            offscreenTextureDescriptor.usage = [.renderTarget, .shaderRead]
            let buffer = metalDevice.makeTexture(descriptor: offscreenTextureDescriptor)!
            return buffer
        }

        func setupRenderBuffers(_ size: CGSize) {
            // dealloc old buffers
            renderBuffers.removeAll()
            // Create the offscreen texture for pass 1
            for _ in 0...MAX_RENDER_BUFFERS {
                renderBuffers.append(createRenderBuffer(size))
            }
        }
        
        func updateViewportSize(_ size: CGSize) {
            var viewportSize = ViewportSize(width: Float(size.width), height: Float(size.height))
            viewportSizeBuffer = metalDevice.makeBuffer(bytes: &viewportSize, length: MemoryLayout<ViewportSize>.size, options: [])
            frameCounter = 0
            startDate = Date()
            setupRenderBuffers(size)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            updateViewportSize(size);
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = metalCommandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
                //   let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) 

            frameCounterBuffer = metalDevice.makeBuffer(bytes: &frameCounter, length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            var elapsedTime = Float(-startDate.timeIntervalSinceNow)
            timeIntervalBuffer = metalDevice.makeBuffer(bytes: &elapsedTime, length: MemoryLayout<Float>.size, options: .storageModeShared)
            // ... inside draw(in:) of your Coordinator ...

            // Pass 1: Render to the offscreen texture
            let pass1Descriptor = MTLRenderPassDescriptor()
            pass1Descriptor.colorAttachments[0].texture = renderBuffers[0]
            pass1Descriptor.colorAttachments[0].loadAction = .clear
            pass1Descriptor.colorAttachments[0].storeAction = .store
            pass1Descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0) // Clear to transparent

            guard let pass1Encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass1Descriptor) else { return }

            pass1Encoder.setRenderPipelineState(pass1PipelineState)
            // pass the viewport dimensions to the fragment shader (u_resolution)
            pass1Encoder.setFragmentBuffer(viewportSizeBuffer, offset: 0, index: 0)

            // pass the frame number to the fragment shader (u_frame)
            pass1Encoder.setFragmentBuffer(frameCounterBuffer, offset: 0, index: 1)

            // pass ellapsed time to fragment shader (u_time)
            pass1Encoder.setFragmentBuffer(timeIntervalBuffer, offset: 0, index: 2)
            pass1Encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            pass1Encoder.endEncoding()

            // Pass 2: Render to a new render pass, processing the offscreen texture
            let pass2Descriptor = MTLRenderPassDescriptor()
            pass2Descriptor.colorAttachments[0].texture = view.currentDrawable!.texture // Render to screen
            pass2Descriptor.colorAttachments[0].loadAction = .clear
            pass2Descriptor.colorAttachments[0].storeAction = .store

            guard let pass2Encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass2Descriptor) else { return }

            pass2Encoder.setRenderPipelineState(pass2PipelineState)
            pass2Encoder.setFragmentTexture(renderBuffers[0], index: 0)
            // pass the viewport dimensions to the fragment shader (u_resolution)
            pass2Encoder.setFragmentBuffer(viewportSizeBuffer, offset: 0, index: 0)

            // pass the frame number to the fragment shader (u_frame)
            pass2Encoder.setFragmentBuffer(frameCounterBuffer, offset: 0, index: 1)

            // pass ellapsed time to fragment shader (u_time)
            pass2Encoder.setFragmentBuffer(timeIntervalBuffer, offset: 0, index: 2)
            pass2Encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            pass2Encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            frameCounter += 1

        }
    }
}
