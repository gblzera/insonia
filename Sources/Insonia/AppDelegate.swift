import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusMenuController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A assertion já é liberada quando o processo morre, mas
        // soltamos explicitamente por garantia.
        PowerManager.shared.deactivate()
    }
}
