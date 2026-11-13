import Flutter
import UIKit
import StoreKit
import AppTrackingTransparency
import AdSupport
import FBAudienceNetwork

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
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

    let privacy = FlutterMethodChannel(name: "garden_ninja/ios_privacy", binaryMessenger: messenger)
    privacy.setMethodCallHandler { [weak self] call, result in
      guard call.method == "prepareAds" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      self?.prepareAds(requestTracking: arguments?["requestTracking"] as? Bool ?? false, result: result)
    }
  }

  private var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }

  private func prepareAds(requestTracking: Bool, result: @escaping FlutterResult) {
    // ATT cannot present while the app is launching or another system sheet is
    // active. Dart retries after the app becomes active, without blocking play.
    guard UIApplication.shared.applicationState == .active else {
      result(false)
      return
    }
    guard requestTracking else {
      setMetaTracking(false)
      result(true)
      return
    }
    if #available(iOS 14.0, *) {
      if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
          DispatchQueue.main.async {
            self?.setMetaTracking(status == .authorized)
            result(status != .notDetermined)
          }
        }
      } else {
        setMetaTracking(ATTrackingManager.trackingAuthorizationStatus == .authorized)
        result(true)
      }
    } else {
      setMetaTracking(ASIdentifierManager.shared().isAdvertisingTrackingEnabled)
      result(true)
    }
  }

  private func setMetaTracking(_ enabled: Bool) {
    // FAN 6.15+ reads ATT directly on iOS 17+. Older OS versions need this flag.
    if #available(iOS 17.0, *) { return }
    FBAdSettings.setAdvertiserTrackingEnabled(enabled)
  }
}
