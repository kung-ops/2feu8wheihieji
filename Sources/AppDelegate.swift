import UIKit

// iOS 12-compatible entry point (no SceneDelegate — scenes are iOS 13+).
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let library = LibraryViewController(style: .plain)

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: library)
        nav.navigationBar.tintColor = UIColor(red: 0.13, green: 0.62, blue: 0.36, alpha: 1)
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        return true
    }

    /// "Open in APK Sandbox" from Files, Safari, Mail, AirDrop…
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let presented = window?.rootViewController?.presentedViewController {
            presented.dismiss(animated: false)
        }
        library.loadViewIfNeeded()
        library.importAndOpen(url)
        return true
    }
}
