import Foundation
import CoreVideo
import UIKit
import AVFoundation
import Gzip
import ExtrasJSON
import ModelIO
import MetalKit
import SwiftUI
import ExtrasJSON

class ProjectSpatialData : Codable {
    var pointCloud: [CPUParticle]?
    var viewProjectionMatrices: [matrix_float4x4]?
    
    enum ScanProjectDataCodingKeys: String, CodingKey {
        //        case pointCloud
        case viewProjectionMatrixes
    }
    
    init(){}
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ScanProjectDataCodingKeys.self)
        try container.encode(viewProjectionMatrices, forKey: .viewProjectionMatrixes)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ScanProjectDataCodingKeys.self)
        self.viewProjectionMatrices = try container.decode([matrix_float4x4].self, forKey: .viewProjectionMatrixes)
    }
}

class ScanProject : Codable, Equatable {
    static func == (lhs: ScanProject, rhs: ScanProject) -> Bool {
        return lhs.uuid == rhs.uuid
    }
    
    
    enum Constants {
        static let videoName : String = "baseVideo.mp4"
        static let depthVideoName : String = "depth.mp4"
        static let metaName : String = "meta.skinmeta"
        static let dataName : String = "data.skin"
        static let thumbnailName : String = "thumb.jpg"
        static let sketchName : String = "sketch.PNG"
        static let uvName : String = "uv.JPG"
        static let modelName : String = "model.obj"
        static let cloudFileName : String = "cloud.ply"
    }
    
    internal var title: String!
    private let uuid: UUID
    private let creationDate: Date
    private var modifiedDate: Date
    private var folderURL: URL
    private var baseVideoUrl: URL?
    private var mesh: MTKMesh?
    private var modelVertexDescriptor: MTLVertexDescriptor?
    private var hasVideo: Bool
    private var hasModel: Bool
    private var hasUV: Bool
    private var hasTexture: Bool
    private var spatialData: ProjectSpatialData
    private var rawVideoData: [CVPixelBuffer]?
    private var rawDepthData: [CVPixelBuffer]?
    private var thumb: UIImage?
    private var bbox: Box?
    private var sketchTexture: UIImage?
    private var uvMap: UIImage?
    
    var id: UUID {
        get {return self.uuid}
    }
    
    var created: Date {
        get {return self.creationDate}
    }
    var modified: Date {
        get {return self.modifiedDate}
    }
    var videoFrames: [CVPixelBuffer]? {
        get {return self.rawVideoData}
    }
    var matrixBuffer: [matrix_float4x4]? {
        get {return self.spatialData.viewProjectionMatrices}
    }
    var pointCloud: [CPUParticle]? {
        get {return self.spatialData.pointCloud}
    }
    var thumbnail: UIImage? {
        get {return self.thumb}
    }
    var boundingBox: Box? {
        get {return self.bbox}
    }
    var folder: URL? {
        get {return self.folderURL}
    }
    var resources: [String: Bool] {
        get {
            return [
                "texture": self.hasTexture,
                "model": self.hasModel,
                "video": self.hasVideo,
                "uv": self.hasUV,
            ]
        }
    }
    var model: MTKMesh? {
        get {
            return self.mesh
        }
    }
    var modelPath: URL? {
        get {
            return self.folderURL.appendingPathComponent(Constants.modelName)
        }
    }
    var vertexDescriptor: MTLVertexDescriptor? {
        return self.modelVertexDescriptor
    }
    var sketch: UIImage? {
        return self.sketchTexture
    }
    var uvAtlas: UIImage? {
        return self.uvMap
    }
    
    enum ScanProjectMetaCodingKeys: String, CodingKey {
        case title
        case uuid
        case creationDate
        case modifiedDate
        case hasVideo
        case hasModel
        case hasUV
        case hasTexture
        case bbox
    }
    
    init() {
        self.uuid = UUID()
        self.title = "Untitled Scan"
        self.creationDate = Date()
        self.modifiedDate = self.creationDate
        self.hasVideo = false
        self.hasModel = false
        self.hasUV = false
        self.hasTexture = false
        self.spatialData = ProjectSpatialData()
        self.folderURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(self.uuid.uuidString)
        do {try FileManager.default.createDirectory(atPath: self.folderURL.path, withIntermediateDirectories: true, attributes: nil)} catch {
            fatalError("Could not create projectFolder")
        }
        self.folderURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(self.uuid.uuidString)
        do {try FileManager.default.createDirectory(atPath: self.folderURL.path, withIntermediateDirectories: true, attributes: nil)} catch {
            fatalError("Could not create projectFolder")
        }
        DispatchQueue.global(qos: .background).async {
            DispatchQueue.main.async { [self] in
                self.writeProjectFiles()
            }
        }
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ScanProjectMetaCodingKeys.self)
        self.uuid = try container.decode(UUID.self, forKey: .uuid)
        self.title = try container.decode(String.self, forKey: .title)
        self.creationDate = try container.decode(Date.self, forKey: .creationDate)
        self.modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
        self.hasVideo = try container.decode(Bool.self, forKey: .hasVideo)
        self.hasModel = try container.decode(Bool.self, forKey: .hasModel)
        self.hasUV = try container.decode(Bool.self, forKey: .hasUV)
        self.hasTexture = try container.decode(Bool.self, forKey: .hasTexture)
        self.hasVideo = try container.decode(Bool.self, forKey: .hasVideo)
        self.bbox = try container.decodeIfPresent(Box.self, forKey: .bbox)
        self.spatialData = ProjectSpatialData()
        
        self.folderURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(self.uuid.uuidString)
        
        if self.hasVideo {
            self.getThumbnail()
            self.baseVideoUrl = self.folderURL.appendingPathComponent(Constants.videoName)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ScanProjectMetaCodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(title, forKey: .title)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(modifiedDate, forKey: .modifiedDate)
        try container.encode(hasVideo, forKey: .hasVideo)
        try container.encode(hasModel, forKey: .hasModel)
        try container.encode(hasUV, forKey: .hasUV)
        try container.encode(hasTexture, forKey: .hasTexture)
        try container.encode(hasVideo, forKey: .hasVideo)
        try container.encodeIfPresent(bbox, forKey: .bbox)
    }
    
    func triggerModified(spatial: Bool? = false) {
        self.modifiedDate = Date()
        self.writeProjectFiles(spatial: spatial)
    }
    
    func setTitle(_ name: String) {
        self.title = name
        self.triggerModified()
    }
    
    func setRawVideoData(data: [CVPixelBuffer], depthData: [CVPixelBuffer]) {
        self.rawVideoData = data
        self.rawDepthData = depthData
        self.writeVideo()
        self.hasVideo = true
        self.triggerModified()
    }
    
    func setMatrices(matrices: [matrix_float4x4]) {
        self.spatialData.viewProjectionMatrices = matrices
        self.triggerModified()
    }
    
    func setPointCloud(data: [CPUParticle]) {
        self.spatialData.pointCloud = data
        self.triggerModified(spatial: true)
    }
    
    func getParticleUniforms() -> [ParticleUniforms] {
        var uniformsCloud = [ParticleUniforms]()
        let hasToReduce = simd_reduce_max(pointCloud![0].color) > 1
        pointCloud?.forEach{ point in
            if self.bbox == nil {
                var uniforms = ParticleUniforms()
                uniforms.position = point.position
                uniforms.color = hasToReduce ? point.color / 255.0 : point.color
                uniforms.normal = point.normal
                uniformsCloud.append(uniforms)
            }else if self.bbox != nil && self.bbox!.contains(point.position){
                var uniforms = ParticleUniforms()
                uniforms.position = point.position
                uniforms.color = hasToReduce ? point.color / 255.0 : point.color
                uniforms.normal = point.normal
                uniformsCloud.append(uniforms)
            }
        }
        return uniformsCloud
    }
    
    func setBoundingBox(_ bb: Box) {
        self.bbox = bb
        self.triggerModified()
    }
    
    func writeProjectFiles(spatial: Bool? = false) {
        do {
            let bytes = try XJSONEncoder().encode(self)
            let byteData = Data(bytes)
            try byteData.write(to: self.folderURL.appendingPathComponent(Constants.metaName))
        } catch _ {
            fatalError("Failure writing projectMetadata")
        }
        
        if spatial!{
            self.encodeSpatial()
        }
    }
    
    func encodeSpatial () {
        DispatchQueue.global(qos: .background).async {
            DispatchQueue.main.async { [self] in
                do {
                    let json = try XJSONEncoder().encode(self.spatialData)
                    let jsonData = Data(json)
                    try jsonData.write(to: self.folderURL.appendingPathComponent(Constants.dataName))
                } catch {
                    fatalError("Error while encoding spatial data of project \(self.title!).")
                }
                self.writePointCloud()
            }
        }
    }
    
    func decodeSpatial() {
        do {
            let jsonData = try Data(contentsOf: self.folderURL.appendingPathComponent(Constants.dataName))
            let spatialData = try XJSONDecoder().decode(ProjectSpatialData.self, from: jsonData)
            self.spatialData = spatialData
        } catch {
            fatalError("Error while decoding spatial data of project \(self.title!).")
        }
    }
    
    func deleteProject() {
        do {
            try FileManager.default.removeItem(at: folderURL)
        } catch {
            fatalError("Could not delete project \"\(self.title!)\" (\(self.uuid.uuidString).")
        }
    }
    
    func loadFullData() {
        self.readVideo()
        if self.hasModel{
            self.readModel()
        } else {
            self.readPointCloud()
        }
        if self.hasTexture{ self.readSketch() }
        if self.hasUV{ self.readUVMap() }
        self.decodeSpatial()
    }
    
    // MARK: - VIDEO
    func writeVideo() {
        guard self.rawVideoData!.count > 0 else{
            return
        }
        
        self.baseVideoUrl = URL.init(string: Constants.videoName, relativeTo: self.folderURL)
        
        let handler = VideoHandler()
        
        self.thumb = UIImage(pixelBuffer: self.rawVideoData![0])
        self.thumb = thumb?.rotate(radians: .pi / 2)
        if let imageData = self.thumb?.jpegData(compressionQuality: 0.7) {
            do{
                try imageData.write(to: folderURL.appendingPathComponent(Constants.thumbnailName))
            } catch {
                fatalError("Could not write thumbnail to disk.")
            }
        }
        
        handler.writeVideo(rawVideoData: self.rawVideoData!, videoURL: self.baseVideoUrl!)
        handler.encodeDepth(
            depthBuffer: self.rawDepthData!,
            url: self.folderURL.appendingPathComponent(Constants.depthVideoName)
        )
    }
    
    func readVideo() {
        self.baseVideoUrl = URL.init(string: Constants.videoName, relativeTo: self.folderURL)
        let handler = VideoHandler()
        self.rawVideoData = handler.readVideo(url: folderURL.appendingPathComponent(Constants.videoName))
    }
    
    func getThumbnail() {
        do {
            self.thumb = UIImage(data: try Data(
                contentsOf: folderURL.appendingPathComponent(Constants.thumbnailName)
            ))
        } catch _ {
            print("\(self.title!) has no thumbnail.")
        }
    }
    //    func exportProjectedVideo
    
    
    // MARK: - POINT CLOUD
    func writePointCloud() {
        let lowerColor = simd_float3(repeating: 0)
        let upperColor = simd_float3(repeating: 255)
        var fileToWrite = ""
        let headers = ["ply", "format ascii 1.0", "element vertex \(self.pointCloud!.count)", "property float x", "property float y", "property float z", "property float nx", "property float ny", "property float nz", "property uchar red", "property uchar green", "property uchar blue", "property uchar alpha", "element face 0", "property list uchar int vertex_indices", "end_header"]
        for header in headers {
            fileToWrite += header
            fileToWrite += "\r\n"
        }
        
        for i in 0..<self.pointCloud!.count {
            let point = self.pointCloud![i]
            let colors = (point.color * 255.0).clamped(lowerBound: lowerColor, upperBound: upperColor)
            let red = Int(colors.x)
            let green = Int(colors.y)
            let blue = Int(colors.z)
            let pvValue = "\(point.position.x) \(point.position.y) \(point.position.z) \(point.normal.x) \(point.normal.y) \(point.normal.z) \(Int(red)) \(Int(green)) \(Int(blue)) 255"
            fileToWrite += pvValue
            fileToWrite += "\r\n"
        }
        do {
            try fileToWrite.write(to: self.folderURL.appendingPathComponent(Constants.cloudFileName), atomically: true, encoding: .ascii)
        }
        catch {
            print("Failed to write PLY file", error)
        }
    }
    
    func readPointCloud() {
        let contents = try? String(contentsOf: self.folderURL.appendingPathComponent(Constants.cloudFileName), encoding: .ascii)
        let lines = contents?.components(separatedBy: .newlines)
        self.spatialData.pointCloud = [CPUParticle]()
        lines?.forEach{ line in
            //            x y z nx ny nz r g b a
            let components = line.split(separator: " ")
            if components.count == 10 {
                self.spatialData.pointCloud!.append(CPUParticle(
                    position: simd_float3(Float(components[0])!, Float(components[1])!, Float(components[2])!),
                    normal: simd_float3(Float(components[3])!, Float(components[4])!, Float(components[5])!),
                    color: simd_float3(Float(components[6])!, Float(components[7])!, Float(components[8])!)
                )
                )
            }
        }
    }
    
    // MARK: - 3D MODEL
    func setFileWritten() {
        self.hasModel = true
        self.readModel()
        self.triggerModified()
    }
    
    func readModel() {
        let device = MTLCreateSystemDefaultDevice()!
        let modelUrl = self.folderURL.appendingPathComponent(Constants.modelName)
        let allocator = MTKMeshBufferAllocator(device: device)
        
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        vertexDescriptor.attributes[3] = MDLVertexAttribute(name: MDLVertexAttributeColor, format: .float3, offset: 32, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 44)
        
        let asset = MDLAsset(
            url: modelUrl,
            vertexDescriptor: vertexDescriptor,
            bufferAllocator: allocator
        )
        //        let asset = MDLAsset(url: modelUrl)
        let meshes = asset.childObjects(of: MDLMesh.self) as! [MDLMesh]
        
        //        self.modelPipelineState = MTLRenderPipelineDescriptor()
        self.modelVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        guard meshes.first != nil else {
            fatalError("No mesh found in obj.")
        }
        do {
            self.mesh = try MTKMesh(mesh: meshes.first!, device: device)
        } catch {
            fatalError("\(error)")
        }
    }
    
    //    MARK: - SKETCH HANDLING
    func readSketch() {
        do {
            self.sketchTexture = UIImage(data: try Data(
                contentsOf: folderURL.appendingPathComponent(Constants.sketchName)
            ))
        } catch {
            fatalError("Could not load sketch from disk.")
        }
    }
    
    func setSketch(_ image: UIImage) {
        self.sketchTexture = image
        if let imageData = image.pngData() {
            do{
                try imageData.write(to: folderURL.appendingPathComponent(Constants.sketchName))
            } catch {
                fatalError("Could not write sketch file to disk.")
            }
        }
        self.hasTexture = true
        self.triggerModified()
    }
    
    func deleteSketch() {
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(Constants.sketchName))
        self.sketchTexture = nil
        self.hasTexture = false
        self.triggerModified()
    }
    
    // MARK: - UV MAPPING
    func setUVMap(_ uvMap: UIImage) {
        self.uvMap = uvMap
        self.exportUVMap()
        self.hasUV = true
        self.triggerModified()
    }
    
    func exportUVMap() {
        try! self.uvMap?.jpegData(compressionQuality: 0.7)?.write(to: self.folderURL.appendingPathComponent(Constants.uvName))
        UIImageWriteToSavedPhotosAlbum(self.uvMap!, nil, nil, nil)
    }
    
    func readUVMap() {
        do {
            self.uvMap = UIImage(data: try Data(
                contentsOf: folderURL.appendingPathComponent(Constants.uvName)
            ))
        } catch {
            fatalError("Could not load sketch from disk.")
        }
    }
}
