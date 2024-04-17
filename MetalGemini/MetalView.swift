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

public let MAX_RENDER_BUFFERS = 4

struct MetalView: NSViewRepresentable {
    @ObservedObject var model: RenderDataModel // Reference the ObservableObject
    func makeCoordinator() -> Coordinator {
        Coordinator(self, model: model)
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
        mtkView.autoResizeDrawable = true  // setting this to false requires updateNSView to update the view's drawableSize
        return mtkView
    }

    func updateNSView(_ mtkView: MTKView, context: Context) {
        // with mtkView.autoResizeDrawable = false, we have to do this
        // this is also how we avoid retina x2 texture sizes, which we may not always want to do
        if( mtkView.frame.size != mtkView.drawableSize ) {
            mtkView.drawableSize = mtkView.frame.size
            print("updateNSView: mtkView.drawableSize resized: \(mtkView.frame.size)")
        }
    }

    func sizeThatFits( _ proposal: ProposedViewSize,
                       nsView: Self.NSViewType,
                       context: Self.Context ) -> CGSize? {
        return nil
    }


    class Coordinator: NSObject, MTKViewDelegate {
        var model: RenderDataModel
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var pipelineStates: [MTLRenderPipelineState]
        var viewportSizeBuffer: MTLBuffer?
        var frameCounterBuffer: MTLBuffer?
        var timeIntervalBuffer: MTLBuffer?
        var passNumBuffer: MTLBuffer?
        var frameCounter: UInt32
        var startDate: Date!
        var renderBuffers: [MTLTexture?]
        var numBuffers = 0
        var renderTimer: Timer?
        var renderingActive = true
        private let renderQueue = DispatchQueue(label: "com.yourapp.renderQueue")
        private var renderSemaphore = DispatchSemaphore(value: 1) // Allows 1 concurrent access


        init(_ parent: MetalView, model: RenderDataModel ) {
            self.parent = parent
            self.startDate = Date()
            self.frameCounter = 0
            self.renderBuffers = []
            self.pipelineStates = []
            self.model = model
            super.init()
            model.coordinator = self

            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!


            // Load the default shaders and create the pipeline states
            setupShaders(nil)
            createUniformBuffers()

            // must initialize render buffers
            updateViewportSize(CGSize(width:2,height:2))
        }

        func setupShaders(_ shaderFileURL: URL?) {
            numBuffers = 0
            pipelineStates.removeAll()

            // Load the default Metal library
            guard var library = metalDevice.makeDefaultLibrary() else {
                fatalError("Could not load default Metal library")
            }
            // Load the default vertex shader
            guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
                fatalError("Could not find vertexShader function")
            }

            if( shaderFileURL != nil ) {
                let fileURL = shaderFileURL!
                let metalLibURL = fileURL.deletingPathExtension().appendingPathExtension("metallib")
                do {
                    let compileResult = metalToAir(srcURL: fileURL)
                    let paths = compileResult.stdOut!.components(separatedBy: "\n")
                    var urls: [URL] = []
                    for path in paths {
                        if path != "" {
                            let url = URL(fileURLWithPath: path)
                            urls.append(url)
                        }
                    }
                    model.shaderURLs = urls
                    model.monitorShaderFiles()

                    if( compileResult.stdErr != nil ) { throw compileResult.stdErr! }
                    let tryLibrary = try metalDevice.makeLibrary(URL: metalLibURL)
                    library = tryLibrary
                    model.shaderError = nil
                } catch {
                    print("Couldn't load shader library at \(metalLibURL)\n\(error)")
                    model.shaderError = "\(error)"
                }
            }

            do {
                    for i in 0..<MAX_RENDER_BUFFERS {

                    guard let fragmentFunction = library.makeFunction(name: "fragmentShader\(i)") else {
                        print("Could not find fragmentShader\(i)")
                        print("Stopping search.")
                        return
                    }
                    // Create a render pipeline state
                    let pipelineDescriptor = MTLRenderPipelineDescriptor()
                    pipelineDescriptor.vertexFunction = vertexFunction
                    pipelineDescriptor.fragmentFunction = fragmentFunction
                    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                    pipelineStates.append( try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )
                    numBuffers = i+1
                    print("numBuffers: \(numBuffers)")
                }
            } catch {
                 print("Failed to setup shaders: \(error)")
            }
            if numBuffers < 1 {
                fatalError("Must have at least one fragment shader named `fragmentShader0`.")
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
            for _ in 0..<MAX_RENDER_BUFFERS {
                renderBuffers.append(createRenderBuffer(size))
            }
        }

        func createUniformBuffers() {
            viewportSizeBuffer = metalDevice.makeBuffer(length: MemoryLayout<ViewportSize>.size, options: [])
            frameCounterBuffer = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            timeIntervalBuffer = metalDevice.makeBuffer(length: MemoryLayout<Float>.size, options: .storageModeShared)
            passNumBuffer = metalDevice.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
        }

        func updateViewportSize(_ size: CGSize) {
            var viewportSize = ViewportSize(width: Float(size.width), height: Float(size.height))
            let bufferPointer = viewportSizeBuffer!.contents()
            memcpy(bufferPointer, &viewportSize, MemoryLayout<ViewportSize>.size)
            model.size.width = size.width
            model.size.height = size.height
            setupRenderBuffers(size)
        }

        func reloadShaders() {
            frameCounter = 0
            startDate = Date()
            model.reloadShaders = false
            model.resetFrame()
            setupRenderBuffers(model.size)
            setupShaders(model.selectedFile)
            print("shaders loaded successfully")
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderSemaphore.wait()  // wait until the resource is free to use
            defer { renderSemaphore.signal() }  // signal that the resource is free now
            print("drawableSizeWillChange size: \(size)")
            updateViewportSize(size)
            frameCounter = 0
        }

        // Setup the timer to trigger offscreen rendering
        func startRendering() {
            renderingActive = true
            renderOffscreen()
        }

        // Cancel the timer to trigger offscreen rendering
        func stopRendering() {
            renderingActive = false
        }

        func updateUniforms(passNum:UInt32) {
            var bufferPointer = frameCounterBuffer!.contents()
            memcpy(bufferPointer, &frameCounter, MemoryLayout<UInt32>.size)
            bufferPointer = timeIntervalBuffer!.contents()
            var elapsedTime = Float(-startDate.timeIntervalSinceNow)
            memcpy(bufferPointer, &elapsedTime, MemoryLayout<Float>.size)
            bufferPointer = passNumBuffer!.contents()
            var pNum = passNum
            memcpy(bufferPointer, &pNum, MemoryLayout<UInt32>.size)
        }


        func setupRenderEncoder( _ encoder: MTLRenderCommandEncoder, _ passNum: UInt32 ) {
            for i in 0..<MAX_RENDER_BUFFERS {
                encoder.setFragmentTexture(renderBuffers[i], index: i)
            }

            // frameCounterBuffer = metalDevice.makeBuffer(bytes: &frameCounter, length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            // var elapsedTime = Float(-startDate.timeIntervalSinceNow)
            // timeIntervalBuffer = metalDevice.makeBuffer(bytes: &elapsedTime, length: MemoryLayout<Float>.size, options: .storageModeShared)

            updateUniforms(passNum:passNum)
            // pass the viewport dimensions to the fragment shader (u_resolution)
            encoder.setFragmentBuffer(viewportSizeBuffer, offset: 0, index: 0)

            // pass the frame number to the fragment shader (u_frame)
            encoder.setFragmentBuffer(frameCounterBuffer, offset: 0, index: 1)

            // pass ellapsed time to fragment shader (u_time)
            encoder.setFragmentBuffer(timeIntervalBuffer, offset: 0, index: 2)

            // pass the render pass number
//            var pNum = passNum
            // passNumBuffer = metalDevice.makeBuffer(bytes: &pNum, length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            encoder.setFragmentBuffer(passNumBuffer, offset: 0, index: 3)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        }

        @objc private func renderOffscreen() {
            renderQueue.async { [weak self] in
                guard let self = self else { return }
                if( !renderingActive ) { return }

                self.renderSemaphore.wait()  // Ensure exclusive access to render buffers
                defer { self.renderSemaphore.signal() }  // Release the lock after updating

                if( model.reloadShaders ) {
                    reloadShaders()
                }
                guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

                var i=0

                // iterate through the shaders, giving them each access to all of the buffers
                // (see the pipeline setup)
                while i < (numBuffers) {
                    let renderPassDescriptor = MTLRenderPassDescriptor()
                    renderPassDescriptor.colorAttachments[0].texture = renderBuffers[i]
                    renderPassDescriptor.colorAttachments[0].loadAction = .load
                    renderPassDescriptor.colorAttachments[0].storeAction = .store

                    guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

                    commandEncoder.setRenderPipelineState(pipelineStates[i])
                    setupRenderEncoder(commandEncoder, 0)
                    commandEncoder.endEncoding()

                    i += 1
                }
                //            commandBuffer.present(drawable)
                
                commandBuffer.addScheduledHandler { commandBuffer in
                    self.frameCounter += 1
                    self.renderOffscreen()
                }
                commandBuffer.commit()
            }
        }

        func draw(in view: MTKView) {
            renderSemaphore.wait()  // wait until the resource is free to use
            defer { renderSemaphore.signal() }  // signal that the resource is free now

            if( model.reloadShaders ) {
                reloadShaders()
            }
            guard let drawable = view.currentDrawable,
                  let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

            // blit the last buffer to the drawable.  this is very fast!
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
            let lastRenderedBuffer:MTLTexture = renderBuffers[numBuffers-1]!

            blitEncoder.copy(from: lastRenderedBuffer,
                            sourceSlice: 0,
                            sourceLevel: 0,
                            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                            sourceSize: MTLSize(width: lastRenderedBuffer.width, height: lastRenderedBuffer.height, depth: 1),
                            to: drawable.texture,
                            destinationSlice: 0,
                            destinationLevel: 0,
                            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blitEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            model.frameCount = frameCounter // right now, this will trigger a view update since the RenderModel is
                                            // observed by ContentView
        }
    }
}
