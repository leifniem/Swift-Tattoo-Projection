/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 General Helper methods and properties
 */

import ARKit
import VideoToolbox
import Accelerate

typealias Float2 = SIMD2<Float>
typealias Float3 = SIMD3<Float>

extension Float {
    static let degreesToRadian = Float.pi / 180
}

extension matrix_float3x3 {
    mutating func copy(from affine: CGAffineTransform) {
        columns.0 = Float3(Float(affine.a), Float(affine.c), Float(affine.tx))
        columns.1 = Float3(Float(affine.b), Float(affine.d), Float(affine.ty))
        columns.2 = Float3(0, 0, 1)
    }
}


extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        guard let cgImage = cgImage else {
            return nil
        }
        
        self.init(cgImage: cgImage)
    }
    
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
        // Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        let context = UIGraphicsGetCurrentContext()!
        
        // Move origin to middle
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        // Rotate around middle
        context.rotate(by: CGFloat(radians))
        // Draw the image at its center
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}

extension CVPixelBuffer
{
    /// Deep copy a CVPixelBuffer:
    ///   http://stackoverflow.com/questions/38335365/pulling-data-from-a-cmsamplebuffer-in-order-to-create-a-deep-copy
    func copy() -> CVPixelBuffer
    {
        precondition(CFGetTypeID(self) == CVPixelBufferGetTypeID(), "copy() cannot be called on a non-CVPixelBuffer")
        
        var _copy: CVPixelBuffer?
        
        CVPixelBufferCreate(
            nil,
            self.getWidth(),
            self.getHeight(),
            CVPixelBufferGetPixelFormatType(self),
            [
                kCVPixelBufferMetalCompatibilityKey: true
            ] as CFDictionary ,
            &_copy)
        
        guard let copy = _copy else { fatalError() }
        
        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer
        {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }
        
        for plane in 0 ..< CVPixelBufferGetPlaneCount(self)
        {
            let dest        = CVPixelBufferGetBaseAddressOfPlane(copy, plane)
            let source      = CVPixelBufferGetBaseAddressOfPlane(self, plane)
            let height      = CVPixelBufferGetHeightOfPlane(self, plane)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(self, plane)
            
            memcpy(dest, source, height * bytesPerRow)
        }
        
        return copy
    }
    
    func getWidth(plane: Int? = nil) -> Int {
        if plane != nil {
            return CVPixelBufferGetWidthOfPlane(self, plane!)
        } else {
            return CVPixelBufferGetWidth(self)
        }
    }
    
    func getHeight(plane: Int? = nil) -> Int {
        if plane != nil {
            return CVPixelBufferGetHeightOfPlane(self, plane!)
        } else {
            return CVPixelBufferGetHeight(self)
        }
    }
    
    func getBytesPerRow(plane: Int? = nil) -> Int{
        if plane != nil {
            return CVPixelBufferGetBytesPerRowOfPlane(self, plane!)
        } else {
            return CVPixelBufferGetBytesPerRow(self)
        }
    }
    
    func getBaseAddress(plane: Int? = nil) -> UnsafeMutableRawPointer?{
        if plane != nil {
            return CVPixelBufferGetBaseAddressOfPlane(self, plane!)
        } else {
            return CVPixelBufferGetBaseAddress(self)
        }
    }
    
    func getSize(plane: Int? = nil) -> CGSize {
        return CGSize(width: self.getWidth(plane: plane), height: self.getHeight(plane: plane))
    }
    
    func vImageBuffer(plane: Int? = nil, with data: UnsafeMutableRawPointer? = nil) -> vImage_Buffer {
        if data != nil {
            return vImage_Buffer(data: data,
                                 height: UInt(self.getHeight(plane: plane)),
                                 width: UInt(self.getWidth(plane: plane)),
                                 rowBytes: self.getBytesPerRow(plane: plane))
        } else {
            return vImage_Buffer(data: self.getBaseAddress(plane: plane),
                                 height: UInt(self.getHeight(plane: plane)),
                                 width: UInt(self.getWidth(plane: plane)),
                                 rowBytes: self.getBytesPerRow(plane: plane))
        }
    }
}

extension simd_float4x4 : Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try self.init(container.decode([SIMD4<Float>].self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        let columns = self.columns
        try container.encode([columns.0, columns.1, columns.2, columns.3])
    }
}
