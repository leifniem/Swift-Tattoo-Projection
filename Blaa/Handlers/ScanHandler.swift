/*
 Added functionality added by @ryanphilly
 */

import Metal
import MetalKit
import ARKit

// MARK: - Core Metal Scan Renderer
final class ScanHandler : RenderingHelper{
    var savedCloudURLs = [URL]()
    private var cpuParticlesBuffer = [CPUParticle]()
    private var viewMatrixBuffer = [matrix_float4x4]()
    private var videoBuffer = [CVPixelBuffer]()
    //    private var framesBuffer = [MTLTexture]()
    private let writeLockFlag = CVPixelBufferLockFlags.init(rawValue: 0)
    var bufferCurrentFrame = 0
    var isCollectingData = false
    var isInViewSceneMode = true
    // Maximum number of points we store in the point cloud
    private let maxPoints = 15_000_000
    // Number of sample points on the grid
    private var numGridPoints = 1_000
    // Particle's size in pixels
    private let particleSize: Float = 8
    // We only use landscape orientation in this app
    private let orientation = UIInterfaceOrientation.portrait
    // Camera's threshold values for detecting when the camera moves so that we can accumulate the points
    private let cameraRotationThreshold = cos(0.5 * .degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.20, 2)   // (meter-squared)
    // The max number of command buffers in flight
    private let maxInFlightBuffers = 5
//    let videoTextureDescriptor = MTLTextureDescriptor()
    private var currentPointCount = 0
    
    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(orientation: orientation)
    private let session: ARSession
    
    // Metal objects and textures
    //    private let device: MTLDevice
    //    private let library: MTLLibrary
    //    private let renderDestination: RenderDestinationProvider
//    private let relaxedStencilState: MTLDepthStencilState
    private let depthStencilState: MTLDepthStencilState
    private var commandQueue: MTLCommandQueue
    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    // texture cache for captured image
    //    private lazy var textureCache = makeTextureCache(device: device)
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
//    private var currentFrameTex: MTLTexture?
    
    // Multi-buffer rendering pipeline
    private let inFlightSemaphore: DispatchSemaphore
    private var currentBufferIndex = 0
    
    // The current viewport size
    private var viewportSize = CGSize()
    // The grid of sample points
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device,
                                                            array: makeGridPoints(),
                                                            index: kGridPoints.rawValue, options: [])
    
    // RGB buffer
    private lazy var rgbUniforms: RGBUniforms = {
        var uniforms = RGBUniforms()
        uniforms.viewToCamera.copy(from: viewToCamera)
        uniforms.viewRatio = Float(viewportSize.width / viewportSize.height)
        return uniforms
    }()
    private var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    // Point Cloud buffer
    private lazy var pointCloudUniforms: PointCloudUniforms = {
        var uniforms = PointCloudUniforms()
        uniforms.maxPoints = Int32(maxPoints)
        uniforms.confidenceThreshold = Int32(confidenceThreshold)
        uniforms.particleSize = particleSize
        uniforms.cameraResolution = cameraResolution
        return uniforms
    }()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    // Particles buffer
    private var particlesBuffer: MetalBuffer<ParticleUniforms>
    private var currentPointIndex = 0
    
    // Camera data
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(sampleFrame.camera.imageResolution.width), Float(sampleFrame.camera.imageResolution.height))
    private lazy var viewToCamera = sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
    private lazy var lastCameraTransform = sampleFrame.camera.transform
    
    var confidenceThreshold: Float = 2
    
    var pointCount: Int {
        get {
            return currentPointCount
        }
    }
    
    var viewMatrixes: [matrix_float4x4] {
        get {
            return viewMatrixBuffer
        }
    }
    
    var videoData: [CVPixelBuffer] {
        get {
            return videoBuffer
        }
    }
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        //        self.device = device
        //        self.renderDestination = renderDestination
        //        library = device.makeDefaultLibrary()!
        
        commandQueue = device.makeCommandQueue()!
        // initialize our buffers
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
        }
        particlesBuffer = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
        
        // setup depth test for point cloud
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .lessEqual
        depthStateDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
        
//        videoTextureDescriptor.pixelFormat = .rgba32Float
//        videoTextureDescriptor.usage = [.shaderRead, .shaderWrite]
//        videoTextureDescriptor.allowGPUOptimizedContents = true
        
        //        currentFrameTex = device.makeTexture(descriptor: videoTextureDescriptor)
        
        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
        super.init(device: device, renderDestination: renderDestination)
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }
//        videoTextureDescriptor.width = pixelBuffer.getWidth(plane: 0)
//        videoTextureDescriptor.height = pixelBuffer.getHeight(plane: 0)
        capturedImageTextureY = textureFromPixelBuffer(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = textureFromPixelBuffer(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)
    }
    
    private func updateDepthTextures(frame: ARFrame) -> Bool {
        guard let depthMap = frame.smoothedSceneDepth?.depthMap,
              let confidenceMap = frame.smoothedSceneDepth?.confidenceMap else {
                  return false
              }
        
        depthTexture = textureFromPixelBuffer(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = textureFromPixelBuffer(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        
        return true
    }
    
    private func update(frame: ARFrame) {
        // frame dependent info
        let camera = frame.camera
        let cameraIntrinsicsInversed = camera.intrinsics.inverse
        let viewMatrix = camera.viewMatrix(for: orientation)
        let viewMatrixInversed = viewMatrix.inverse
        let projectionMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        let viewProjectionMatrix = projectionMatrix * viewMatrix
        pointCloudUniforms.viewProjectionMatrix = viewProjectionMatrix
        pointCloudUniforms.cameraPosition = camera.transform.columns.3
        pointCloudUniforms.localToWorld = viewMatrixInversed * rotateToARCamera
        pointCloudUniforms.cameraIntrinsicsInversed = cameraIntrinsicsInversed
        if isCollectingData {
            viewMatrixBuffer.insert(viewProjectionMatrix, at: bufferCurrentFrame)
        }
    }
    
    func draw() {
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
                  return
              }
        
        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let self = self {
                self.inFlightSemaphore.signal()
            }
        }
        
        // update frame data
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        // handle buffer rotating
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        
        if shouldAccumulate(frame: currentFrame), updateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
        }
        
        // render rgb camera image
        var retainingTextures = [capturedImageTextureY, capturedImageTextureCbCr]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(yCbCrToRGBPipelineState)
        renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
        renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        //        renderEncoder.setFragmentTexture(currentFrameTex!, index: Int(kTextureRGB.rawValue))
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        // render particles
        
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        
        
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
        
        //        Write capturedImage to Buffer for later conversion
        if isCollectingData {
            let insertFrameIndex = bufferCurrentFrame
            //            let texToSave = currentFrameTex!
            DispatchQueue.global(qos: .background).async {
                DispatchQueue.main.async { [self] in
                    videoBuffer.insert(currentFrame.capturedImage.copy(), at: insertFrameIndex)
                    //                    framesBuffer.insert(texToSave, at: insertFrameIndex)
                }
            }
            bufferCurrentFrame += 1
        }
    }
    
    private func shouldAccumulate(frame: ARFrame) -> Bool {
        if !isCollectingData{
            return false
        }
        let cameraTransform = frame.camera.transform
        return currentPointCount == 0
        || dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
        || distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        
        var retainingTextures = [/* capturedImageTextureY, capturedImageTextureCbCr, */ depthTexture, confidenceTexture]
        
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
            
            var i = self.cpuParticlesBuffer.count
            while (i < self.maxPoints && self.particlesBuffer[i].position != simd_float3(0.0,0.0,0.0)) {
                //  maybe only save high conf particles to cpu???
                let position = self.particlesBuffer[i].position
//                let color = self.particlesBuffer[i].color
                let normal = self.particlesBuffer[i].normal
                let confidence = self.particlesBuffer[i].confidence
                if confidence >= self.confidenceThreshold {
                    self.cpuParticlesBuffer.append(
                        CPUParticle(position: position,
                                    normal: normal,
//                                    color: color,
                                    confidence: confidence))
                    i += 1
                }
            }
        }
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
//        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
//        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: 0)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: 1)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        lastCameraTransform = frame.camera.transform
    }
    
    func compileProject() -> ScanProject {
        let project = ScanProject()
        
        project.setPointCloud(data: cpuParticlesBuffer)
        project.setViewProjectionMatrixes(data: viewMatrixBuffer)
        project.setRawVideoData(data: videoBuffer)
        
        return project
    }
}

// MARK: - Added Renderer functionality
extension ScanHandler {
    func toggleCollection() {
        self.isCollectingData = !self.isCollectingData
    }
    func toggleSceneMode() {
        self.isInViewSceneMode = !self.isInViewSceneMode
    }
    func getCpuParticles() -> Array<CPUParticle> {
        return self.cpuParticlesBuffer
    }
    
    func clearData() {
        currentPointIndex = 0
        currentPointCount = 0
        cpuParticlesBuffer = [CPUParticle]()
        rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
        pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
        videoBuffer = [CVPixelBuffer]()
        
        commandQueue = device.makeCommandQueue()!
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
        }
        particlesBuffer = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
    }
    
    func loadSavedClouds() {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        savedCloudURLs = try! FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }
}

// MARK: - Metal Renderer Helpers
private extension ScanHandler {
    func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    /// Makes sample points on camera image, also precompute the anchor point for animation
    func makeGridPoints() -> [Float2] {
        let gridArea = cameraResolution.x * cameraResolution.y
        let spacing = sqrt(gridArea / Float(numGridPoints))
        let deltaX = Int(round(cameraResolution.x / spacing))
        let deltaY = Int(round(cameraResolution.y / spacing))
        
        var points = [Float2]()
        for gridY in 0 ..< deltaY {
            let alternatingOffsetX = Float(gridY % 2) * spacing / 2
            for gridX in 0 ..< deltaX {
                let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5) * spacing, (Float(gridY) + 0.5) * spacing)
                
                points.append(cameraPoint)
            }
        }
        
        return points
    }
}
