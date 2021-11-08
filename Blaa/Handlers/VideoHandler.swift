import CoreVideo
import AVFoundation
import Accelerate

class VideoHandler {
    
    let fps: Int32 = 30
    
    func writeVideo(rawVideoData: [CVPixelBuffer], videoURL: URL) {
        var frames = rawVideoData
        let frameDuration = CMTimeMake(value: 1, timescale: fps)
        let sourceWidth = frames[0].getWidth(plane: 0)
        let sourceHeight = frames[0].getHeight(plane: 0)
        
        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey : 2000000,
        ]
        
        let videoSettings: [String : Any] = [
            AVVideoWidthKey: sourceWidth,
            AVVideoHeightKey: sourceHeight,
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoCompressionPropertiesKey: compressionSettings
        ]
        
        
        var assetWriter: AVAssetWriter?
        do {assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)} catch {
            fatalError("Asset Writer creation failed: \(error).")
        }
        
        guard let assetWriter = assetWriter else {
            fatalError("Asset Writer does not exist.")
        }
        
        guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            fatalError("Output Settings not working for filetype.")
        }
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        guard assetWriter.canAdd(input) else {
            fatalError("Cannot add data input to video out.")
        }
        
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        input.mediaTimeScale = CMTimeScale(fps)
        
        assetWriter.add(input)
        
        let videoPixelAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(sourceWidth)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(sourceHeight)),
        ] as [String: Any]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: videoPixelAttributes)
        
        if assetWriter.startWriting(){
            assetWriter.startSession(atSourceTime: .zero)
            guard pixelBufferAdaptor.pixelBufferPool != nil else {
                fatalError("pixelBufferPool does not exist")
            }
            
            let videoQueue = DispatchQueue(label: "website.leifs.scanner.VideoOutputQueue")
            
            input.requestMediaDataWhenReady(on: videoQueue, using: { () -> Void in
                var currentFrameIndex:Int64 = 0
                var currentTime = CMTime(value: 0, timescale: self.fps)
                var lastFrameSuccess = true
                
                while(!frames.isEmpty) {
                    if input.isReadyForMoreMediaData {
                        let frame = frames.remove(at: 0)
                        lastFrameSuccess = pixelBufferAdaptor.append(frame, withPresentationTime: currentTime)
                        currentTime = CMTimeAdd(currentTime, frameDuration)
                        currentFrameIndex += 1
                    }
                    if(!lastFrameSuccess) {
                        print(assetWriter.error! as Any, assetWriter.status.rawValue)
                        fatalError("Could not append buffer to video output")
                        break
                    }
                }
                input.markAsFinished()
                assetWriter.finishWriting(completionHandler: { () -> Void in
                    print("VIDEO EXPORTED")
                } )
            })
        }
        
        
    }
    
    func readVideo(url: URL) -> [CVPixelBuffer] {
        var frames: [CVPixelBuffer] = []
        
        let asset = AVAsset(url: url)
        let reader = try! AVAssetReader(asset: asset)
        
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        
        // read video frames as BGRA
        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings:[String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
        
        reader.add(trackReaderOutput)
        reader.startReading()
        
        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frames.append(imageBuffer)
            }
        }
        
        return frames
    }
    
    func encodeDepth(depthBuffer: [CVPixelBuffer], url: URL) {
        var frames = depthBuffer
        let frameDuration = CMTimeMake(value: 1, timescale: fps)
        let sourceWidth = frames[0].getWidth()
        let sourceHeight = frames[0].getHeight()
        
        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey : 8000000,
        ]
        
        let videoSettings: [String : Any] = [
            AVVideoWidthKey: sourceWidth,
            AVVideoHeightKey: sourceHeight,
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: compressionSettings
        ]
        
        
        var assetWriter: AVAssetWriter?
        do {assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)} catch {
            fatalError("Asset Writer creation failed: \(error).")
        }
        
        guard let assetWriter = assetWriter else {
            fatalError("Asset Writer does not exist.")
        }
        
        guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            fatalError("Output Settings not working for filetype.")
        }
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        guard assetWriter.canAdd(input) else {
            fatalError("Cannot add data input to video out.")
        }
        
        input.transform = CGAffineTransform(scaleX: 1, y: -1).rotated(by: .pi/2)
        
        assetWriter.add(input)
        
        let videoPixelAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(sourceWidth)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(sourceHeight)),
        ] as [String: Any]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: videoPixelAttributes)
        
        //        MTLKit Stuff
        let device = MTLCreateSystemDefaultDevice()!
        let library = device.makeDefaultLibrary()!
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.width = sourceWidth
        textureDescriptor.height = sourceHeight
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        textureDescriptor.sampleCount = 1
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "rgbVertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "encodeDepth")
        let pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
//        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
//        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
//        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
//        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        let rgbUniforms: RGBUniforms = {
            var uniforms = RGBUniforms()
            uniforms.viewToCamera = matrix_float3x3(columns: (
                simd_float3(0, 1, 0),
                simd_float3(-1, 0, 1),
                simd_float3(0, 0, 1)
            ))
            uniforms.viewRatio = Float(sourceWidth / sourceHeight)
            return uniforms
        }()
        let rgbUniformsBuffer = MetalBuffer<RGBUniforms>(device: device, array: [rgbUniforms], index: 0)
        
        if assetWriter.startWriting(){
            assetWriter.startSession(atSourceTime: .zero)
            guard pixelBufferAdaptor.pixelBufferPool != nil else {
                fatalError("pixelBufferPool does not exist")
            }
            
            let videoQueue = DispatchQueue(label: "website.leifs.scanner.VideoOutputQueue")
            
            let commandQueue = device.makeCommandQueue()!
            commandQueue.label = "Depth Encoding Queue"
            
            input.requestMediaDataWhenReady(on: videoQueue, using: { () -> Void in
                var currentFrameIndex:Int64 = 0
                var currentTime = CMTime(value: 0, timescale: self.fps)
                var lastFrameSuccess = true
                
                while(!frames.isEmpty) {
                    if input.isReadyForMoreMediaData {
                        let frame = frames.remove(at: 0)
                        
                        let frameTex = frame.toCVMetalTexture(textureCache: cache, pixelFormat: .r32Float)!
                        let outTex = device.makeTexture(descriptor: textureDescriptor)
                        renderPassDescriptor.colorAttachments[0].texture = outTex
                        
                        guard let commandBuffer = commandQueue.makeCommandBuffer(),
                              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                                  fatalError("Could not set up command structure to render Depth Video.")
                              }
                        
                        renderEncoder.setRenderPipelineState(pipelineState)
                        renderEncoder.setVertexBuffer(rgbUniformsBuffer, offset: 0)
                        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(frameTex), index: 0)
                        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                        renderEncoder.endEncoding()
                        
                        commandBuffer.addCompletedHandler{ commandBuffer in
                            var buffer: CVPixelBuffer?
                            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferAdaptor.pixelBufferPool!, &buffer)
                            guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
                                fatalError("Could not create CVPixelBuffer for depth video.")
                            }
                            CVPixelBufferLockBaseAddress(pixelBuffer, [])
                            let data = CVPixelBufferGetBaseAddress(pixelBuffer)
                            let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
                            let region = MTLRegionMake2D(0, 0, outTex!.width, outTex!.height)
                            outTex!.getBytes(data!, bytesPerRow: bpr, from: region, mipmapLevel: 0)
                            
                            lastFrameSuccess = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: currentTime)
                            currentTime = CMTimeAdd(currentTime, frameDuration)
                            CVPixelBufferUnlockBaseAddress(buffer!, [])
                            currentFrameIndex += 1
                        }
                        
                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
                    }
                    if(!lastFrameSuccess) {
                        print(assetWriter.error! as Any, assetWriter.status.rawValue)
                        fatalError("Could not append buffer to video output")
                        break
                    }
                }
                input.markAsFinished()
                assetWriter.finishWriting(completionHandler: { () -> Void in
                    print("DEPTH EXPORTED")
                } )
            })
        }
    }
    
    func readDepth(url: URL) -> [CVPixelBuffer] {
        var frames: [CVPixelBuffer] = []
        
        let asset = AVAsset(url: url)
        let reader = try! AVAssetReader(asset: asset)
        
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        
        // read video frames as BGRA
        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings:[String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
        
        reader.add(trackReaderOutput)
        reader.startReading()
        
        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frames.append(imageBuffer)
            }
        }
        
        //        MTLKit Stuff
        let device = MTLCreateSystemDefaultDevice()!
        let library = device.makeDefaultLibrary()!
        
        let sourceWidth = frames[0].getWidth()
        let sourceHeight = frames[0].getHeight()
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.width = sourceWidth
        textureDescriptor.height = sourceHeight
        textureDescriptor.pixelFormat = .r32Float
        textureDescriptor.usage = [.shaderWrite]
        textureDescriptor.storageMode = .shared
        textureDescriptor.sampleCount = 1
        
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        
        let pipelineState = try! device.makeComputePipelineState(function: library.makeFunction(name: "decodeDepth")!)
        let numThreadgroups = MTLSize(width: sourceWidth, height: sourceHeight, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: 1, height: 1, depth: 1)
        
        let commandQueue = device.makeCommandQueue()!
        
        let sharedCaptueManager = MTLCaptureManager.shared()
        let myScope = sharedCaptueManager.makeCaptureScope(commandQueue: commandQueue)
        myScope.label = "Debug Depth Decoding"
        sharedCaptueManager.defaultCaptureScope = myScope
        myScope.begin()
        
        let back: [CVPixelBuffer] = frames.map{ frame in
            let frameTex = frame.toCVMetalTexture(textureCache: cache, pixelFormat: .bgra8Unorm)!
            let outTex = device.makeTexture(descriptor: textureDescriptor)
            //            renderPassDescriptor.colorAttachments[0].texture = outTex
            
            
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                      fatalError("Could not set up command structure to render Depth Video.")
                  }
            
            encoder.setComputePipelineState(pipelineState)
            encoder.setTexture(CVMetalTextureGetTexture(frameTex), index: 0)
            encoder.setTexture(outTex, index: 1)
            encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
            
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, sourceWidth, sourceHeight, kCVPixelFormatType_DepthFloat32, [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &buffer)
            guard let pixelBuffer = buffer else {
                fatalError("Could not create CVPixelBuffer for depth video.")
            }
            
            commandBuffer.addCompletedHandler{ commandBuffer in
                CVPixelBufferLockBaseAddress(pixelBuffer, [])
                let data = CVPixelBufferGetBaseAddress(pixelBuffer)
                let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let region = MTLRegionMake2D(0, 0, outTex!.width, outTex!.height)
                outTex!.getBytes(data!, bytesPerRow: bpr, from: region, mipmapLevel: 0)
                
                CVPixelBufferUnlockBaseAddress(buffer!, [])
            }
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            return buffer!
        }
        
        myScope.end()
        
        return back
    }
}
