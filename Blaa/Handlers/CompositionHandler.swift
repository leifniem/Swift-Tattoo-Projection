import MetalKit
import CoreGraphics
import AVFoundation

final class CompositionHandler: RenderingHelper {
    
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
        self.commandQueue = device.makeCommandQueue()!
        self.pointsBuffer = MetalBuffer<ParticleUniforms>(device: device, array: project.getParticleUniforms(), index: kParticleUniforms.rawValue)
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
        super.init(device: device, renderDestination: view)
        
        self.pointCloudUniforms.maxPoints = 15_000_000
        self.pointCloudUniforms.cameraResolution = simd_float2(videoResolution)
        self.pointCloudUniforms.particleSize = 16
        self.pointCloudUniforms.confidenceThreshold = 2
        self.pointCloudUniforms.pointCloudCurrentIndex = 0
        self.pointCloudUniforms.viewProjectionMatrix = project.viewProjectionMatrixes![0]
    }
    
    func setPlayBackFrame(value: Float) {
        self.currentFrameIndex = Int((value * Float(project.videoFrames!.count - 1)).rounded(.down))
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
            return
        }
        
//        TODO: Check if triple buffering is needed to reach performance
        
        pointCloudUniformsBuffer[0].viewProjectionMatrix = currentMatrix!

        let currentFrameTex = self.textureFromPixelBuffer(fromPixelBuffer: currentFrame!, pixelFormat: .bgra8Unorm)!
        
        renderEncoder.setRenderPipelineState(rgbHalfOpacityPipelineState)
        renderEncoder.setVertexBuffer(rgbUniformsBuffer)
        renderEncoder.setFragmentBuffer(rgbUniformsBuffer)
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(currentFrameTex), index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffer)
        renderEncoder.setVertexBuffer(pointsBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointsBuffer.count)
        
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
}
