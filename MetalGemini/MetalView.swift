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


// we need this to get access to the inner class of MetalView
typealias MetalViewCoordinator = MetalView.Coordinator
// we need this because makeCoordinator gets called every time MetalView
// is hidden (eg. shader error), and if we don't reuse an existing coordinator, a new one gets created
// which can allocate resources faster than they can be released during off-line rendering.  yuck.
var existingCoordinator: MetalViewCoordinator?

struct MetalView: NSViewRepresentable {
    @ObservedObject var renderMgr: RenderManager // Reference the ObservableObject
    let retinaEnabled = false

    func makeCoordinator() -> Coordinator {
        if let coordinator = existingCoordinator {
            return coordinator
        }
        existingCoordinator = Coordinator(self, renderMgr: renderMgr)
        return existingCoordinator!
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
        if( !retinaEnabled ) {
            // with mtkView.autoResizeDrawable = false, we have to do this
            // also, this is also how we avoid retina x2 texture sizes, which we may not always want to do
            if( mtkView.frame.size != mtkView.drawableSize ) {
                mtkView.drawableSize = mtkView.frame.size
                print("updateNSView: mtkView.drawableSize resized: \(mtkView.frame.size)")
            }
        }
    }

    func sizeThatFits( _ proposal: ProposedViewSize,
                       nsView: Self.NSViewType,
                       context: Self.Context ) -> CGSize? {
        return nil
    }


    struct SysUniforms {
        var vpSize: ViewportSize
        var frameCount: UInt32
        var timeInterval: Float
        var passNum: UInt32
    }

    class Coordinator: NSObject, MTKViewDelegate {
        private var renderMgr: RenderManager
        private var parent: MetalView
        public private(set) var metalDevice: MTLDevice!
        private var metalCommandQueue: MTLCommandQueue!
        private var pipelineStates: [MTLRenderPipelineState]
        private var sysUniformBuffer: MTLBuffer?
        private var frameCounter: UInt32
        private var renderBuffers: [MTLTexture?]
        private var numBuffers = 0
        private var renderTimer: Timer?
        private var renderingActive = false
        private var metallibURL: URL?
        private var reloadShaders = false

        private var renderWorkItem: DispatchWorkItem? // Work item for saving uniforms
        public private(set) var renderSync = RenderSynchronizer()
        private let renderQueue = DispatchQueue(label: "com.yourapp.renderQueue")

        init(_ parent: MetalView, renderMgr: RenderManager ) {
            self.parent = parent
            self.frameCounter = 0
            self.renderBuffers = []
            self.pipelineStates = []
            self.renderMgr = renderMgr
            self.renderSync = renderMgr.renderSync
            super.init()
            renderMgr.setCoordinator(self)

            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }
            self.metalCommandQueue = metalDevice.makeCommandQueue()!

            // must initialize render buffers
            createUniformBuffers()
            updateViewportSize(CGSize(width:2,height:2))

            // Load the default shaders and create the pipeline states
//            reinitShaders()

        }

        func setupShaders() -> String? {
            print("MetalView: setupShaders() on thread \(Thread.current)")
            stopRendering() // ensure offline rendering is disabled

            numBuffers = 0
            pipelineStates.removeAll()

            // Load the default Metal library
            guard var library = metalDevice.makeDefaultLibrary() else {
                return "Could not load default Metal library"
            }
            // Load the default vertex shader
            guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
                return "Could not find 'vertexShader' function"
            }

            if( metallibURL != nil ) {
                let metalLibURL = metallibURL!
                do {
                    let tryLibrary = try metalDevice.makeLibrary(URL: metalLibURL)
                    library = tryLibrary
                } catch {
                    return "Couldn't load shader library at \(metalLibURL)\n\(error)"
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
                }
                if fragmentFunctions.count < 1 {
                    return "Shader must define at least one fragment shader named `fragmentShader0`"
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

                    pipelineStates.append( try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )
                }
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragmentFunctions[numBuffers]
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                pipelineStates.append( try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )

                print("MetalView: setupShaders() - shaders loaded")
            } catch {
                return "Failed to setup shaders: \(error)"
            }
            return nil
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

        func setupRenderBuffers(_ size: CGSize) {
            print("MetalView: setupRenderBuffers(\(size)")
            // dealloc old buffers
            renderBuffers.removeAll()
            // Create the offscreen texture for pass 1
            for _ in 0..<MAX_RENDER_BUFFERS {
                renderBuffers.append(createRenderBuffer(size))
            }
        }

        func createUniformBuffers() {
            // 32 bytes is more than enough to hold SysUniforms, packed
            sysUniformBuffer = metalDevice.makeBuffer(length: 32, options: .storageModeShared)
        }

        func updateViewportSize(_ size: CGSize) {
            var viewportSize = ViewportSize(width: Float(size.width), height: Float(size.height))
            let bufferPointer = sysUniformBuffer!.contents()
            memcpy(bufferPointer, &viewportSize, MemoryLayout<ViewportSize>.size)
            renderMgr.setViewSize(size)
            renderMgr.resetFrame()
            setupRenderBuffers(size)
        }

        func loadShader(metallibURL: URL?) -> String? {
            print("MetalView: loadShader() on thread \(Thread.current)")
            renderWorkItem?.cancel()
            self.metallibURL = metallibURL
            return reinitShaders()
        }

        func reinitShaders() -> String? {
            print("MetalView: reinitShaders() on thread \(Thread.current)")
            frameCounter = 0
            return setupShaders()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            Task {
                await renderSync.run {
                    self.updateViewportSize(size)
                    self.frameCounter = 0
                }
            }
        }

        // Enable offscreen rendering
        func startRendering() {
            print("MetalView: startRendering()")
            renderingActive = true
            renderOffscreen()
        }

        // Disable offscreen rendering
        func stopRendering() {
            print("MetalView: stopRendering()")
            renderingActive = false
        }

        func updateVSyncState(_ enabled: Bool) {
            // Update your rendering logic here based on the VSync state
            if enabled {
                stopRendering()
            } else {
                startRendering()
            }
        }

        func updateUniforms() {
            var offset = MemoryLayout<ViewportSize>.size // for viewport
            let bufferPointer = sysUniformBuffer!.contents()

            // Ensure the offset is aligned
            var memAlign = MemoryLayout<UInt32>.alignment
            var memSize = MemoryLayout<UInt32>.size
            offset = (offset + memAlign - 1) / memAlign * memAlign
            // Copy the data
            memcpy(bufferPointer.advanced(by: offset), &frameCounter, memSize)
            // Update the offset
            offset += memSize

            var elapsedTime = Float(-renderMgr.startDate.timeIntervalSinceNow)
            memAlign = MemoryLayout<Float>.alignment
            memSize = MemoryLayout<Float>.size
            offset = (offset + memAlign - 1) / memAlign * memAlign
            memcpy(bufferPointer.advanced(by: offset), &elapsedTime, memSize)
            offset += memSize


            var pNum = numBuffers
            memAlign = MemoryLayout<UInt32>.alignment
            memSize = MemoryLayout<UInt32>.size
            offset = (offset + memAlign - 1) / memAlign * memAlign
            memcpy(bufferPointer.advanced(by: offset), &pNum, memSize)
            offset += memSize
        }


        func setupRenderEncoder( _ encoder: MTLRenderCommandEncoder ) {
            for i in 0..<MAX_RENDER_BUFFERS {
                encoder.setFragmentTexture(renderBuffers[i], index: i)
            }
            // pass a dynamic reference to the last buffer rendered, if there is one
            if numBuffers > 0 {
                encoder.setFragmentTexture(renderBuffers[numBuffers-1], index: MAX_RENDER_BUFFERS)
            }

            // now the first MAX_RENDER_BUFFERS+1 buffers are passed
            // it's up to the shaders how to use them

            do {
                updateUniforms()
                encoder.setFragmentBuffer(sysUniformBuffer, offset: 0, index: 0)
                let uniformBuffer = try renderMgr.uniformBuffer()
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } catch {
                print("Failed to setup render encoder: \(error.localizedDescription)")
            }
        }

        private func renderOffscreen() {
            renderWorkItem?.cancel() // Cancel the previous task if it exists
            renderWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.renderSync.run {
                        let renderMgr = self.renderMgr
                        let numBuffers = self.numBuffers
                        let pipelineStates = self.pipelineStates
                        guard self.numBuffers > 0 else { return }
                        if( !self.renderingActive && !renderMgr.vsyncOn ) { return }

                        guard let commandBuffer = self.metalCommandQueue.makeCommandBuffer() else { return }

                        var i=0

                        // iterate through the shaders, giving them each access to all of the buffers
                        // (see the pipeline setup)
                        while i < (numBuffers) {
                            let renderPassDescriptor = MTLRenderPassDescriptor()
                            renderPassDescriptor.colorAttachments[0].texture = self.renderBuffers[i]
                            renderPassDescriptor.colorAttachments[0].loadAction = .load
                            renderPassDescriptor.colorAttachments[0].storeAction = .store

                            guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

                            commandEncoder.setRenderPipelineState(pipelineStates[i])
                            self.setupRenderEncoder(commandEncoder)
                            commandEncoder.endEncoding()

                            i += 1
                        }

                        // This is the most optimal way I found to do offline rendering
                        // as quickly as possible.  The drawback is that slower renderings
                        // like circle_and_lines don't display smoothly even though
                        // framerates are faster than 60Hz.
                        if( !renderMgr.vsyncOn ) {
                            commandBuffer.addScheduledHandler { commandBuffer in
                                self.renderOffscreen()
                            }
                        }
                        self.frameCounter += 1
                        commandBuffer.commit()
                    }
                }
            }

            if let renderWorkItem = renderWorkItem {
                renderQueue.async(execute: renderWorkItem)
            }
        }

        func draw(in view: MTKView) {
            Task {
                await renderSync.run {
                    let renderMgr = self.renderMgr
                    let numBuffers = self.numBuffers
                    let pipelineStates = self.pipelineStates

                    guard !self.renderMgr.renderingPaused else { return }
                    guard pipelineStates.count - 1 == numBuffers else { return }

                    if( renderMgr.vsyncOn && numBuffers > 0 ) { self.renderOffscreen() } else { self.frameCounter += 1 }
                    guard let drawable = await view.currentDrawable,
                          let commandBuffer = self.metalCommandQueue.makeCommandBuffer() else { return }

                    let renderPassDescriptor = await view.currentRenderPassDescriptor!

                    // renderPassDescriptor.colorAttachments[0].texture = renderBuffers[numBuffers-1]
                    renderPassDescriptor.colorAttachments[0].loadAction = .load
                    renderPassDescriptor.colorAttachments[0].storeAction = .store

                    guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

                    commandEncoder.setRenderPipelineState(pipelineStates[numBuffers])
                    self.setupRenderEncoder(commandEncoder)
                    commandEncoder.endEncoding()

                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                }
            }
            // renderMgr.frameCount is observed by ContentView forcing redraw
            self.renderMgr.frameCount = self.frameCounter // right now, this will trigger a view update since the RenderModel's
        }

    }
}
