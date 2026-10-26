import Cocoa
import FlutterMacOS
import UserNotifications

public final class LocalNotifierPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    private var channel: FlutterMethodChannel!
    private var authorizationRequested = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LocalNotifierPlugin()
        instance.channel = FlutterMethodChannel(
            name: "local_notifier",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.channel)

        let center = UNUserNotificationCenter.current()
        center.delegate = instance
        instance.requestAuthorizationIfNeeded(center)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "notify":
            notify(call, result: result)
        case "close":
            close(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func requestAuthorizationIfNeeded(_ center: UNUserNotificationCenter) {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "invalid_notification", message: "Missing notification identifier", details: nil))
            return
        }

        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? ""
        content.subtitle = args["subtitle"] as? String ?? ""
        content.body = args["body"] as? String ?? ""
        content.sound = (args["silent"] as? Bool == true) ? nil : .default
        content.userInfo = ["notificationId": identifier]

        if let actions = args["actions"] as? [[String: Any]], !actions.isEmpty {
            let categoryIdentifier = "dclash.local_notifier.\(identifier)"
            let notificationActions = actions.enumerated().compactMap { index, action -> UNNotificationAction? in
                guard let text = action["text"] as? String, !text.isEmpty else { return nil }
                return UNNotificationAction(identifier: "action_\(index)", title: text, options: [])
            }
            if !notificationActions.isEmpty {
                let category = UNNotificationCategory(
                    identifier: categoryIdentifier,
                    actions: notificationActions,
                    intentIdentifiers: [],
                    options: []
                )
                let center = UNUserNotificationCenter.current()
                center.setNotificationCategories([category])
                content.categoryIdentifier = categoryIdentifier
            }
        }

        let center = UNUserNotificationCenter.current()
        requestAuthorizationIfNeeded(center)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if let error = error {
                result(FlutterError(code: "notification_failed", message: error.localizedDescription, details: nil))
                return
            }
            self?._invokeMethod("onLocalNotificationShow", identifier)
            result(true)
        }
    }

    private func close(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "invalid_notification", message: "Missing notification identifier", details: nil))
            return
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        _invokeMethod("onLocalNotificationClose", identifier)
        result(true)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = notificationId(from: response.notification.request.content)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            _invokeMethod("onLocalNotificationClick", identifier)
        } else if response.actionIdentifier.hasPrefix("action_"),
                  let index = Int(response.actionIdentifier.dropFirst("action_".count)) {
            _invokeMethod("onLocalNotificationClickAction", identifier, extra: ["actionIndex": index])
        }
        completionHandler()
    }

    private func notificationId(from content: UNNotificationContent) -> String {
        return content.userInfo["notificationId"] as? String ?? content.threadIdentifier
    }

    private func _invokeMethod(_ methodName: String, _ notificationId: String, extra: [String: Any] = [:]) {
        var args = extra
        args["notificationId"] = notificationId
        channel.invokeMethod(methodName, arguments: args, result: nil)
    }
}
