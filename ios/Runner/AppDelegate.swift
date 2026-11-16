import Flutter
import UIKit
import StoreKit
#if DEBUG && NATIVE_STOREKIT_TEST && targetEnvironment(simulator)
import StoreKitTest
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var gameCenter: GameCenterBridge?
  private var adPrivacy: AdPrivacyBridge?
  #if DEBUG && NATIVE_STOREKIT_TEST && targetEnvironment(simulator)
  private var nativeStoreKitSession: SKTestSession?
  #endif
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    #if DEBUG && NATIVE_STOREKIT_TEST && targetEnvironment(simulator)
    // Hosted XCTest starts after plugin registration. Select the local store
    // first, so eager purchase clients never cache the sandbox environment.
    guard let fixture = Bundle.main.url(forResource: "GardenNinjaPurchases", withExtension: "storekit") else {
      fatalError("Native StoreKit tests require their local product fixture")
    }
    do {
      nativeStoreKitSession = try SKTestSession(contentsOf: fixture)
      nativeStoreKitSession?.disableDialogs = true
      NSLog("STOREKIT_FIXTURE_READY_BEFORE_PLUGINS")
    } catch {
      fatalError("Unable to initialize the native test store: \(error)")
    }
    #endif
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    gameCenter = GameCenterBridge(messenger: messenger)
    adPrivacy = AdPrivacyBridge(messenger: messenger)
    let updates = FlutterMethodChannel(name: "garden_ninja/app_update", binaryMessenger: messenger)
    updates.setMethodCallHandler { [weak self] call, result in
      let appID = (call.arguments as? [String: Any])?["appStoreId"] as? String ?? ""
      guard !appID.isEmpty, appID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
        result(nil); return
      }
      switch call.method {
      case "checkStoreUpdate":
        Task { @MainActor in await self?.checkStoreUpdate(appID: appID, result: result) }
      case "openStoreUpdate":
        guard let url = URL(string: "https://apps.apple.com/app/id\(appID)") else {
          result(false); return
        }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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

  @MainActor
  private func checkStoreUpdate(appID: String, result: @escaping FlutterResult) async {
    #if DEBUG || targetEnvironment(simulator)
    result(["production": false]); return
    #else
    var production = false
    if #available(iOS 16.0, *) {
      if let transaction = try? await AppTransaction.shared,
         case .verified(let verified) = transaction {
        production = verified.environment == .production
      }
    } else if let receipt = Bundle.main.appStoreReceiptURL {
      production = receipt.lastPathComponent != "sandboxReceipt" &&
        FileManager.default.fileExists(atPath: receipt.path)
    }
    guard production else { result(["production": false]); return }
    var components = URLComponents(string: "https://itunes.apple.com/lookup")!
    let country: String
    if #available(iOS 16.0, *) { country = Locale.current.region?.identifier ?? "US" }
    else { country = Locale.current.regionCode ?? "US" }
    components.queryItems = [URLQueryItem(name: "id", value: appID),
                             URLQueryItem(name: "country", value: country)]
    guard let url = components.url else { result(nil); return }
    do {
      var request = URLRequest(url: url)
      request.timeoutInterval = 8
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
            data.count < 1_000_000,
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let listing = (payload["results"] as? [[String: Any]])?.first else {
        result(nil); return
      }
      result(["production": true,
              "installedVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
              "systemVersion": UIDevice.current.systemVersion,
              "listing": listing])
    } catch { result(nil) }
    #endif
  }
}
