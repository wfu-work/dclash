import Cocoa
import Carbon
import FlutterMacOS

/// Local hotkey_manager adapter: propagate Carbon registration failures so
/// settings can roll back instead of silently saving an unavailable shortcut.
public class HotkeyManagerMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private struct Binding {
        let identifier: String
        let reference: EventHotKeyRef
        let arguments: [String: Any]
    }

    private static let signature: OSType = 0x44434C48 // DCLH
    private var bindings: [UInt32: Binding] = [:]
    private var nextID: UInt32 = 0
    private var handler: EventHandlerRef?
    private var sink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = HotkeyManagerMacosPlugin()
        let channel = FlutterMethodChannel(
            name: "dev.leanflutter.plugins/hotkey_manager",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
        FlutterEventChannel(
            name: "dev.leanflutter.plugins/hotkey_manager_event",
            binaryMessenger: registrar.messenger
        ).setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "register":
            registerShortcut(call, result: result)
        case "unregister":
            guard let args = call.arguments as? [String: Any],
                  let identifier = args["identifier"] as? String else {
                result(FlutterError(code: "invalid_shortcut", message: "Invalid shortcut identifier", details: nil))
                return
            }
            for (id, binding) in bindings where binding.identifier == identifier {
                UnregisterEventHotKey(binding.reference)
                bindings.removeValue(forKey: id)
            }
            result(true)
        case "unregisterAll":
            removeAll()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func registerShortcut(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyCode = args["keyCode"] as? UInt32,
              let modifiers = args["modifiers"] as? [String],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "invalid_shortcut", message: "Invalid shortcut", details: nil))
            return
        }
        let flags: [String: UInt32] = [
            "alt": UInt32(optionKey), "control": UInt32(controlKey),
            "shift": UInt32(shiftKey), "meta": UInt32(cmdKey),
        ]
        guard modifiers.allSatisfy({ flags[$0] != nil }),
              !bindings.values.contains(where: { $0.identifier == identifier }) else {
            result(FlutterError(code: "invalid_shortcut", message: "Invalid or duplicate shortcut", details: nil))
            return
        }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, context in
                    guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
                    return Unmanaged<HotkeyManagerMacosPlugin>.fromOpaque(context).takeUnretainedValue().handleEvent(event)
                },
                1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
            )
            if status != noErr {
                result(FlutterError(code: "shortcut_handler", message: "Cannot listen for global shortcuts", details: Int(status)))
                return
            }
        }
        nextID &+= 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers.reduce(0) { $0 | flags[$1]! },
            EventHotKeyID(signature: Self.signature, id: nextID),
            GetEventDispatcherTarget(), 0, &reference
        )
        guard status == noErr, let reference = reference else {
            result(FlutterError(
                code: "shortcut_unavailable",
                message: "Shortcut is already in use or unavailable. Choose another combination.",
                details: Int(status)
            ))
            return
        }
        bindings[nextID] = Binding(identifier: identifier, reference: reference, arguments: args)
        result(true)
    }

    private func handleEvent(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id
        )
        guard status == noErr, id.signature == Self.signature,
              let binding = bindings[id.id] else { return OSStatus(eventNotHandledErr) }
        sink?(["type": "onKeyDown", "data": binding.arguments])
        return noErr
    }

    private func removeAll() {
        for binding in bindings.values { UnregisterEventHotKey(binding.reference) }
        bindings.removeAll()
    }

    deinit {
        removeAll()
        if let handler = handler { RemoveEventHandler(handler) }
    }
}
