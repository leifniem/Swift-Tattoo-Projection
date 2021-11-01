//  https://github.com/raywenderlich/swift-algorithm-club/blob/master/Octree/Octree.playground/Sources/Octree.swift

import GameplayKit
import simd

public class OctreeNode<T: Equatable>: CustomStringConvertible {
    let box: Box
    var point: simd_float3!
    var elements: [T]!
    var type: NodeType = .leaf
    
    enum NodeType {
        case leaf
        case `internal`(children: Children)
    }
    
    public var description: String {
        switch type {
        case .leaf:
            return "leaf node with \(box) elements: \(elements)"
        case .internal:
            return "internal node with \(box)"
        }
    }
    
    var recursiveDescription: String {
        return recursiveDescription(withTabCount: 0)
    }
    
    private func recursiveDescription(withTabCount count: Int) -> String {
        let indent = String(repeating: "\t", count: count)
        var result = "\(indent)" + description + "\n"
        switch type {
        case .internal(let children):
            for child in children {
                result += child.recursiveDescription(withTabCount: count + 1)
            }
        default:
            break
        }
        return result
    }
    
    public struct Children: Sequence {
        let frontLeftTop: OctreeNode
        let frontLeftBottom: OctreeNode
        let frontRightTop: OctreeNode
        let frontRightBottom: OctreeNode
        let backLeftTop: OctreeNode
        let backLeftBottom: OctreeNode
        let backRightTop: OctreeNode
        let backRightBottom: OctreeNode
        
        init(parentNode: OctreeNode) {
            frontLeftTop = OctreeNode(box: parentNode.box.frontLeftTop)
            frontLeftBottom = OctreeNode(box: parentNode.box.frontLeftBottom)
            frontRightTop = OctreeNode(box: parentNode.box.frontRightTop)
            frontRightBottom = OctreeNode(box: parentNode.box.frontRightBottom)
            backLeftTop = OctreeNode(box: parentNode.box.backLeftTop)
            backLeftBottom = OctreeNode(box: parentNode.box.backLeftBottom)
            backRightTop = OctreeNode(box: parentNode.box.backRightTop)
            backRightBottom = OctreeNode(box: parentNode.box.backRightBottom)
        }
        
        public struct ChildrenIterator: IteratorProtocol {
            var index = 0
            let children: Children
            
            init(children: Children) {
                self.children = children
            }
            
            public mutating func next() -> OctreeNode? {
                defer { index += 1 }
                switch index {
                case 0: return children.frontLeftTop
                case 1: return children.frontLeftBottom
                case 2: return children.frontRightTop
                case 3: return children.frontRightBottom
                case 4: return children.backLeftTop
                case 5: return children.backLeftBottom
                case 6: return children.backRightTop
                case 7: return children.backRightBottom
                default: return nil
                }
            }
        }
        
        public func makeIterator() -> ChildrenIterator {
            return ChildrenIterator(children: self)
        }
    }
    
    init(box: Box) {
        self.box = box
    }
    
    @discardableResult
    func add(_ element: T, at point: simd_float3) -> OctreeNode? {
        return tryAdd(element, at: point)
    }
    
    private func tryAdd(_ element: T, at point: simd_float3) -> OctreeNode? {
        if !box.contains(point) {
            return nil
        }
        
        switch type {
        case .internal(let children):
            // pass the point to one of the children
            for child in children {
                if let child = child.tryAdd(element, at: point) {
                    return child
                }
            }
            
            fatalError("box.contains evaluted to true, but none of the children added the point")
        case .leaf:
            if self.point != nil {
                // leaf already has an asigned point
                if self.point == point {
                    self.elements.append(element)
                    return self
                } else {
                    return subdivide(adding: element, at: point)
                }
            } else {
                self.elements = [element]
                self.point = point
                return self
            }
        }
    }
    
    func add(_ elements: [T], at point: simd_float3) {
        for element in elements {
            self.add(element, at: point)
        }
    }
    
    @discardableResult
    func remove(_ element: T) -> Bool {
        switch type {
        case .leaf:
            if let elements = self.elements {
                // leaf contains one ore more elements
                if let index = elements.firstIndex(of: element) {
                    // leaf contains the element we want to remove
                    self.elements.remove(at: index)
                    // if elements is now empty remove it
                    if self.elements.isEmpty {
                        self.elements = nil
                    }
                    return true
                }
            }
            return false
        case .internal(let children):
            for child in children  {
                if child.remove(element) {
                    return true
                }
            }
            return false
        }
    }
    
    func elements(at point: simd_float3) -> [T]? {
        switch type {
        case .leaf:
            if self.point == point {
                return self.elements
            }
        case .internal(let children):
            for child in children {
                if child.box.contains(point) {
                    return child.elements(at: point)
                }
            }
        }
        // tree does not contain given point
        return nil
    }
    
    func elements(in box: Box) -> [T]? {
        var values: [T] = []
        switch type {
        case .leaf:
            // check if leaf has an assigned point
            if let point = self.point {
                // check if point is inside given box
                if box.contains(point) {
                    values += elements ?? []
                }
            }
        case .internal(let children):
            for child in children {
                if child.box.isContained(in: box) {
                    // child is contained in box
                    // add all children of child
                    values += child.elements(in: child.box) ?? []
                } else if child.box.contains(box) || child.box.intersects(box) {
                    // child contains at least part of box
                    values += child.elements(in: box) ?? []
                }
                // child does not contain any part of given box
            }
        }
        if values.isEmpty { return nil }
        return values
    }
    
    private func subdivide(adding element: T, at point: simd_float3) -> OctreeNode? {
        precondition(self.elements != nil, "Subdividing while leaf does not contain a element")
        precondition(self.point != nil, "Subdividing while leaf does not contain a point")
        switch type {
        case .leaf:
            type = .internal(children: Children(parentNode: self))
            // add element previously contained in leaf to children
            self.add(self.elements, at: self.point)
            self.elements = nil
            self.point = nil
            // add new element to children
            return self.add(element, at: point)
        case .internal:
            preconditionFailure("Calling subdivide on an internal node")
        }
    }
}

public class Octree<T: Equatable>: CustomStringConvertible {
    var root: OctreeNode<T>
    
    public var description: String {
        return "Octree\n" + root.recursiveDescription
    }
    
    public init(boundingBox: GKBox, minimumCellSize: Float) {
        root = OctreeNode<T>(box: boundingBox)
    }
    
    @discardableResult
    public func add(_ element: T, at point: simd_float3) -> OctreeNode<T>? {
        return root.add(element, at: point)
    }
    
    @discardableResult
    public func remove(_ element: T, using node: OctreeNode<T>) -> Bool {
        return node.remove(element)
    }
    
    @discardableResult
    public func remove(_ element: T) -> Bool {
        return root.remove(element)
    }
    
    public func elements(at point: simd_float3) -> [T]? {
        return root.elements(at: point)
    }
    
    public func elements(in box: GKBox) -> [T]? {
        precondition(root.box.contains(box), "box is outside of octree bounds")
        return root.elements(in: box)
    }
    
    //    public func makeIterator() -> OctreeNode<T>.Children.ChildrenIterator{
    //        return OctreeNode<T>.Children(parentNode:self.root).makeIterator()
    //    }
}

extension GKBox {
    public var boxSize: simd_float3 {
        return boxMax - boxMin
    }
    
    var halfBoxSize: simd_float3 {
        return boxSize/2
    }
    
    var center: simd_float3 {
        return (boxMin + boxMax)/2
    }
    
    var frontLeftTop: GKBox {
        let boxMin = self.boxMin + simd_float3(0, halfBoxSize.y, halfBoxSize.z)
        let boxMax = self.boxMax - simd_float3(halfBoxSize.x, 0, 0)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var frontLeftBottom: GKBox {
        let boxMin = self.boxMin + simd_float3(0, 0, halfBoxSize.z)
        let boxMax = self.boxMax - simd_float3(halfBoxSize.x, halfBoxSize.y, 0)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var frontRightTop: GKBox {
        let boxMin = self.boxMin + simd_float3(halfBoxSize.x, halfBoxSize.y, halfBoxSize.z)
        let boxMax = self.boxMax - simd_float3(0, 0, 0)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var frontRightBottom: GKBox {
        let boxMin = self.boxMin + simd_float3(halfBoxSize.x, 0, halfBoxSize.z)
        let boxMax = self.boxMax - simd_float3(0, halfBoxSize.y, 0)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var backLeftTop: GKBox {
        let boxMin = self.boxMin + simd_float3(0, halfBoxSize.y, 0)
        let boxMax = self.boxMax - simd_float3(halfBoxSize.x, 0, halfBoxSize.z)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var backLeftBottom: GKBox {
        let boxMin = self.boxMin + simd_float3(0, 0, 0)
        let boxMax = self.boxMax - simd_float3(halfBoxSize.x, halfBoxSize.y, halfBoxSize.z)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var backRightTop: GKBox {
        let boxMin = self.boxMin + simd_float3(halfBoxSize.x, halfBoxSize.y, 0)
        let boxMax = self.boxMax - simd_float3(0, 0, halfBoxSize.z)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    var backRightBottom: GKBox {
        let boxMin = self.boxMin + simd_float3(halfBoxSize.x, 0, 0)
        let boxMax = self.boxMax - simd_float3(0, halfBoxSize.y, halfBoxSize.z)
        return GKBox(boxMin: boxMin, boxMax: boxMax)
    }
    
    public func contains(_ point: simd_float3) -> Bool {
        return (boxMin.x <= point.x && point.x <= boxMax.x) && (boxMin.y <= point.y && point.y <= boxMax.y) && (boxMin.z <= point.z && point.z <= boxMax.z)
    }
    
    public func contains(_ box: GKBox) -> Bool {
        return
        self.boxMin.x <= box.boxMin.x &&
        self.boxMin.y <= box.boxMin.y &&
        self.boxMin.z <= box.boxMin.z &&
        self.boxMax.x >= box.boxMax.x &&
        self.boxMax.y >= box.boxMax.y &&
        self.boxMax.z >= box.boxMax.z
    }
    
    public func isContained(in box: GKBox) -> Bool {
        return
        self.boxMin.x >= box.boxMin.x &&
        self.boxMin.y >= box.boxMin.y &&
        self.boxMin.z >= box.boxMin.z &&
        self.boxMax.x <= box.boxMax.x &&
        self.boxMax.y <= box.boxMax.y &&
        self.boxMax.z <= box.boxMax.z
    }
    
    public func intersects(_ box: GKBox) -> Bool {
        let corners = [
            simd_float3(boxMin.x, boxMax.y, boxMax.z), //frontLeftTop
            simd_float3(boxMin.x, boxMin.y, boxMax.z), //frontLeftBottom
            simd_float3(boxMax.x, boxMax.y, boxMax.z), //frontRightTop
            simd_float3(boxMax.x, boxMin.y, boxMax.z), //frontRightBottom
            simd_float3(boxMin.x, boxMax.y, boxMin.z), //backLeftTop
            simd_float3(boxMin.x, boxMin.y, boxMin.z), //backLeftBottom
            simd_float3(boxMax.x, boxMax.y, boxMin.z), //backRightTop
            simd_float3(boxMax.x, boxMin.y, boxMin.z)  //backRightBottom
        ]
        for corner in corners {
            if box.contains(corner) {
                return true
            }
        }
        return false
    }
}
