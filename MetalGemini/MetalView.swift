//
//  MetalView.swift
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

import SwiftUI
import MetalKit

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

    func updateNSView(_ nsView: MTKView, context: Context) {}

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var metalPipelineState: MTLRenderPipelineState!

        init(_ parent: MetalView) {
            self.parent = parent
            super.init()

            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!

            // Load the shader and create the pipeline state
            setupShader() // You'll implement this function
        }

        func setupShader() {
            do {
                // 1. Load the Metal library
                guard let library = metalDevice.makeDefaultLibrary() else {
                    fatalError("Could not load default Metal library")
                }

                // 2. Get the shader function
                guard let pixelFunction = library.makeFunction(name: "pixelShader") else {
                    fatalError("Could not find pixelShader function")
                }

                // 3. Create a render pipeline state
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = nil  // No vertex processing
                pipelineDescriptor.fragmentFunction = pixelFunction
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Adjust if needed

                metalPipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                 print("Failed to setup shader: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = metalCommandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

            renderEncoder.setRenderPipelineState(metalPipelineState)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
