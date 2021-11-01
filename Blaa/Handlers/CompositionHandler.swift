import MetalKit
import CoreGraphics
import AVFoundation
import SwiftUI

final class CompositionHandler: RenderingHelper {
    
    private let view: MTKView
    private let project: ScanProject
    private var viewportSize = CGSize()
    
    private var currentFrame: CVPixelBuffer?
    private var currentViewMatrix: matrix_float4x4?
    private var currentProjectionMatrix: matrix_float4x4?
    private var modelMatrix: matrix_float4x4?
    private var currentFrameIndex: Int
    private var rgbUniforms: RGBUniforms
    private var rgbUniformsBuffer: MetalBuffer<RGBUniforms>
    private let pointsBuffer: MetalBuffer<ParticleUniforms>
    private var pointCloudUniforms: PointCloudUniforms
    private var pointCloudUniformsBuffer: MetalBuffer<PointCloudUniforms>
    private var mesh: MTKMesh?
    //    private var submesh: MTKSubmesh?
    //    private var vertBuffer: MTKMeshBuffer?
    private var modelPipelineState: MTLRenderPipelineState?
    
    private var commandQueue: MTLCommandQueue
    private var videoAspect: Float
    private var videoResolution: simd_float2
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
        self.videoResolution = simd_float2(
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
        self.pointCloudUniforms.viewMatrix = project.viewMatrixBuffer![0]
        self.pointCloudUniforms.projectionMatrix = project.projectionMatrixBuffer![0]
        
        if project.resources["model"]! {
            self.mesh = project.model
            
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexDescriptor = project.vertexDescriptor!
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            //            if !project.resources["texture"]! {
            descriptor.vertexFunction = library.makeFunction(name: "wireVert")
            descriptor.fragmentFunction = library.makeFunction(name: "wireFrag")
            //            } else {
            //                descriptor.vertexFunction = library.makeFunction(name: "wireframeVertex")
            //                descriptor.fragmentFunction = library.makeFunction(name: "wireframeFragment")
            //            }
            
            do {self.modelPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)}
            catch { fatalError("Could not create ModelPipelineState.") }
        }
    }
    
    func setPlayBackFrame(value: Float) {
        self.currentFrameIndex = Int((value * Float(project.videoFrames!.count - 1)).rounded(.down))
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
            return
        }
        
        //        TODO: Check if triple buffering is needed to reach performance
        
        pointCloudUniformsBuffer[0].viewMatrix = currentViewMatrix!
        pointCloudUniformsBuffer[0].projectionMatrix = currentProjectionMatrix!
        
        let currentFrameTex = self.textureFromPixelBuffer(fromPixelBuffer: currentFrame!, pixelFormat: .bgra8Unorm)!
        
        if project.resources["video"]! && !project.resources["model"]! {
            renderEncoder.setRenderPipelineState(rgbHalfOpacityPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffer)
            renderEncoder.setFragmentBuffer(rgbUniformsBuffer)
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(currentFrameTex), index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            renderEncoder.setRenderPipelineState(particlePipelineState)
            renderEncoder.setVertexBuffer(pointCloudUniformsBuffer)
            renderEncoder.setVertexBuffer(pointsBuffer)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointsBuffer.count)
        } else if project.resources["video"]! && project.resources["model"]! && self.mesh != nil{
            renderEncoder.setRenderPipelineState(rgbHalfOpacityPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffer)
            renderEncoder.setFragmentBuffer(rgbUniformsBuffer)
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(currentFrameTex), index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            if !project.resources["texture"]! {
                //            wireframe
                renderEncoder.setRenderPipelineState(self.modelPipelineState!)
                renderEncoder.setTriangleFillMode(.lines)
//                renderEncoder.setCullMode(.none)
                let vertexBuffer = mesh!.vertexBuffers.first!
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
                renderEncoder.setVertexBuffer(pointCloudUniformsBuffer.bufferContent, offset: 0, index: 1)
                mesh!.submeshes.forEach{ submesh in
//                    renderEncoder.setVertexBuffer(pointCloudUniformsBuffer)
                    let indexBuffer = submesh.indexBuffer
                    renderEncoder.drawIndexedPrimitives(
                        type: submesh.primitiveType,
                        indexCount: submesh.indexCount,
                        indexType: submesh.indexType,
                        indexBuffer: indexBuffer.buffer,
                        indexBufferOffset: indexBuffer.offset
                    )
                }
            }
            //            eeeeelse
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
        
        if let error = commandBuffer.error as NSError? {
            NSLog("%@", error)
        }
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
    
    func loadModelForMetal() {
        
    }
}

//model matrix
extension float4x4 {
    init(scaleBy s: Float) {
        self.init(simd_float4(s, 0, 0, 0),
                  simd_float4(0, s, 0, 0),
                  simd_float4(0, 0, s, 0),
                  simd_float4(0, 0, 0, 1))
    }
 
    init(rotationAbout axis: simd_float3, by angleRadians: Float) {
        let x = axis.x, y = axis.y, z = axis.z
        let c = cosf(angleRadians)
        let s = sinf(angleRadians)
        let t = 1 - c
        self.init(simd_float4( t * x * x + c,     t * x * y + z * s, t * x * z - y * s, 0),
                  simd_float4( t * x * y - z * s, t * y * y + c,     t * y * z + x * s, 0),
                  simd_float4( t * x * z + y * s, t * y * z - x * s,     t * z * z + c, 0),
                  simd_float4(                 0,                 0,                 0, 1))
    }
 
    init(translationBy t: simd_float3) {
        self.init(simd_float4(   1,    0,    0, 0),
                  simd_float4(   0,    1,    0, 0),
                  simd_float4(   0,    0,    1, 0),
                  simd_float4(t[0], t[1], t[2], 1))
    }
 
    init(perspectiveProjectionFov fovRadians: Float, aspectRatio aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
 
        let xx = xScale
        let yy = yScale
        let zz = zScale
        let zw = Float(-1)
        let wz = wzScale
 
        self.init(simd_float4(xx,  0,  0,  0),
                  simd_float4( 0, yy,  0,  0),
                  simd_float4( 0,  0, zz, zw),
                  simd_float4( 0,  0, wz,  0))
    }
}
