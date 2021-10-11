import UIKit
import MetalKit

class SingleProjectViewController: UIViewController, MTKViewDelegate {
    
    @IBOutlet weak var compositionView: MTKView!
    @IBOutlet weak var videoTimeSlider: UISlider!
    @IBOutlet weak var uvPreview: UIImageView!
    @IBOutlet weak var sketchPreview: UIImageView!
    @IBOutlet weak var generateModelButton: UIButton!
    @IBOutlet weak var playButton: UIImageView!
    
    var project: ScanProject?
    private var compositionHandler: CompositionHandler!
    private var isPlaying: Bool = false
    
    
    override func viewDidLoad() {
        guard project != nil else{
            dismiss(animated: true, completion: nil)
            return
        }
        let device = MTLCreateSystemDefaultDevice()!
        compositionView.device = device
        compositionView.backgroundColor = UIColor.darkGray
        compositionView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        compositionView.depthStencilPixelFormat = .depth32Float
        compositionView.contentScaleFactor = 1
        compositionView.delegate = self
        compositionView.preferredFramesPerSecond = 30
        compositionHandler = CompositionHandler(device: device, view: compositionView, project: project!)
        navigationItem.title = project!.title
//        if project!.resources["video"] != nil {
//            uvPreview.image = project!.thumbnail
//        }
        
        compositionHandler.drawRectResized(size: compositionView.bounds.size)
        
        videoTimeSlider.addTarget(self, action: #selector(timelineValueChange), for: .valueChanged)
    }
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        compositionHandler.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        compositionHandler.draw()
    }
    
    @objc func timelineValueChange () {
        self.isPlaying = false
        compositionHandler.setPlayBackFrame(value: videoTimeSlider.value)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.destination is LimitViewController {
            let lvc = segue.destination as? LimitViewController
            lvc?.project = self.project
        }
    }
}
