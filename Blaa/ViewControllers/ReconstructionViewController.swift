import UIKit
import SceneKit

class ReconstructionViewController: UIViewController {
    
    @IBOutlet weak var statusLabel: UILabel!
//    @IBOutlet weak var scnView: SCNView!
    
    var project: ScanProject?
    private var reconstructionHandler: ReconstructionHandler?
    
    override func viewDidAppear(_ animated: Bool) {
        guard project != nil else {
            print("ReconstructionViewController did not receive Project.")
            dismiss(animated: true, completion: nil)
            return
        }
//        scnView.backgroundColor = UIColor.black
        self.reconstructionHandler = ReconstructionHandler(project: project!)
        guard reconstructionHandler!.reconstruct() == .Success else {
            statusLabel.text = "Failed :((("
            fatalError("Failed to create Mesh.")
        }
//        statusLabel.removeFromSuperview()
//        let scene = try! SCNScene(url: project!.modelPath!)
//        let cameraNode = SCNNode()
//        cameraNode.camera = SCNCamera()
//        cameraNode.position = SCNVector3(project!.boundingBox!.center - simd_float3(0,0,1))
//        let lightNode = SCNNode()
//        lightNode.light = SCNLight()
//        lightNode.light!.type = .omni
//        lightNode.position = SCNVector3(0,1,1)
//        scene.rootNode.addChildNode(cameraNode)
//        scene.rootNode.addChildNode(lightNode)
//        scnView.scene = scene
//        scnView.allowsCameraControl = true
        let projectView = self.navigationController!.viewControllers.first(where: { type(of: $0) == SingleProjectViewController.self })
        if projectView != nil {
            self.navigationController?.popToViewController(projectView!, animated: true)
        } else {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
}
