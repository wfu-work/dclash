import Cocoa
import FlutterMacOS
import window

@main
class AppDelegate: FlutterAppDelegate {
  private var appearanceObservation: NSKeyValueObservation?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    updateDockIcon()
    appearanceObservation = NSApp.observe(\NSApplication.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateDockIcon()
      }
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    appearanceObservation?.invalidate()
    appearanceObservation = nil
    super.applicationWillTerminate(notification)
  }

  private func updateDockIcon() {
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    if let image = NSImage(named: isDark ? "DclashLogoDarkAqua" : "DclashLogoAqua") {
      image.isTemplate = false
      NSApp.applicationIconImage = image
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
