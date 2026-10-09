import AppKit

@MainActor
final class SessionbarDelegate: NSObject, NSApplicationDelegate {
    static let store = SessionStore()

    func applicationDidFinishLaunching(_ notification: Notification) { Self.store.openListWindow() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.store.openListWindow()
        return false
    }
}
