import Foundation
import Gzip
import ExtrasJSON

class ProjectsManager {
    
    private var projectsInMemory = [ScanProject]()
    
    var projects: [ScanProject] {
        get {
            return projectsInMemory
        }
    }
    
    func loadProjectsFromDisk () {
        let projectsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: projectsFolder, includingPropertiesForKeys: nil, options: [])
            try folders.forEach{
                let metaURL = URL(fileURLWithPath: $0.appendingPathComponent(ScanProject.Constants.metaName).path)
                if FileManager.default.fileExists(atPath: metaURL.path) {
                    let data = try Data(contentsOf: metaURL)
                    let project = try XJSONDecoder().decode(ScanProject.self, from: data)
                    if let index = projectsInMemory.firstIndex(of: project) {
                        projectsInMemory[index] = project
                    } else {
                        projectsInMemory.append(project)
                    }
                }
            }
            projectsInMemory.sort{
                $0.created > $1.created
            }
        } catch {
            fatalError("Could not load Projects:\(error)")
        }
    }
    
    func deleteProject (project: ScanProject) {
        if let index = self.projectsInMemory.firstIndex(where: {$0.id == project.id}) {
            let projectToDelete = self.projectsInMemory.remove(at: index)
            projectToDelete.deleteProject()
        }
    }
}
