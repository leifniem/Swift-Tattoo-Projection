import Foundation
import Accelerate
import UIKit
import simd

import Open3DSupport
import NumPySupport
import PythonSupport
import PythonKit
import LinkPython

let o3d = Python.import("open3d")

class ReconstructionHandler {
    
    enum ReconstructionStatus {
        case Success
        case Failed
    }
    
    let project: ScanProject
    var tstate: UnsafeMutableRawPointer?
    
    init (project: ScanProject) {
        self.project = project
    }
    
    func reconstruct() -> ReconstructionStatus {
        PythonSupport.initialize()
        Open3DSupport.sitePackagesURL.insertPythonPath()
        NumPySupport.sitePackagesURL.insertPythonPath()
        let o3d = Python.import("open3d")
        let np = Python.import("numpy")
        let ma = Python.import("numpy.ma")
        
        let divideColor = simd_reduce_max(project.pointCloud![0].color) > 1
        
        var pcdPositions = [[Float]]()
        var pcdNormals = [[Float]]()
        var pcdColors = [[Float]]()
        project.pointCloud?.forEach{ point in
            if project.boundingBox!.contains(point.position) {
                pcdPositions.append([point.position.x, point.position.y, point.position.z])
                pcdNormals.append([point.normal.x, point.normal.y, point.normal.z])
                divideColor
                ? pcdColors.append([point.color.x / 255.0, point.color.y / 255.0, point.color.z / 255.0])
                : pcdColors.append([point.color.x, point.color.y, point.color.z])
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).sync {
            let gstate = PyGILState_Ensure()
            defer {
                DispatchQueue.main.async {
                    guard let tstate = self.tstate else { fatalError() }
                    PyEval_RestoreThread(tstate)
                    self.tstate = nil
                }
                PyGILState_Release(gstate)
            }
            
            var pcd = o3d.geometry.PointCloud()
            pcd.points = o3d.utility.Vector3dVector(np.array(pcdPositions))
            pcd.normals = o3d.utility.Vector3dVector(np.array(pcdNormals))
            pcd.colors = o3d.utility.Vector3dVector(np.array(pcdColors))
            
            pcd.orient_normals_consistent_tangent_plane(100)
            pcd = pcd.remove_statistical_outlier(nb_neighbors: 20, std_ratio: 2.0)[0]
            
            let meshbb = o3d.geometry.AxisAlignedBoundingBox.create_from_points(pcd.points)
            pcd = pcd.voxel_down_sample(voxel_size: 0.0025)
            
            let result = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth: 9, scale: 1.5)
            var pyMesh = result[0]
            
//            Filter by density function
            let densities = result[1]
            let quantile = np.quantile(densities, 0.2)
            let mask = np.less(densities, quantile)
            pyMesh.remove_vertices_by_mask(mask)
            
//            remove all but biggest mesh
            pyMesh = pyMesh.crop(meshbb)
            let clustering = pyMesh.cluster_connected_triangles()
            let triClusters = np.asarray(clustering[0])
            let clusterVertCounts = np.asarray(clustering[1])
            let clusterMask = ma.masked_greater(clusterVertCounts[triClusters], 100)
//            var clusterMask = [Bool]()
//            for element in triClusters {
//                clusterMask.append( Int(clusterVertCounts[Int(element)!])! > 100 )
//            }
            pyMesh.remove_triangles_by_mask(clusterMask)
            
//            smooth mesh
            pyMesh = pyMesh.filter_smooth_taubin(number_of_iterations: 3)
            pyMesh.orient_triangles()
            pyMesh.compute_triangle_normals()
            pyMesh.compute_vertex_normals()
            
            //            optimization
            pyMesh.remove_degenerate_triangles()
            pyMesh.remove_duplicated_triangles()
            pyMesh.remove_duplicated_vertices()
            pyMesh.remove_non_manifold_edges()
            pyMesh.remove_unreferenced_vertices()
            
//            TODO Remove all submeshes but the one with the most polygons
            
            o3d.io.write_triangle_mesh(project.modelPath!.path, pyMesh, write_ascii: true)
            project.setFileWritten()
        }
        
        tstate = PyEval_SaveThread()
        return ReconstructionStatus.Success
    }
}
