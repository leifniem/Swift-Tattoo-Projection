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
        let projectView = self.navigationController!.viewControllers.first(where: { type(of: $0) == SingleProjectViewController.self })
        if projectView != nil {
            self.navigationController?.popToViewController(projectView!, animated: true)
        } else {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
}
