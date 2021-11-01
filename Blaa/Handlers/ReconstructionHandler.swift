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
        
        
        var pcdPositions = [[Float]]()
        var pcdNormals = [[Float]]()
        var pcdColors = [[Float]]()
        project.pointCloud?.forEach{ point in
            if project.boundingBox!.contains(point.position) {
                pcdPositions.append([point.position.x, point.position.y, point.position.z])
                pcdNormals.append([point.normal.x, point.normal.y, point.normal.z])
                pcdColors.append([point.color.x, point.color.y, point.color.z])
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
            pcd = pcd.voxel_down_sample(voxel_size: 0.005)
            
            let result = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth: 9, scale: 1.5)
            var pyMesh = result[0]
            
//            TODO: remove low density vertices / triangles
            let densities = result[1]
            let quantile = np.quantile(densities, 0.2)
            let mask = np.less(densities, quantile)
            pyMesh.remove_vertices_by_mask(mask)
            
            pyMesh = pyMesh.crop(meshbb)
            pyMesh = pyMesh.filter_smooth_laplacian(number_of_iterations: 3)
            pyMesh.compute_triangle_normals()
            pyMesh.orient_triangles()
            
            //            optimization
            pyMesh.remove_degenerate_triangles()
            pyMesh.remove_duplicated_triangles()
            pyMesh.remove_duplicated_vertices()
            pyMesh.remove_non_manifold_edges()
            pyMesh.remove_unreferenced_vertices()
            
            o3d.io.write_triangle_mesh(project.modelPath!.path, pyMesh, write_vertex_colors: false)
            project.setFileWritten()
        }
        
        tstate = PyEval_SaveThread()
        return ReconstructionStatus.Success
    }
}
