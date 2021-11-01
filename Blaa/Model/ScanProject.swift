import Foundation
import CoreVideo
import UIKit
import AVFoundation
import Gzip
import ExtrasJSON
import ModelIO
import MetalKit
import SwiftUI
import StickyEncoding

class ProjectSpatialData : Codable {
    var pointCloud: [CPUParticle]?
    var viewMatrices: [matrix_float4x4]?
    var projectionMatrices: [matrix_float4x4]?
}

class ScanProject : Codable {
    
    enum Constants {
        static let videoName : String = "baseVideo.mp4"
        static let metaName : String = "meta.skinmeta"
        static let dataName : String = "data.skin"
        static let thumbnailName : String = "thumb.jpg"
        static let modelName : String = "model.stl"
    }
    
    var title: String!
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
    private var thumb: UIImage?
    private var bbox: Box?
    //    private var sketchTexture: UIImage?
    //    private var uvMap: UIImage?
    
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
    var viewMatrices: [matrix_float4x4]? {
        get {return self.spatialData.viewMatrices}
    }
    var viewMatrixBuffer: [matrix_float4x4]? {
        get {return self.spatialData.viewMatrices}
    }
    var projectionMatrixBuffer: [matrix_float4x4]? {
        get {return self.spatialData.projectionMatrices}
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
                "texture": hasTexture,
                "model": hasModel,
                "video": hasVideo,
                "uv": hasUV,
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
    
    enum ScanProjectDataCodingKeys: String, CodingKey {
        case pointCloud
        case viewProjectionMatrixes
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
    
    func setRawVideoData(data: [CVPixelBuffer]) {
        self.rawVideoData = data
        self.writeVideo()
        self.hasVideo = true
        self.triggerModified()
    }
    
    func setMatrices(viewMatrices: [matrix_float4x4], projectionMatrices: [matrix_float4x4]) {
        self.spatialData.viewMatrices = viewMatrices
        self.spatialData.projectionMatrices = projectionMatrices
        self.triggerModified()
    }
    
    func setPointCloud(data: [CPUParticle]) {
        self.spatialData.pointCloud = data
        self.triggerModified(spatial: true)
    }
    
    func getParticleUniforms() -> [ParticleUniforms] {
        var uniformsCloud = [ParticleUniforms]()
        pointCloud?.forEach{ point in
            if self.bbox == nil {
                var uniforms = ParticleUniforms()
                uniforms.position = point.position
                uniformsCloud.append(uniforms)
            }else if self.bbox != nil && self.bbox!.contains(point.position){
                var uniforms = ParticleUniforms()
                uniforms.position = point.position
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
            let bytes = try BinaryEncoder().encode(self)
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
                    let json = try BinaryEncoder().encode(self.spatialData)
                    let jsonData = Data(json)
                    try jsonData.write(to: self.folderURL.appendingPathComponent(Constants.dataName))
                } catch {
                    fatalError("Error while encoding spatial data of project \(self.title!).")
                }
            }
        }
    }
    
    func decodeSpatial() {
        do {
            let jsonData = try Data(contentsOf: self.folderURL.appendingPathComponent(Constants.dataName))
            let spatialData = try BinaryDecoder().decode(ProjectSpatialData.self, from: [UInt8](jsonData))
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
        if self.hasModel{ self.readModel() }
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
        
        //        DispatchQueue.global(qos: .background).async {
        //            DispatchQueue.main.async { [self] in
        handler.writeVideo(rawVideoData: self.rawVideoData!, videoURL: self.baseVideoUrl!)
        //            }
        //        }
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
    
    // MARK: - UV MAPPING
    //    func setUVCoords
    //    func exportUVMap
    
}
