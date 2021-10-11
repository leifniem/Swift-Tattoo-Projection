import UIKit
import MetalKit

final class LimitViewController: UIViewController {
    @IBOutlet weak var timeSlider: UISlider!
    @IBOutlet weak var sliderXMin: UISlider!
    @IBOutlet weak var sliderXMax: UISlider!
    @IBOutlet weak var sliderYMin: UISlider!
    @IBOutlet weak var sliderYMax: UISlider!
    @IBOutlet weak var sliderZMin: UISlider!
    @IBOutlet weak var sliderZMax: UISlider!
    @IBOutlet weak var proceedButton: UIButton!
    @IBOutlet weak var renderView: MTKView!
    
    var project: ScanProject?
    var limitHandler: LimitHandler!
    private var isPlaying = false
    
    private var viewportSize = CGSize()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard self.project?.pointCloud != nil else {
            print("Point cloud of loaded project empty, closing LimitView.")
            dismiss(animated: true, completion: nil)
            return
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        renderView.device = device
        renderView.backgroundColor = UIColor.darkGray
        renderView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderView.depthStencilPixelFormat = .depth32Float
        renderView.contentScaleFactor = 1
        renderView.delegate = self
        renderView.preferredFramesPerSecond = 30
        limitHandler = LimitHandler(device: device, view: renderView, project: project!)
        
        
        timeSlider.addTarget(self, action: #selector(timeSliderValueChanged), for: .valueChanged)
        sliderXMin.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        sliderXMax.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        sliderYMin.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        sliderYMax.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        sliderZMin.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        sliderZMax.addTarget(self, action: #selector(limitSliderValueChanged), for: .valueChanged)
        
        draw(in: renderView)
    }
    
    @objc func timeSliderValueChanged() {
        isPlaying = false
        limitHandler.setPlayBackFrame(value: timeSlider.value)
    }
    
    @objc func limitSliderValueChanged(view: UIView) {
        switch view {
        case sliderXMin:
            limitHandler.setBoundingBoxCoordinate(axis: "xMin", t: sliderXMin.value)
        case sliderXMax:
            limitHandler.setBoundingBoxCoordinate(axis: "xMax", t: sliderXMax.value)
        case sliderYMin:
            limitHandler.setBoundingBoxCoordinate(axis: "yMin", t: sliderYMin.value)
        case sliderYMax:
            limitHandler.setBoundingBoxCoordinate(axis: "yMax", t: sliderYMax.value)
        case sliderZMin:
            limitHandler.setBoundingBoxCoordinate(axis: "zMin", t: sliderZMin.value)
        case sliderZMax:
            limitHandler.setBoundingBoxCoordinate(axis: "zMax", t: sliderZMax.value)
        default:
            break
        }
    }
    
    override public var shouldAutorotate: Bool {
        return true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return false
    }
    
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override public var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .unknown
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.destination is ReconstructionViewController {
            let rvc = segue.destination as? ReconstructionViewController
            rvc?.project = self.project
            rvc?.boundingBox = limitHandler.bounds
        }
    }
    
}


//MARK: - MTKViewDelegate
extension LimitViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        limitHandler.drawRectResized(size: size)
    }
    
    func draw(in view: MTKView) {
        limitHandler.draw()
    }
}
