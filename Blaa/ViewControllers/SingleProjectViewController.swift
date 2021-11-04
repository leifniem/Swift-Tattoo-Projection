import UIKit
import MetalKit

class SingleProjectViewController: UIViewController, MTKViewDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    
    @IBOutlet weak var compositionView: MTKView!
    @IBOutlet weak var videoTimeSlider: UISlider!
    @IBOutlet weak var uvPreview: UIImageView!
    @IBOutlet weak var sketchPreview: UIImageView!
    @IBOutlet weak var generateModelButton: UIButton!
    @IBOutlet weak var playButton: UIImageView!
    @IBOutlet weak var pickImageButton: UIButton!
    @IBOutlet weak var exportFrameButton: UIButton!
    
    var project: ScanProject?
    private var compositionHandler: CompositionHandler!
    private var isPlaying: Bool = false
    private let pickerController = UIImagePickerController()
    
    override func viewDidAppear(_ animated: Bool) {
        compositionHandler.updateModelPipeLineState()
    }
    
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
        compositionHandler.drawRectResized(size: compositionView.bounds.size)
        
        if project?.sketch != nil {
            self.sketchPreview.image = project?.sketch
        }
        
        pickerController.delegate = self
        pickerController.mediaTypes = ["public.image"]
        pickerController.sourceType = .photoLibrary
        
        videoTimeSlider.addTarget(self, action: #selector(timelineValueChange), for: .valueChanged)
        pickImageButton.addTarget(self, action: #selector(openGalleryPicker), for: .touchUpInside)
        exportFrameButton.addTarget(self, action: #selector(saveFrame), for: .touchUpInside)
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
    
    @objc func saveFrame () {
        self.compositionHandler.saveFrame()
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        print("Hi")
        guard let image = info[.originalImage] as? UIImage else {
            return
        }
        print(image)
        project?.setSketch(image)
    }
    
    @objc func openGalleryPicker() {
        self.navigationController?.present(pickerController, animated: true)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.destination is LimitViewController {
            let lvc = segue.destination as? LimitViewController
            lvc?.project = self.project
        }
    }
}
