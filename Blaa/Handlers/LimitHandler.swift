import MetalKit
import CoreGraphics
import AVFoundation

final class LimitHandler: RenderingHelper {
    
    private let view: MTKView
    private let project: ScanProject
    private var viewportSize = CGSize()
    
    private var currentFrame: CVPixelBuffer?
    private var currentMatrix: matrix_float4x4?
    private var currentFrameIndex: Int
    private var rgbUniforms: RGBUniforms
    private var rgbUniformsBuffer: MetalBuffer<RGBUniforms>
    private let pointsBuffer: MetalBuffer<ParticleUniforms>
    private var pointCloudUniforms: PointCloudUniforms
    private var pointCloudUniformsBuffer: MetalBuffer<PointCloudUniforms>
    
    private var commandQueue: MTLCommandQueue
    private var videoAspect: Float
    private var videoResolution: Float2
    //    private let particleSize: Float = 8
    private var frameTextureY: CVMetalTexture?
    private var frameTextureCbCr: CVMetalTexture?
    private var frameTextureBGRA: CVMetalTexture?
    private let isYcBcR: Bool
    
    private var boundingBox = BoundingBox()
    private var limitBox = BoundingBox()
    private var limitBoxBuffer: MetalBuffer<BoundingBox>
    
    var bounds: BoundingBox {
        get {
            return self.limitBox
        }
    }
    
    init(device: MTLDevice, view: MTKView, project: ScanProject) {
        guard project.videoFrames != nil else {
            fatalError("Project passed has no video frame data")
        }
        self.view = view
        self.project = project
        self.currentFrameIndex = 0
        self.videoAspect = Float(project.videoFrames![0].getWidth(plane: 0) / project.videoFrames![0].getHeight(plane: 0))
        self.videoResolution = Float2(
            Float(project.videoFrames![0].getWidth(plane: 0)),
            Float(project.videoFrames![0].getHeight(plane: 0))
        )
        self.isYcBcR = CVPixelBufferGetPlaneCount(project.videoFrames![0]) > 1
        self.commandQueue = device.makeCommandQueue()!
        
        self.pointsBuffer = MetalBuffer<ParticleUniforms>(device: device, array: project.getParticleUniforms(), index: kParticleUniforms.rawValue)
        
        self.pointCloudUniforms = PointCloudUniforms()
        self.pointCloudUniforms = PointCloudUniforms()
        self.pointCloudUniformsBuffer = .init(device: device, array: [pointCloudUniforms], index: kPointCloudUniforms.rawValue)
        rgbUniforms = {
            var uniforms = RGBUniforms()
            uniforms.viewToCamera = matrix_float3x3(columns: (
                simd_float3(0, 1, 0),
                simd_float3(-1, 0, 1),
                simd_float3(0, 0, 1)
            ))
            uniforms.viewRatio = Float(project.videoFrames![0].getWidth(plane: 0) / project.videoFrames![0].getHeight(plane: 0))
            return uniforms
        }()
        rgbUniformsBuffer = MetalBuffer<RGBUniforms>(device: device, array: [rgbUniforms], index: 0)
        
        boundingBox.xMin = project.pointCloud!.min(by:{ $0.position.x < $1.position.x })!.position.x
        boundingBox.xMax = project.pointCloud!.max(by:{ $0.position.x < $1.position.x })!.position.x
        boundingBox.yMin = project.pointCloud!.min(by:{ $0.position.y < $1.position.y })!.position.y
        boundingBox.yMax = project.pointCloud!.max(by:{ $0.position.y < $1.position.y })!.position.y
        boundingBox.zMin = project.pointCloud!.min(by:{ $0.position.z < $1.position.z })!.position.z
        boundingBox.zMax = project.pointCloud!.max(by:{ $0.position.z < $1.position.z })!.position.z
        limitBox = boundingBox
        limitBoxBuffer = MetalBuffer<BoundingBox>(device: device, array: [limitBox], index: kBoundingBox.rawValue)
        
        super.init(device: device, renderDestination: view)
        
        self.pointCloudUniforms.maxPoints = 15_000_000
        self.pointCloudUniforms.cameraResolution = simd_float2(videoResolution)
        self.pointCloudUniforms.particleSize = 8
        self.pointCloudUniforms.confidenceThreshold = 2
        self.pointCloudUniforms.pointCloudCurrentIndex = 0
        self.pointCloudUniforms.viewProjectionMatrix = project.viewProjectionMatrixes![0]
    }
    
    func setPlayBackFrame(value: Float) {
        self.currentFrameIndex = Int((value * Float(project.videoFrames!.count - 1)).rounded(.down))
    }
    
    func setBoundingBoxCoordinate(axis: String, t: Float) {
        switch axis{
        case "xMin":
            self.limitBox.xMin = lerp(t: t, min: boundingBox.xMin, max: (boundingBox.xMax + boundingBox.xMin) / 2)
        case "xMax":
            self.limitBox.xMax = lerp(t: t, min: (boundingBox.xMax + boundingBox.xMin) / 2, max: boundingBox.xMax)
        case "yMin":
            self.limitBox.yMin = lerp(t: t, min: boundingBox.yMin, max: (boundingBox.yMax + boundingBox.yMin) / 2)
        case "yMax":
            self.limitBox.yMax = lerp(t: t, min: (boundingBox.yMax + boundingBox.yMin) / 2, max: boundingBox.yMax)
        case "zMin":
            self.limitBox.zMin = lerp(t: t, min: boundingBox.zMin, max: (boundingBox.zMax + boundingBox.zMin) / 2)
        case "zMax":
            self.limitBox.zMax = lerp(t: t, min: (boundingBox.zMax + boundingBox.zMin) / 2, max: boundingBox.zMax)
        default:
            break
        }
    }
    
    func lerp(t: Float, min: Float, max: Float) -> Float{
        return t * max + (1 - t) * min
    }
    
    func draw () {
        currentFrame = project.videoFrames![currentFrameIndex]
        currentMatrix = project.viewProjectionMatrixes![currentFrameIndex]
        guard currentFrame != nil,
              currentMatrix != nil,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor)
        else {
            print("Error Updating render command in LimitHandler.")
            return
        }
        
        //        TODO: Check if triple buffering is needed to reach performance
        
        pointCloudUniformsBuffer[0].viewProjectionMatrix = currentMatrix!
        limitBoxBuffer[0] = limitBox
        
        if self.isYcBcR {
            //  CV420YpCbCr8BiPlanarFullRange
            frameTextureY = textureFromPixelBuffer(fromPixelBuffer: currentFrame!, pixelFormat: .r8Unorm, planeIndex: 0)
            frameTextureCbCr = textureFromPixelBuffer(fromPixelBuffer: currentFrame!, pixelFormat: .rg8Unorm, planeIndex: 1)
            renderEncoder.setRenderPipelineState(yCbCrToRGBPipelineState)
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(frameTextureY!), index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(frameTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        } else {
            frameTextureBGRA = textureFromPixelBuffer(fromPixelBuffer: currentFrame!, pixelFormat: .bgra8Unorm)
            renderEncoder.setRenderPipelineState(rgbHalfOpacityPipelineState)
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(frameTextureBGRA!), index: 0)
        }
        renderEncoder.setVertexBuffer(rgbUniformsBuffer)
        renderEncoder.setFragmentBuffer(rgbUniformsBuffer)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.setRenderPipelineState(limitedParticlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffer)
        renderEncoder.setVertexBuffer(pointsBuffer)
        renderEncoder.setVertexBuffer(limitBoxBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointsBuffer.count)
        
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
}

extension LimitHandler {
    
}
