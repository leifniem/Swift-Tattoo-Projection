import Foundation
import Accelerate
import UIKit
//import GameplayKit

class ReconstructionHandler {
    
    let project: ScanProject
    let boundingBox: BoundingBox
    let vicinityRadius:simd_float1 = 0.05 // also smoothing factor
    let maxSmoothingIterations = 3
    let treeBox: Box
    let tree: Octree<CPUParticle>
    let empty = simd_float3(0,0,0)
    
    init(project: ScanProject, boundingBox: BoundingBox) {
        self.project = project
        self.boundingBox = boundingBox
        self.treeBox = Box(boxMin: simd_float3(boundingBox.xMin, boundingBox.yMin, boundingBox.zMin), boxMax: simd_float3(boundingBox.xMax, boundingBox.yMax, boundingBox.zMax))
        self.tree = Octree(boundingBox: treeBox, minimumCellSize: 0.0001)
    }
    
    func reconstruct() {
        //    Invert Normals
        //    Generate - all points to leaf nodes
        project.pointCloud?.forEach{ (point) in
//            point.normal = -point.normal
            tree.add(point, at: point.position)
//            return point
        }
        
        var currentTree = tree
        
        var smoothingIteration = 0
        while smoothingIteration < maxSmoothingIterations {
            let newTree = Octree<CPUParticle>(boundingBox: self.treeBox, minimumCellSize: 0.0001)
            
            //    calculate weighted distance at center of node (multiplied by normal)
            var iterator = currentTree.makeIterator()
            while let node = iterator.next() {
                switch node.type {
                case .leaf:
                    var scalar = f(node.box.center)
                    if scalar > 0 {
                        scalar = min(vicinityRadius, scalar)
                    } else {
                        scalar = max(-vicinityRadius, scalar)
                    }
                    let newPoint = node.elements[0]
                    newPoint.position -= scalar * newPoint.normal
                    newTree.add(newPoint, at: newPoint.position)
                default:
                    continue
                }
            }
            
            smoothingIteration += 1
            currentTree = newTree
        }
        
        
    }
    
//    Implicit function for surface estimation
    func f(_ x: simd_float3) -> simd_float1 {
        let vicinity = tree.elements(in: Box(boxMin: x - vicinityRadius, boxMax: x + vicinityRadius))
        var positions = empty
        var normals = empty
        var totalWeight:simd_float1 = 0
        vicinity?.forEach{ (point) in
            let weight = pow(1 - pow(simd_length(x - point.position)/vicinityRadius, 2), 4) // Approximate Gaussian as in Guennebaud and Gross
            totalWeight += weight
            positions += weight * point.position
            normals += weight * point.normal
        }
        positions /= totalWeight
        normals /= totalWeight
        
        return simd_reduce_add(normals * (x - positions))
    }

}
