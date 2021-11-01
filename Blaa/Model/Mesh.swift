protocol Face {
    var indices: [Int] { get }
}

class QuadFace: Face {
    let v1: Int
    let v2: Int
    let v3: Int
    let v4: Int
    
    init(_ v1: Int, _ v2: Int, _ v3: Int, _ v4: Int, reverseOrder: Bool?) {
        if reverseOrder ?? true {
            self.v1 = v1
            self.v2 = v2
            self.v3 = v3
            self.v4 = v4
        } else {
            self.v1 = v4
            self.v2 = v3
            self.v3 = v2
            self.v4 = v1
        }
    }
    
    var indices: [Int] {
        get{
            return [v1, v2, v3, v4]
        }
    }
}

class TriFace: Face {
    let v1: Int
    let v2: Int
    let v3: Int
    
    init(_ v1: Int, _ v2: Int, _ v3: Int, reverseOrder: Bool? = false) {
        if reverseOrder ?? true {
            self.v1 = v1
            self.v2 = v2
            self.v3 = v3
        } else {
            self.v1 = v3
            self.v2 = v2
            self.v3 = v1
        }
    }
    
    var indices: [Int] {
        get{
            return [v1, v2, v3]
        }
    }
}

class Mesh {
    let faceArray: [Face]
    let vertArray: [simd_float3]
    let normalsArray: [simd_float3]?
    
    init(vertices: [simd_float3], faces: [Face], normals: [simd_float3]? = nil){
        self.vertArray = vertices
        self.faceArray = faces
        self.normalsArray = normals
    }
    
    var faces: [Face] {
        get {
            return faceArray
        }
    }
    
    var vertices: [simd_float3] {
        get {
            return vertArray
        }
    }
    
    var normals: [simd_float3]? {
        get {
            return normalsArray
        }
    }
    
    func toObjString() -> String {
        var obj = ""
        self.vertArray.forEach { vert in
            obj += "v \(vert.x) \(vert.y) \(vert.z)\n"
        }
        if self.normalsArray != nil {
            self.normalsArray!.forEach { normal in
                obj += "vn \(normal.x) \(normal.y) \(normal.z)\n"
            }
        }
        self.faceArray.forEach { face in
            let indices = face.indices
            if indices.count == 4 {
                obj += "f \(indices[0]) \(indices[1]) \(indices[2]) \(indices[3])"
            } else {
                obj += "f \(indices[0]) \(indices[1]) \(indices[2])"
            }
        }
        return obj
    }
}

