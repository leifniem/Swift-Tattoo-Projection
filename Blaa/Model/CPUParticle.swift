import Foundation

final class CPUParticle : Equatable, Codable {
    static func == (lhs: CPUParticle, rhs: CPUParticle) -> Bool {
        return lhs.position == rhs.position
    }
    
    var position: simd_float3
    var normal: simd_float3
//    var color: simd_float3
    var confidence: Float
    
    init(position: simd_float3, normal: simd_float3, confidence: Float) {
        self.position = position
        self.normal = normal
        self.confidence = confidence
    }
}
