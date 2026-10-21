import Cocoa
import FlutterMacOS
import window

@main
class AppDelegate: FlutterAppDelegate {
  private var appearanceObservation: NSKeyValueObservation?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    appearanceObservation = NSApp.observe(\NSApplication.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
      DispatchQueue.main.async {
        self?.updateDockIcon(for: app.effectiveAppearance)
      }
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    appearanceObservation?.invalidate()
    appearanceObservation = nil
    super.applicationWillTerminate(notification)
  }

  private func updateDockIcon(for appearance: NSAppearance) {
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let name = NSImage.Name(isDark ? "DclashDockIconDark" : "DclashDockIconLight")
    if let image = NSImage(named: name) {
      image.isTemplate = false
      NSApp.applicationIconImage = image
      NSApp.dockTile.display()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let plugin = WindowPlugin.instance else { return .terminateNow }
    plugin.handleShouldTerminate()
    return .terminateCancel
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    WindowPlugin.instance?.handleReopen()
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
