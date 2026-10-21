import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  private var chromeChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Let Flutter paint behind the native titlebar controls. The Flutter
    // window frame reserves the traffic-light area and provides the drag
    // target for the rest of the titlebar.
    self.title = "dclash"
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    titlebarSeparatorStyle = .none

    let startup = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger)
    startup.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        if #available(macOS 13.0, *) {
          result(SMAppService.mainApp.status == .enabled)
        } else {
          result(false)
        }
      case "launchAtStartupSetEnabled":
        guard #available(macOS 13.0, *) else {
          result(FlutterError(code: "unsupported", message: "Launch at login requires macOS 13 or later", details: nil))
          return
        }
        guard let arguments = call.arguments as? [String: Any], let enabled = arguments["setEnabledValue"] as? Bool else {
          result(FlutterError(code: "invalid_arguments", message: "A login preference is required", details: nil))
          return
        }
        Task { @MainActor in
          do {
            if enabled {
              try SMAppService.mainApp.register()
              if SMAppService.mainApp.status == .requiresApproval {
                result(FlutterError(code: "approval_required", message: "Allow dclash in System Settings > General > Login Items", details: nil))
                return
              }
            } else {
              try await SMAppService.mainApp.unregister()
            }
            result(nil)
          } catch {
            result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    registerWindowChrome(flutterViewController)
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  private func registerWindowChrome(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "cloudrift/windowChrome",
      binaryMessenger: controller.engine.binaryMessenger)
    chromeChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else {
        result(nil)
        return
      }
      switch call.method {
      case "startDragging":
        DispatchQueue.main.async { [weak window] in
          guard let window = window, let event = window.currentEvent else { return }
          window.performDrag(with: event)
        }
        result(nil)
      case "zoom":
        window.performZoom(nil)
        result(nil)
      case "setAppearance":
        guard let dark = call.arguments as? Bool else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "Expected a dark appearance flag",
            details: nil))
          return
        }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
