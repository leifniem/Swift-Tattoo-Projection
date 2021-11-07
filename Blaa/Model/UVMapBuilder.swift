import Foundation
import MetalKit

class UVMapBuilder {
    private let device: MTLDevice
    private var mesh: MTKMesh
    private let textureDimensions = CGSize(width: 4096, height: 4096)
    private var texture: MTLTexture
    private var pipeline: MTLRenderPipelineState
    private var renderPassDescriptor: MTLRenderPassDescriptor
    
    init(mesh: MTKMesh, vertexDescriptor: MTLVertexDescriptor, device: MTLDevice) {
        self.device = device
        self.mesh = mesh
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.width = Int(textureDimensions.width)
        textureDescriptor.height = Int(textureDimensions.height)
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared
        textureDescriptor.sampleCount = 1
        self.texture = device.makeTexture(descriptor: textureDescriptor)!
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = texture.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
//        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
//        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
//        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
//        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        let library = device.makeDefaultLibrary()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "UVMapVert")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "wireFrag")
        self.pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        self.renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = self.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
//        draw()
    }
    
    public func draw() -> MTLTexture{
        guard let queue = device.makeCommandQueue(),
        let commandBuffer = queue.makeCommandBuffer(),
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Could not set up command structure to render UV map.")
        }
        renderEncoder.label = "Offscreen UV Render"
        renderEncoder.setRenderPipelineState(self.pipeline)
        renderEncoder.setTriangleFillMode(.lines)
        let vertexBuffer = self.mesh.vertexBuffers.first!
        renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
        mesh.submeshes.forEach{ submesh in
            let indexBuffer = submesh.indexBuffer
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: indexBuffer.buffer,
                indexBufferOffset: indexBuffer.offset
            )
        }
        renderEncoder.endEncoding()
        commandBuffer.commit()
        return self.texture
    }
}
