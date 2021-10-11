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
//        https://stackoverflow.com/questions/49390728/how-to-get-frames-from-a-local-video-file-in-swift
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
}
