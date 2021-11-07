import UIKit
import Metal
import MetalKit
import ARKit

class ScanViewController: UIViewController, ARSessionDelegate {
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var startStopButton: UIButton!
    @IBOutlet weak var proceedButton: UIButton!
    
    private var project: ScanProject?
    private let session = ARSession()
    private var scanHandler: ScanHandler!
    
    override func viewDidLoad() {
        self.navigationController?.navigationBar.isTranslucent = true
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        self.navigationController?.navigationBar.shadowImage = UIImage()
        
        super.viewDidLoad()
        
        session.delegate = self
        // Set the view to use the default device
        if let view = view as? MTKView {
            let device = MTLCreateSystemDefaultDevice()!
            view.device = device
            view.backgroundColor = UIColor.black
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha:1)
            // we need this to enable depth test
            view.depthStencilPixelFormat = .depth32Float
            view.contentScaleFactor = 1
            view.delegate = self
            view.preferredFramesPerSecond = 30
            // Configure the renderer to draw to the view
            scanHandler = ScanHandler(session: session, metalDevice: device, renderDestination: view)
            scanHandler.drawRectResized(size: view.bounds.size)
        }
        
        proceedButton.isHidden = true
        
        clearButton.addTarget(self, action: #selector(viewValueChanged), for: .touchUpInside)
        startStopButton.addTarget(self, action: #selector(viewValueChanged), for: .touchUpInside)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a world-tracking configuration, and
        // enable the scene depth frame-semantic.
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        // Run the view's session
        session.run(configuration)
        
        // The screen shouldn't dim during AR experiences.
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
    }
    
    @objc
    func viewValueChanged(view: UIView) {
        switch view {
        case startStopButton:
            if !scanHandler.isCollectingData, scanHandler.pointCount == 0{
                scanHandler.toggleCollection()
                startStopButton.setTitle("Stop Scan", for: .normal)
            } else {
                scanHandler.toggleCollection()
                startStopButton.isHidden = true
                proceedButton.isHidden = false
                startStopButton.setTitle("Start Scan", for: .normal)
                startStopButton.isEnabled = false
            }

        case clearButton:
            scanHandler.clearData()
            if scanHandler.isCollectingData {
                scanHandler.toggleCollection()    
            }
            proceedButton.isHidden = true
            startStopButton.isHidden = false
            startStopButton.isEnabled = true
            startStopButton.setTitle("Start Scan", for: .normal)

        default:
            break
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user.
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                if let configuration = self.session.configuration {
                    self.session.run(configuration, options: .resetSceneReconstruction)
                }
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.destination is LimitViewController {
            session.pause()
            proceedButton.isHidden = true
            startStopButton.isHidden = false
            project = scanHandler.compileProject()
            let lvc = segue.destination as? LimitViewController
            lvc?.project = self.project
        }
    }
    
    override open var shouldAutorotate: Bool {
        return false
    }
    
    override open var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override open var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
}

extension UINavigationController {
    
    override open var shouldAutorotate: Bool {
        get {
            if let visibleVC = visibleViewController {
                return visibleVC.shouldAutorotate
            }
            return super.shouldAutorotate
        }
    }
    
    override open var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation{
        get {
            if let visibleVC = visibleViewController {
                return visibleVC.preferredInterfaceOrientationForPresentation
            }
            return super.preferredInterfaceOrientationForPresentation
        }
    }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask{
        get {
            if let visibleVC = visibleViewController {
                return visibleVC.supportedInterfaceOrientations
            }
            return super.supportedInterfaceOrientations
        }
    }
}


// MARK: - MTKViewDelegate
extension ScanViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scanHandler.drawRectResized(size: size)
    }
    
    func draw(in view: MTKView) {
        scanHandler.draw()
    }
}
