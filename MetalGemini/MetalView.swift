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



    class Coordinator: NSObject, MTKViewDelegate {
        var model: RenderDataModel
        var parent: MetalView
        var metalDevice: MTLDevice!
        var metalCommandQueue: MTLCommandQueue!
        var pipelineStates: [MTLRenderPipelineState]
        var finalPipelineState: MTLRenderPipelineState?
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
            guard let fragTransFunction = library.makeFunction(name: "fragTransShader") else {
                fatalError("Could not find fragTransShader function")
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
                } catch {
                    print("Couldn't load shader library at \(metalLibURL)\n\(error)")
                    DispatchQueue.main.async {
                        self.model.shaderError = "\(error)"
                    }
                }
            }


            do {
                for i in 0..<MAX_RENDER_BUFFERS {

                    guard let fragmentFunction = library.makeFunction(name: "fragmentShader\(i)") else {
                        print("Could not find fragmentShader\(i)")
                        print("Stopping search.")
                        continue
                    }
                    // Create a render pipeline state
                    let pipelineDescriptor = MTLRenderPipelineDescriptor()
                    pipelineDescriptor.vertexFunction = vertexFunction
                    pipelineDescriptor.fragmentFunction = fragmentFunction
                    pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Unorm

                    pipelineStates.append( try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )
                    numBuffers = i+1
                    print("numBuffers: \(numBuffers)")
                }
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexFunction = vertexFunction
                pipelineDescriptor.fragmentFunction = fragTransFunction
                pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                finalPipelineState = ( try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor) )

                print("shaders loaded")
                DispatchQueue.main.async {
                    self.updateVSyncState(self.model.vsyncOn) // renable offline rendering if vsync is false
                }
            } catch {
                 print("Failed to setup shaders: \(error)")
            }
            if numBuffers < 1 {
                fatalError("Must have at least one fragment shader named `fragmentShader0`.")
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
            viewportSizeBuffer = metalDevice.makeBuffer(length: MemoryLayout<ViewportSize>.size, options: .storageModeShared)
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

        func updateUniforms(passNum:UInt32) throws {
            var bufferPointer = frameCounterBuffer!.contents()
            memcpy(bufferPointer, &frameCounter, MemoryLayout<UInt32>.size)
            bufferPointer = timeIntervalBuffer!.contents()
            var elapsedTime = Float(-startDate.timeIntervalSinceNow)
            memcpy(bufferPointer, &elapsedTime, MemoryLayout<Float>.size)
            bufferPointer = passNumBuffer!.contents()
            var pNum = passNum
            memcpy(bufferPointer, &pNum, MemoryLayout<UInt32>.size)
            try uniformManager.mapUniformsToBuffer()
        }


        func setupRenderEncoder( _ encoder: MTLRenderCommandEncoder, _ passNum: UInt32 ) {
            for i in 0..<MAX_RENDER_BUFFERS {
                encoder.setFragmentTexture(renderBuffers[i], index: i)
            }

            do {
                try updateUniforms(passNum:passNum)
                encoder.setFragmentBuffer(viewportSizeBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(frameCounterBuffer, offset: 0, index: 1)
                encoder.setFragmentBuffer(timeIntervalBuffer, offset: 0, index: 2)
                encoder.setFragmentBuffer(passNumBuffer, offset: 0, index: 3)
                encoder.setFragmentBuffer(uniformManager.buffer, offset: 0, index: 4)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            } catch {
                print("Failed to setup render encoder: \(error)")
            }
        }

        @objc private func renderOffscreen() {
            renderQueue.async { [weak self] in
                guard let self = self else { return }
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
                    setupRenderEncoder(commandEncoder, 0)
                    commandEncoder.endEncoding()

                    i += 1
                }

                // This is the most optimal way I found to do offline rendering
                // as quickly as possible.  The drawback is that slower renderings
                // like circle_and_lines don't display smoothly even though
                // framerates are faster than 60Hz.
                if( !model.vsyncOn ) {
                    commandBuffer.addScheduledHandler { commandBuffer in
                        self.frameCounter += 1
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

            if( model.vsyncOn ) { renderOffscreen() }
            guard finalPipelineState != nil else { return }
            guard let drawable = view.currentDrawable,
                  let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

            let renderPassDescriptor = view.currentRenderPassDescriptor!

            // renderPassDescriptor.colorAttachments[0].texture = renderBuffers[numBuffers-1]
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.colorAttachments[0].storeAction = .store

            guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

            commandEncoder.setRenderPipelineState(finalPipelineState!)
            commandEncoder.setFragmentTexture(renderBuffers[numBuffers-1], index: 0)
            commandEncoder.setFragmentBuffer(viewportSizeBuffer, offset: 0, index: 0)
            commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

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
