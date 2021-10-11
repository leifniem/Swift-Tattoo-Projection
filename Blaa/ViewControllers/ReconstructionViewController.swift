import UIKit

class ReconstructionViewController: UIViewController {
    
    var project: ScanProject?
    var boundingBox: BoundingBox?
    private var reconstructionHandler: ReconstructionHandler?
    
    override func viewDidLoad() {
        guard project != nil else {
            print("ReconstructionViewController did not receive Project.")
            dismiss(animated: true, completion: nil)
            return
        }
        self.reconstructionHandler = ReconstructionHandler(project: project!, boundingBox: boundingBox!)
    }
}
