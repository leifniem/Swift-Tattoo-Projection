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
    private var descriptor: MTLRenderPipelineDescriptor
    private var modelPipelineState: MTLRenderPipelineState?
    private var sketchTexture: MTLTexture?
    private var saveNextFrame = false
    private var image: CGImage?
    
    private var commandQueue: MTLCommandQueue
    private var videoAspect: Float
    private var videoResolution: simd_float2
    
    init(device: MTLDevice, view: MTKView, project: ScanProject) {
        guard project.videoFrames != nil else {
            fatalError("Project passed has no video frame data")
        }
        self.view = view
        view.framebufferOnly = false
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
        
        self.pointCloudUniforms.maxPoints = 15_000_000
        self.pointCloudUniforms.cameraResolution = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        self.pointCloudUniforms.particleSize = 16
        self.pointCloudUniforms.confidenceThreshold = 2
        self.pointCloudUniforms.pointCloudCurrentIndex = 0
        self.pointCloudUniforms.viewMatrix = project.viewMatrixBuffer![0]
        self.pointCloudUniforms.projectionMatrix = project.projectionMatrixBuffer![0]
        self.descriptor = MTLRenderPipelineDescriptor()
        self.descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        self.descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        self.descriptor.colorAttachments[0].isBlendingEnabled = true
        self.descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        self.descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        self.descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        super.init(device: device, renderDestination: view)
        
        if project.resources["model"]! && project.model != nil {
            updateModelPipeLineState()
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
        pointCloudUniformsBuffer[0].cameraResolution = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        
        if saveNextFrame {
            let size = currentFrame!.getSize()
            view.autoResizeDrawable = false
            self.pointCloudUniformsBuffer[0].cameraResolution = simd_float2(
                Float(size.width),
                Float(size.height)
            )
            commandBuffer.addCompletedHandler { [weak self] commandBuffer in
                if let self = self {
                    self.pointCloudUniformsBuffer[0].cameraResolution = simd_float2(
                        Float(self.view.drawableSize.width),
                        Float(self.view.drawableSize.height)
                    )
                    self.saveNextFrame = false
                    self.view.autoResizeDrawable = true
                    
                    DispatchQueue.global(qos: .background).async {
                        DispatchQueue.main.async {
                            if self.image != nil {
                                let frameImage = UIImage(cgImage: self.image!)
                                UIImageWriteToSavedPhotosAlbum(frameImage, nil, nil, nil)
                            }
                        }
                    }
                }
            }
        }
        
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
            
            renderEncoder.setRenderPipelineState(self.modelPipelineState!)
            if !project.resources["texture"]! {
                renderEncoder.setTriangleFillMode(.lines)
                print("noTex")
            } else {
                renderEncoder.setCullMode(MTLCullMode.none)
                renderEncoder.setFragmentTexture(self.sketchTexture, index: 1)
            }
            let vertexBuffer = mesh!.vertexBuffers.first!
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
            renderEncoder.setVertexBuffer(pointCloudUniformsBuffer.bufferContent, offset: 0, index: 1)
            renderEncoder.setFragmentBuffer(pointCloudUniformsBuffer.bufferContent, offset: 0, index: 1)
            mesh!.submeshes.forEach{ submesh in
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
        
        renderEncoder.endEncoding()
        if saveNextFrame {
            image = renderDestination.currentDrawable!.texture.toImage()
        }
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
        if saveNextFrame {
            commandBuffer.waitUntilCompleted()
        }
        
        if let error = commandBuffer.error as NSError? {
            NSLog("%@", error)
        }
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        pointCloudUniforms.cameraResolution = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        pointCloudUniformsBuffer[0].cameraResolution = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
    }
    
    func updateModelPipeLineState() {
        self.mesh = project.model
        self.descriptor.vertexDescriptor = project.vertexDescriptor!
        self.descriptor.vertexFunction = library.makeFunction(name: "modelVert")
        if !project.resources["texture"]! && project.sketch != nil{
            self.descriptor.fragmentFunction = library.makeFunction(name: "wireFrag")
        } else {
            let loader = MTKTextureLoader(device: device)
            let textureLoaderOptions: [MTKTextureLoader.Option : Any] = [
                .origin: MTKTextureLoader.Origin.bottomLeft
            ]
            do {
                self.sketchTexture = try loader.newTexture(
                    URL: project.folder!.appendingPathComponent(ScanProject.Constants.sketchName),
                    options: textureLoaderOptions)
            } catch {
                fatalError("Could not load sketch for rendering")
            }
            self.descriptor.fragmentFunction = library.makeFunction(name: "sketchFrag")
        }
        
        do {self.modelPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)}
        catch { fatalError("Could not create ModelPipelineState.") }
    }
    
    func saveFrame() {
        self.saveNextFrame = true
    }
}

extension MTLTexture {

    func bytes() -> UnsafeMutableRawPointer {
        let width = self.width
        let height   = self.height
        let rowBytes = self.width * 4
        let p = malloc(width * height * 4)

        self.getBytes(p!, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        return p!
    }

    func toImage() -> CGImage? {
        let p = bytes()

        let pColorSpace = CGColorSpaceCreateDeviceRGB()

        let rawBitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let bitmapInfo:CGBitmapInfo = CGBitmapInfo(rawValue: rawBitmapInfo)

        let selftureSize = self.width * self.height * 4
        let rowBytes = self.width * 4
        let releaseMaskImagePixelData: CGDataProviderReleaseDataCallback = { (info: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int) -> () in
            return
        }
        let provider = CGDataProvider(dataInfo: nil, data: p, size: selftureSize, releaseData: releaseMaskImagePixelData)
        let cgImageRef = CGImage(width: self.width, height: self.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: pColorSpace, bitmapInfo: bitmapInfo, provider: provider!, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)!

        return cgImageRef
    }
}
