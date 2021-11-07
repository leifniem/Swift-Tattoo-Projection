import UIKit
import MetalKit
import SwiftUI

class SingleProjectViewController: UIViewController, MTKViewDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    
    @IBOutlet weak var compositionView: MTKView!
    @IBOutlet weak var videoTimeSlider: UISlider!
    @IBOutlet weak var uvPreview: UIImageView!
    @IBOutlet weak var sketchPreview: UIImageView!
    @IBOutlet weak var generateModelButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var pickImageButton: UIButton!
    @IBOutlet weak var exportFrameButton: UIButton!
    @IBOutlet weak var exportUVButton: UIButton!
    @IBOutlet weak var removeSketchButton: UIButton!
    @IBOutlet weak var removeModelButton: UIButton!
    @IBOutlet weak var titleField: UITextField!
    
    var project: ScanProject?
    private var compositionHandler: CompositionHandler!
    private var isPlaying: Bool = false
    private let pickerController = UIImagePickerController()
    
    override func viewDidAppear(_ animated: Bool) {
        if (project?.resources["model"])! && project?.model != nil{
            compositionHandler.updateModelPipeLineState()
        }
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
        compositionHandler = CompositionHandler(device: device, view: compositionView, project: project!, timeline: videoTimeSlider)
        navigationItem.title = project!.title
        titleField.text = project?.title
        compositionHandler.drawRectResized(size: compositionView.bounds.size)
        
        if project?.sketch != nil {
            self.sketchPreview.image = project?.sketch
        }
        if project?.uvAtlas != nil {
            self.uvPreview.image = project?.uvAtlas
        }
        
        pickerController.delegate = self
        pickerController.mediaTypes = ["public.image"]
        pickerController.sourceType = .photoLibrary
        
        videoTimeSlider.addTarget(self, action: #selector(timelineValueChange), for: .valueChanged)
        playButton.addTarget(self, action: #selector(togglePlayState), for: .touchUpInside)
        pickImageButton.addTarget(self, action: #selector(openGalleryPicker), for: .touchUpInside)
        exportFrameButton.addTarget(self, action: #selector(saveFrame), for: .touchUpInside)
        exportUVButton.addTarget(self, action: #selector(exportUV), for: .touchUpInside)
        removeSketchButton.addTarget(self, action: #selector(removeSketch), for: .touchUpInside)
        titleField.addTarget(self, action: #selector(changeTitle), for: .editingDidEnd)
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
        compositionHandler.togglePlayState(value: false)
        compositionHandler.setPlayBackFrame(value: videoTimeSlider.value)
    }
    
    @objc func saveFrame () {
        self.compositionHandler.saveFrame()
    }
    
    @objc func exportUV () {
        uvPreview.image = self.compositionHandler.saveUV()
    }
    
    @objc func changeTitle () {
        project?.setTitle(titleField.text!)
    }
    
    @objc func removeSketch () {
        project?.deleteSketch()
        compositionHandler.updateModelPipeLineState()
        sketchPreview.image = nil
    }
    
    @objc func togglePlayState() {
        compositionHandler.togglePlayState()
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            return
        }
        project?.setSketch(image)
        sketchPreview.image = image
        compositionHandler.updateModelPipeLineState()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func openGalleryPicker() {
        self.navigationController?.present(pickerController, animated: true)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        if segue.destination is LimitViewController {
            if project?.pointCloud == nil || project?.pointCloud!.count == 0 {
                project!.readPointCloud()
            }
            if (project?.pointCloud!.first!.color.x)! <= 1 {
                project?.pointCloud!.forEach{ point in
                    point.color += 255.0
                }
            }
            let lvc = segue.destination as? LimitViewController
            lvc?.project = self.project
        }
    }
}
