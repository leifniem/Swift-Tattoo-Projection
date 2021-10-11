
import UIKit
import ARKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // Ensure that the device supports scene depth and present
            //  an error-message view controller, if not.
            let storyboard = UIStoryboard(name: "ProjectListView", bundle: nil)
            let viewController = storyboard.instantiateViewController(withIdentifier: "unsupportedDeviceMessage")
            let navController = UINavigationController(rootViewController: viewController)
            window?.rootViewController = navController
            window?.makeKeyAndVisible()
        }
        return true
    }
}

