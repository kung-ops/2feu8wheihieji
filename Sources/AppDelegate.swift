import UIKit

// iOS 12-compatible entry point (no SceneDelegate – scenes are iOS 13+).
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let home = HomeViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ApkStore.cleanStaging()
        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = AppNavigationController(rootViewController: home)
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        return true
    }

    /// "Open in APK Sandbox" from Files, Safari, Mail, AirDrop… → installer.
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        home.loadViewIfNeeded()
        home.install(url)
        return true
    }

    /// Like Android's low-memory killer: background apps go first.
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        TaskManager.shared.trimMemory()
    }
}
