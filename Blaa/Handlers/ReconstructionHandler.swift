import Foundation
import Accelerate
import UIKit
import simd
//import GameplayKit

class ReconstructionHandler {
    
    let project: ScanProject
    let boundingBox: BoundingBox
    let vicinityRadius:simd_float1 = 0.02 // also smoothing factor
    let maxSmoothingIterations = 3
    let treeBox: Box
    let tree: Octree<CPUParticle>
    let currentTree: Octree<CPUParticle>
    let empty = simd_float3(0,0,0)
    let minimumCellSize: Float = 0.0001
    let adaptive = true
    let xAxis = simd_float3(1,0,0)
    let yAxis = simd_float3(0,1,0)
    let zAxis = simd_float3(0,0,1)
    
    init(project: ScanProject, boundingBox: BoundingBox) {
        self.project = project
        self.boundingBox = boundingBox
        self.treeBox = Box(boxMin: simd_float3(boundingBox.xMin, boundingBox.yMin, boundingBox.zMin), boxMax: simd_float3(boundingBox.xMax, boundingBox.yMax, boundingBox.zMax))
        self.tree = Octree(boundingBox: treeBox, minimumCellSize: Double(minimumCellSize))
        self.currentTree = tree
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
        
        for _ in 0...maxSmoothingIterations - 1 {
            let newTree = Octree<CPUParticle>(boundingBox: self.treeBox, minimumCellSize: Double(minimumCellSize))
            
            //    calculate weighted distance at center of node (multiplied by normal)
            var iterator = currentTree.makeIterator()
            while let node = iterator.next() {
                switch node.type {
                case .leaf:
                    var indicator = f(node.box.center)
                    if indicator > 0 {
                        indicator = min(vicinityRadius, indicator)
                    } else {
                        indicator = max(-vicinityRadius, indicator)
                    }
                    let newPoint = node.elements[0]
                    newPoint.position -= indicator * newPoint.normal
                    newPoint.normal = fN(newPoint.position)
                    newTree.add(newPoint, at: newPoint.position)
                default:
                    continue
                }
            }
            currentTree = newTree
        }
        
        //        Possible vertex reduction
        
        dualContour(currentTree)
    }
    
    //    Implicit function for surface estimation
    func f(_ x: simd_float3) -> simd_float1 {
        let vicinity = currentTree.elements(in: Box(boxMin: x - vicinityRadius, boxMax: x + vicinityRadius))
        var positions = empty
        var normals = empty
        var totalWeight:simd_float1 = 0
        vicinity?.forEach{ (point) in
            let weight = pow(1 - pow(simd_fast_length(x - point.position)/vicinityRadius, 2), 4) // Approximate Gaussian as in Guennebaud and Gross
            totalWeight += weight
            positions += weight * point.position
            normals += weight * point.normal
        }
        positions /= totalWeight
        normals /= totalWeight
        
        return simd_reduce_add(normals * (x - positions))
    }
    
    func fN(_ x: simd_float3) -> simd_float3{
        let vicinity = currentTree.elements(in: Box(boxMin: x - vicinityRadius, boxMax: x + vicinityRadius))
        var normals = empty
        var totalWeight:simd_float1 = 0
        vicinity?.forEach{ (point) in
            let weight = pow(1 - pow(simd_fast_length(x - point.position)/vicinityRadius, 2), 4) // Approximate Gaussian as in Guennebaud and Gross
            totalWeight += weight
            normals += weight * point.normal
        }
        normals /= totalWeight
        return normals
    }
    
    func dualContour(_ octree: Octree<CPUParticle>) {
        var finalVertices:[simd_float3] = []
        
//        Iterate leaves
        var iterator = octree.makeIterator()
        while let node = iterator.next() {
            switch node.type {
            case .leaf:
                if adaptive {
                    var tempVerts: [simd_float3: simd_float1] = [:]
                    let v0 = node.box.boxMin
                    let v1 = simd_float3(node.box.boxMin.x, node.box.boxMax.y, node.box.boxMin.z)
                    let v2 = simd_float3(node.box.boxMin.x, node.box.boxMin.y, node.box.boxMax.z)
                    let v3 = simd_float3(node.box.boxMin.x, node.box.boxMax.y, node.box.boxMax.z)
                    let v4 = simd_float3(node.box.boxMax.x, node.box.boxMin.y, node.box.boxMin.z)
                    let v5 = simd_float3(node.box.boxMax.x, node.box.boxMin.y, node.box.boxMax.z)
                    let v6 = simd_float3(node.box.boxMax.x, node.box.boxMax.y, node.box.boxMin.z)
                    let v7 = node.box.boxMax
//                    Calculate Function at Cell corners
                    for v in [v0,v1,v2,v3,v4,v5,v6,v7] {
                        tempVerts[v] = f(v)
                    }
                    var changes: [simd_float3] = []
//                    Sign Edges and calc interpolation if changed
                    for edge in [(v1, v3), (v6, v7), (v3, v7), (v1, v6), (v0, v1), (v2, v3), (v4, v6), (v5, v7), (v0, v2), (v4, v5), (v0, v4), (v2, v5)] {
                        if ((tempVerts[edge.0]! > 0) != (tempVerts[edge.1]! > 0)) {
                            changes.append(lerp(edge.0, edge.1, t: ((0 - (tempVerts[edge.0]!)) / (tempVerts[edge.1]! - tempVerts[edge.0]!))))
                        }
                    }
                    if changes.count <= 1 {
                        continue
                    }
                    var normals: [simd_float3] = []
                    for vert in changes {
                        normals.append(fN(vert))
                    }
                    
                    finalVertices.append(solveQEF(position: node.box.center, changes: changes, normals: normals))
                } else {
                    finalVertices.append(node.box.center)
                }
                
            default:
                continue
            }
        }
    }
    
    
    func solveQEF(position: simd_float3, changes: [simd_float3], normals: [simd_float3]) -> simd_float3 {
        var tempA: [[simd_float1]] = [[],[],[]]
        normals.forEach{ vec in
            tempA[0].append(vec.x)
            tempA[1].append(vec.y)
            tempA[2].append(vec.z)
        }
        var a: [simd_float1] = tempA.flatMap{$0}
        var aVals = a
        
        var b: [simd_float1] = zip(changes, normals).map{ (vert, normal) -> simd_float1 in
            simd_reduce_add(vert * normal)
        }
        var bVals = b
        
        var result = [Float](repeating: 0.0, count: bVals.count)
        var resultBuffer = result
        var rowIndices: [Int32] = [[Int32]](repeating: [0,1,2], count: normals.count * 3).flatMap{$0}
        var columnStarts = [0, normals.count - 1, normals.count * 2 - 1]
        
        let matrixStructure = rowIndices.withUnsafeMutableBufferPointer { rowIndicesPointer in
            columnStarts.withUnsafeMutableBufferPointer { columnStartsPointer in
                return  SparseMatrixStructure(rowCount: Int32(normals.count), columnCount: 3, columnStarts: columnStartsPointer.baseAddress!, rowIndices: rowIndicesPointer.baseAddress!, attributes: SparseAttributes_t(), blockSize: 1)
            }
        }
        
        aVals.withUnsafeMutableBufferPointer{ Apointer in
            let A = SparseMatrix_Float(structure: matrixStructure, data: Apointer.baseAddress!)
            
            bVals.withUnsafeMutableBufferPointer{ Bpointer in
                resultBuffer.withUnsafeMutableBufferPointer{ ResultPointer in
                    let B = DenseVector_Float(count: Int32(b.count), data: Bpointer.baseAddress!)
                    let results = DenseVector_Float(count: Int32(result.count), data: ResultPointer.baseAddress!)
                    
                    let status = SparseSolve(SparseLSMR(), A, B, results, SparsePreconditionerDiagScaling)
                    if status != SparseIterativeConverged {
                        fatalError("Failed to converge points")
                    }
                    
                }
            }
        }
        
        return simd_float3(resultBuffer)
    }
    
}
