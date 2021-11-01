import MetalKit
import CoreGraphics
import AVFoundation

final class LimitHandler: RenderingHelper {
    
    private let view: MTKView
    private let project: ScanProject
    private var viewportSize = CGSize()
    
    private var currentFrame: CVPixelBuffer?
    private var currentViewMatrix: matrix_float4x4?
    private var currentProjectionMatrix: matrix_float4x4?
    private var currentFrameIndex: Int
    private var rgbUniforms: RGBUniforms
    private var rgbUniformsBuffer: MetalBuffer<RGBUniforms>
    private let pointsBuffer: MetalBuffer<ParticleUniforms>
    private var pointCloudUniforms: PointCloudUniforms
    private var pointCloudUniformsBuffer: MetalBuffer<PointCloudUniforms>
    
    private var commandQueue: MTLCommandQueue
    private var videoAspect: Float
    private var videoResolution: simd_float2
    //    private let particleSize: Float = 8
    private var frameTextureY: CVMetalTexture?
    private var frameTextureCbCr: CVMetalTexture?
    private var frameTextureBGRA: CVMetalTexture?
    private let isYcBcR: Bool
    
    private var boundingBox: Box
    private var limitBox: Box
    private var limitBoxBuffer: MetalBuffer<Box>
    
    var bounds: Box {
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
        self.videoResolution = simd_float2(
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
        
        var boxMin = simd_float3()
        var boxMax = simd_float3()
        boxMin.x = project.pointCloud!.min(by:{ $0.position.x < $1.position.x })!.position.x
        boxMax.x = project.pointCloud!.max(by:{ $0.position.x < $1.position.x })!.position.x
        boxMin.y = project.pointCloud!.min(by:{ $0.position.y < $1.position.y })!.position.y
        boxMax.y = project.pointCloud!.max(by:{ $0.position.y < $1.position.y })!.position.y
        boxMin.z = project.pointCloud!.min(by:{ $0.position.z < $1.position.z })!.position.z
        boxMax.z = project.pointCloud!.max(by:{ $0.position.z < $1.position.z })!.position.z
        self.boundingBox = Box(boxMin: boxMin, boxMax: boxMax)
        if project.boundingBox != nil {
            limitBox = project.boundingBox!
        } else {
            limitBox = boundingBox
        }
        limitBoxBuffer = MetalBuffer<Box>(device: device, array: [limitBox], index: kBoundingBox.rawValue)
        
        super.init(device: device, renderDestination: view)
        
        self.pointCloudUniforms.maxPoints = 15_000_000
        self.pointCloudUniforms.cameraResolution = simd_float2(videoResolution)
        self.pointCloudUniforms.particleSize = 8
        self.pointCloudUniforms.confidenceThreshold = 2
        self.pointCloudUniforms.pointCloudCurrentIndex = 0
        self.pointCloudUniforms.viewMatrix = project.viewMatrixBuffer![0]
        self.pointCloudUniforms.projectionMatrix = project.projectionMatrixBuffer![0]
    }
    
    func setPlayBackFrame(value: Float) {
        self.currentFrameIndex = Int((value * Float(project.videoFrames!.count - 1)).rounded(.down))
    }
    
    func setBoundingBoxCoordinate(axis: String, t: Float) {
        switch axis{
        case "xMin":
            self.limitBox.boxMin.x = lerp(t: t, min: boundingBox.boxMin.x, max: boundingBox.boxMax.x)
        case "xMax":
            self.limitBox.boxMax.x = lerp(t: t, min: boundingBox.boxMin.x, max: boundingBox.boxMax.x)
        case "yMin":
            self.limitBox.boxMin.y = lerp(t: t, min: boundingBox.boxMin.y, max: boundingBox.boxMax.y)
        case "yMax":
            self.limitBox.boxMax.y = lerp(t: t, min: boundingBox.boxMin.y, max: boundingBox.boxMax.y)
        case "zMin":
            self.limitBox.boxMin.z = lerp(t: t, min: boundingBox.boxMin.z, max: boundingBox.boxMax.z)
        case "zMax":
            self.limitBox.boxMax.z = lerp(t: t, min: boundingBox.boxMin.z, max: boundingBox.boxMax.z)
        default:
            break
        }
    }
    
    func lerp(t: Float, min: Float, max: Float) -> Float{
        return t * max + (1 - t) * min
    }
    
    func writeBoundingBox() {
        self.project.setBoundingBox(limitBox)
        print(self.limitBox.boxMin, self.limitBox.boxMax)
    }
    
    func draw () {
        currentFrame = project.videoFrames![currentFrameIndex]
        currentViewMatrix = project.viewMatrixBuffer![currentFrameIndex]
        currentProjectionMatrix = project.projectionMatrixBuffer![currentFrameIndex]
        guard currentFrame != nil,
              currentViewMatrix != nil,
              currentProjectionMatrix != nil,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor)
        else {
            print("Error Updating render command in LimitHandler.")
            return
        }
        
        //        TODO: Check if triple buffering is needed to reach performance
        
        pointCloudUniformsBuffer[0].viewMatrix = currentViewMatrix!
        pointCloudUniformsBuffer[0].projectionMatrix = currentProjectionMatrix!
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

//extension LimitHandler {
//
//}
