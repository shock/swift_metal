//
//  MetalView.swift
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

import SwiftUI
import MetalKit
import SwiftOSC

struct ViewportSize {
    var width: Float
    var height: Float
}


public let MAX_RENDER_BUFFERS = 4


// we need this to get access to the inner class of MetalView
typealias MetalViewCoordinator = MetalView.Coordinator
// we need this because makeCoordinator gets called every time MetalView
// is hidden, and if we don't reuse an existing coordinator, a new and gets created
// which creates a new OSC server and starts ravaging the CPU
var existingCoordinator: MetalViewCoordinator?

struct MetalView: NSViewRepresentable {
    @ObservedObject var model: RenderDataModel // Reference the ObservableObject
    let retinaEnabled = false

    func makeCoordinator() -> Coordinator {
        if let coordinator = existingCoordinator {
            return coordinator
        }
        existingCoordinator = Coordinator(self, model: model)
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
        var model: RenderDataModel
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var pipelineStates: [MTLRenderPipelineState]
        var sysUniformBuffer: MTLBuffer?
        var frameCounter: UInt32
        var startDate: Date!
        var renderBuffers: [MTLTexture?]
        var numBuffers = 0
        var renderTimer: Timer?
        var renderingActive = true
        private let renderQueue = DispatchQueue(label: "com.yourapp.renderQueue")
        private var renderSemaphore = DispatchSemaphore(value: 1) // Allows 1 concurrent access
        private var oscServer: OSCServerManager!
        private var uniformManager = UniformManager()

        init(_ parent: MetalView, model: RenderDataModel ) {
            self.parent = parent
            self.startDate = Date()
            self.frameCounter = 0
            self.renderBuffers = []
            self.pipelineStates = []
            self.model = model
            super.init()
            model.coordinator = self
            oscServer = OSCServerManager(metalView: self)
            setupOSCServer()

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

        func setupOSCServer() {
            oscServer.startServer()
        }

        func recvOscMsg(_ message: OSCMessage) {
            // Handle incoming OSC message here

            let oscRegex = /[\/\d]*?(\w+).*/
            if let firstMatch = message.address.string.firstMatch(of: oscRegex) {
                let name = firstMatch.1
                var tuple:[Float] = []
                for argument in message.arguments {
                    if let float = argument as? Float {
                        tuple.append(float)
                    } else if let double = argument as? Double {
                        print("WARNING: \(name) sent \(double) as double")
                    }

                }
                uniformManager.setUniformTuple(String(name), values: tuple)

            }
//            print("Received OSC message: \(message.address.string), \(String(describing: message.arguments))")
        }

        func setupShaders(_ shaderFileURL: URL?) {
            stopRendering() // ensure offline rendering is disabled

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

                    // Setup the model to monitor updates to the shader file and/or any of it's includes.
                    // We do this even if the compilation failed, so if the error is corrected, we'll
                    // automatically retry compilation.
                    model.shaderURLs = urls
                    model.monitorShaderFiles()

                    if( compileResult.exitCode != 0 ) { throw compileResult.stdErr ?? "Unknown error" }
                    let tryLibrary = try metalDevice.makeLibrary(URL: metalLibURL)
                    library = tryLibrary
                    DispatchQueue.main.async {
                        self.model.shaderError = nil
                    }

                    // detect any uniform metadata in the shader source
                    uniformManager.resetMapping()
                    let error = uniformManager.setupUniformsFromShader(metalDevice: metalDevice!, srcURL: fileURL)
                    if( error != nil ) { throw error! }
//                    let appDelegate = NSApplication.shared.delegate as? AppDelegate
//                    if let view_u = uniformManager.getUniformFloat4("u_resolution") {
//                        appDelegate?.resizeWindow?(CGFloat(view_u.x), CGFloat(view_u.y))
//                    }
                    uniformManager.setUniformTuple("u_resolution", values: [Float(model.size.width), Float(model.size.height)],
                        suppressSave: true)
                } catch {
                    print("Couldn't load shader library at \(metalLibURL)\n\(error)")
                    DispatchQueue.main.async {
                        self.model.shaderError = "\(error)"
                    }
                    return
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
                    DispatchQueue.main.async {
                        self.model.shaderError = "Must have at least one fragment shader named `fragmentShader0`"
                    }
                    return
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

                print("shaders loaded")
                DispatchQueue.main.async {
                    self.updateVSyncState(self.model.vsyncOn) // renable offline rendering if vsync is false
                }
            } catch {
                DispatchQueue.main.async {
                    self.model.shaderError = "Failed to setup shaders: \(error)"
                }
                return
            }

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
            model.size.width = size.width
            model.size.height = size.height
            setupRenderBuffers(size)
            uniformManager.setUniformTuple("u_resolution", values: [Float(model.size.width), Float(model.size.height)])
        }

        func reloadShaders() {
            frameCounter = 0
            startDate = Date()
            model.reloadShaders = false
            model.resetFrame()
            setupRenderBuffers(model.size)
            setupShaders(model.selectedFile)
            print("shaders loading finished")
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderSemaphore.wait()  // wait until the resource is free to use
            defer { renderSemaphore.signal() }  // signal that the resource is free now
            updateViewportSize(size)
            frameCounter = 0
        }

        // Enable offscreen rendering
        func startRendering() {
            renderingActive = true
            renderOffscreen()
        }

        // Disable offscreen rendering
        func stopRendering() {
            renderingActive = false
        }

        func updateVSyncState(_ enabled: Bool) {
            // Update your rendering logic here based on the VSync state
            model.vsyncOn = enabled
            if enabled {
                stopRendering()
            } else {
                startRendering()
            }
        }

        func updateUniforms() throws {
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

            var elapsedTime = Float(-startDate.timeIntervalSinceNow)
            // Ensure the offset is aligned
            memAlign = MemoryLayout<Float>.alignment
            memSize = MemoryLayout<Float>.size
            offset = (offset + memAlign - 1) / memAlign * memAlign
            // Copy the data
            memcpy(bufferPointer.advanced(by: offset), &elapsedTime, memSize)
            // Update the offset
            offset += memSize


            var pNum = numBuffers
            // Ensure the offset is aligned
            memAlign = MemoryLayout<UInt32>.alignment
            memSize = MemoryLayout<UInt32>.size
            offset = (offset + memAlign - 1) / memAlign * memAlign
            // Copy the data
            memcpy(bufferPointer.advanced(by: offset), &pNum, memSize)
            // Update the offset
            offset += memSize

            try uniformManager.mapUniformsToBuffer()
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
                try updateUniforms()
                encoder.setFragmentBuffer(sysUniformBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(uniformManager.buffer, offset: 0, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } catch {
                print("Failed to setup render encoder: \(error)")
            }
        }

        @objc private func renderOffscreen() {
            renderQueue.async { [weak self] in
                guard let self = self else { return }
                guard self.numBuffers > 0 else { return }
                if( !renderingActive && !model.vsyncOn ) { return }

                self.renderSemaphore.wait()  // Ensure exclusive access to render buffers
                defer { self.renderSemaphore.signal() }  // Release the lock after updating

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
                    setupRenderEncoder(commandEncoder)
                    commandEncoder.endEncoding()

                    i += 1
                }

                // This is the most optimal way I found to do offline rendering
                // as quickly as possible.  The drawback is that slower renderings
                // like circle_and_lines don't display smoothly even though
                // framerates are faster than 60Hz.
                if( !model.vsyncOn ) {
                    commandBuffer.addScheduledHandler { commandBuffer in
                        self.renderOffscreen()
                    }
                }
                self.frameCounter += 1
                commandBuffer.commit()
            }
        }

        func draw(in view: MTKView) {
            renderSemaphore.wait()  // wait until the resource is free to use
            defer { renderSemaphore.signal() }  // signal that the resource is free now

            if( model.reloadShaders ) {
                reloadShaders()
            }
            
            guard pipelineStates.count - 1 == numBuffers else { return }
            if( model.vsyncOn ) { renderOffscreen() }
//            guard finalPipelineState != nil else { return }
            guard let drawable = view.currentDrawable,
                  let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

            let renderPassDescriptor = view.currentRenderPassDescriptor!

            // renderPassDescriptor.colorAttachments[0].texture = renderBuffers[numBuffers-1]
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = .store

            guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

            commandEncoder.setRenderPipelineState(pipelineStates[numBuffers])
            setupRenderEncoder(commandEncoder)
            commandEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            self.model.frameCount = self.frameCounter // right now, this will trigger a view update since the RenderModel's
            // frameCount is observed by ContentView
        }

        deinit { // Unfortunately, this doesn't get called even when the view disappears
            print( "Coordinator deinit")
            self.oscServer = nil
        }
    }
}
