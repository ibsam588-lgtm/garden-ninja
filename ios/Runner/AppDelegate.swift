import Flutter
import UIKit
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var gameCenter: GameCenterBridge?
  private var adPrivacy: AdPrivacyBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    gameCenter = GameCenterBridge(messenger: messenger)
    adPrivacy = AdPrivacyBridge(messenger: messenger)
    let reviews = FlutterMethodChannel(name: "garden_ninja/play_review", binaryMessenger: messenger)
    reviews.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "requestReview":
        guard let scene = self?.activeScene else {
          result(false)
          return
        }
        if #available(iOS 18.0, *) {
          AppStore.requestReview(in: scene)
        } else if #available(iOS 14.0, *) {
          SKStoreReviewController.requestReview(in: scene)
        } else {
          SKStoreReviewController.requestReview()
        }
        // StoreKit controls whether a prompt appears; this means it was requested.
        result(true)
      case "openStoreListing":
        let arguments = call.arguments as? [String: Any]
        guard let appID = arguments?["appStoreId"] as? String,
              !appID.isEmpty, appID.allSatisfy({ $0.isASCII && $0.isNumber }),
              let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review") else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
  private var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }
}
