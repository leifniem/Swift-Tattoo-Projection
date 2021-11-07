import UIKit
import AVFAudio

class ProjectListViewCell : UICollectionViewCell {
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var creationDate: UILabel!
    @IBOutlet weak var thumbnail: UIImageView!
    @IBOutlet weak var meta: UIStackView!
    @IBOutlet weak var videoLabel: UILabel!
    @IBOutlet weak var modelLabel: UILabel!
    @IBOutlet weak var uvLabel: UILabel!
    @IBOutlet weak var sketchLabel: UILabel!
    
    private let gradient = CAGradientLayer()
    
    override func setNeedsUpdateConfiguration() {
        if self.isSelected {
            self.layer.borderWidth = 2
            self.contentView.layer.backgroundColor = UIColor.tintColor.cgColor
            self.thumbnail.layer.opacity = 0.5
        } else {
            self.layer.borderWidth = 0
            self.contentView.layer.backgroundColor = UIColor.darkGray.cgColor
            self.thumbnail.layer.opacity = 1
        }
    }
    
    override func layoutSublayers(of layer: CALayer) {
        thumbnail.layer.insertSublayer(gradient, at: 1)
        gradient.locations = [0.0, 0.75]
        gradient.colors = [UIColor.darkGray.withAlphaComponent(0).cgColor, UIColor.darkGray.cgColor]
        gradient.frame = thumbnail.bounds
        super.layoutSublayers(of: self.layer)
    }
    
    override var isSelected: Bool {
        didSet{
            if self.isSelected {
                UIView.animate(withDuration: 0.3) { // for animation effect
                    self.layer.borderColor = CGColor.init(red: 1, green: 0, blue: 0, alpha: 1)
                    self.gradient.colors = [UIColor.red.withAlphaComponent(0).cgColor, UIColor.red.cgColor]
                    self.layer.borderWidth = 3
                }
            }
            else {
                UIView.animate(withDuration: 0.3) { // for animation effect
                    self.layer.borderColor = CGColor.init(red: 1, green: 0, blue: 0, alpha: 0)
                    self.gradient.colors = [UIColor.darkGray.withAlphaComponent(0).cgColor, UIColor.darkGray.cgColor]
                    self.layer.borderWidth = 0
                }
            }
        }
    }
}

class ProjectListViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UIGestureRecognizerDelegate {
    @IBOutlet weak var projectList: UICollectionView!
    @IBOutlet weak var selectButton: UIButton!
    @IBOutlet weak var newScanButton: UIButton!
    
    private enum OperationMode {
        case selecting
        case viewing
    }
    private let manager = ProjectsManager()
    private let reuseIdentifier = "ProjectCell"
    private var selectedProjects: [ScanProject] = []
    private let dateFormatter = DateFormatter()
    private var operationMode: OperationMode = .viewing
    private let minCellWidth: CGFloat = 300
    
    override func viewDidLoad() {
        projectList.delegate = self
//        DispatchQueue.main.async { [self] in
//            manager.loadProjectsFromDisk()
//            projectList.reloadData()
//        }
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        projectList.dataSource = self
        
        selectButton.addTarget(self, action: #selector(switchOperationMode), for: .touchUpInside)
        
        setupLongGestureRecognizerOnCollection()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        DispatchQueue.main.async { [self] in
            manager.loadProjectsFromDisk()
            projectList.reloadData()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return manager.projects.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ProjectListViewCell
        
        let project = manager.projects[indexPath.item]
        cell.titleLabel.text = project.title
        cell.creationDate.text = dateFormatter.string(from: project.created)
        
        if project.resources["video"]! {
            cell.videoLabel.textColor = .white
            cell.thumbnail.image = project.thumbnail
        }
        if project.resources["model"]! { cell.modelLabel.textColor = .white }
        if project.resources["uv"]! { cell.uvLabel.textColor = .white }
        if project.resources["texture"]! { cell.sketchLabel.textColor = .white }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let excess = (projectList.frame.size.width - 40).remainder(dividingBy: minCellWidth)
        let count = (projectList.frame.size.width - 40) - excess
        let width = minCellWidth + excess / count
        return CGSize(width: width, height: width * 0.66)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if operationMode == .viewing{// open project view
            let storyboard = UIStoryboard(name: "Screens", bundle: nil)
            let project = manager.projects[indexPath.item]
            project.loadFullData()
            let vc = storyboard.instantiateViewController(withIdentifier: "SingleProjectView") as! SingleProjectViewController
            vc.project = project
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            let project = manager.projects[indexPath.item]
            if let index = selectedProjects.firstIndex(of: project) {
                selectedProjects.remove(at: index)
            } else {
                selectedProjects.append(project)
            }
        }
    }
    
    private func setupLongGestureRecognizerOnCollection() {
        let longPressedGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(gestureRecognizer:)))
        longPressedGesture.minimumPressDuration = 0.5
        longPressedGesture.delegate = self
        longPressedGesture.delaysTouchesBegan = true
        projectList.addGestureRecognizer(longPressedGesture)
    }
    
    @objc func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state != .began else { return }
        if self.operationMode == .viewing {
            self.switchOperationMode()
        }
        let pressPosition = gestureRecognizer.location(in: projectList)
        if let indexPath = projectList.indexPathForItem(at: pressPosition) {
            projectList.selectItem(at: indexPath, animated: false, scrollPosition: .centeredHorizontally)
        }
    }
    
    @objc func switchOperationMode() {
        if self.operationMode == .viewing {
            self.operationMode = .selecting
            self.selectButton.setTitle("", for: .normal)
            self.selectButton.setImage(UIImage(systemName: "trash"), for: .normal)
            self.projectList.allowsMultipleSelection = true
        } else {
            self.operationMode = .viewing
            self.selectButton.setTitle("Select", for: .normal)
            self.selectButton.setImage(nil, for: .normal)
            self.projectList.allowsMultipleSelection = false
            self.projectList.selectItem(at: nil, animated: true, scrollPosition: [])
            self.selectedProjects.removeAll()
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
}
