import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let shareChannelName = "receiptnest/share"
  private let shareEventMethod = "onSharedImage"
  private let shareInitialFileMethod = "getInitialSharedFilePath"

  private var shareChannel: FlutterMethodChannel?
  private var pendingSharedFilePath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: shareChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }

        switch call.method {
        case self.shareInitialFileMethod:
          result(self.pendingSharedFilePath)
          self.pendingSharedFilePath = nil
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      shareChannel = channel
    }

    if let url = launchOptions?[.url] as? URL {
      _ = handleShareURL(url)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleShareURL(url) {
      return true
    }

    return super.application(app, open: url, options: options)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    flushPendingSharedFilePath()
  }

  @discardableResult
  private func handleShareURL(_ url: URL) -> Bool {
    guard url.scheme == "receiptnest", url.host == "share" else {
      return false
    }

    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let filePath = components.queryItems?.first(where: { $0.name == "file" })?.value,
      !filePath.isEmpty
    else {
      return true
    }

    pendingSharedFilePath = filePath
    flushPendingSharedFilePath()
    return true
  }

  private func flushPendingSharedFilePath() {
    guard let filePath = pendingSharedFilePath, !filePath.isEmpty else {
      return
    }

    shareChannel?.invokeMethod(shareEventMethod, arguments: filePath)
  }
}
