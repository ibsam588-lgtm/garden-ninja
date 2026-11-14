import Flutter
import UIKit
import AppTrackingTransparency
import FBAudienceNetwork
import IronSource
import InMobiCMP

/// Consent is resolved before LevelPlay can initialize. Errors leave play usable.
final class AdPrivacyBridge: NSObject, ChoiceCmpDelegate, CCPADelegate {
  private let channel: FlutterMethodChannel
  private var pending: [FlutterResult] = []
  private var started = false
  private var loaded = false
  private var visible = false
  private var resolved = false
  private var requestTracking = false
  private var gdprApplies = true
  private var usApplies = true
  private var optOut = true
  private var consents = AdPrivacyBridge.networkConsents(false)
  private var timeout: DispatchWorkItem?
  private var completing = false
  private let usChoiceKey = "garden_ninja_us_ad_privacy_v1"

  private static func networkConsents(_ allowed: Bool) -> [String: NSNumber] {
    ["UnityAds": NSNumber(value: allowed), "Chartboost": NSNumber(value: allowed),
     "Facebook": NSNumber(value: allowed)]
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "garden_ninja/ios_privacy", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      guard call.method == "prepareAds" || call.method == "showPrivacyOptions" else {
        result(FlutterMethodNotImplemented); return
      }
      guard UIApplication.shared.applicationState == .active else { result(false); return }
      self.requestTracking = (call.arguments as? [String: Any])?["requestTracking"] as? Bool ?? true
      if call.method == "showPrivacyOptions", self.started {
        guard self.loaded, !self.visible, !self.completing else { result(false); return }
        self.resolved = false
        self.pending.append(result)
        self.armTimeout()
        self.channel.invokeMethod("privacyPending", arguments: nil)
        if self.usApplies { ChoiceCmp.shared.showUSRegulations(ccpaDelegate: self) }
        else { ChoiceCmp.shared.forceDisplayUI() }
      } else {
        self.pending.append(result)
        self.armTimeout()
        if !self.started {
          self.started = true
          // The SDK uses the package ID to find this app's published property.
          // p- is a portal prefix and is omitted in the native SDK API.
          ChoiceCmp.shared.startChoice(pcode: "NsyGmQjxKcASn", delegate: self,
            ccpaDelegate: self, shouldDisplayIDFA: false)
        } else { self.finishIfReady() }
      }
    }
  }

  private func armTimeout() {
    timeout?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.finish(false) }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
  }

  private func finish(_ ready: Bool) {
    timeout?.cancel()
    timeout = nil
    let results = pending
    pending.removeAll()
    results.forEach { $0(ready) }
  }

  private func finishIfReady() {
    guard loaded, resolved, !visible, !completing,
          UIApplication.shared.applicationState == .active else { return }
    completing = true
    LPMPrivacySettings.setGDPRConsents(consents)
    LPMPrivacySettings.setCCPA(optOut)
    let mayTrack = requestTracking && !optOut &&
      (!gdprApplies || consents.values.contains(NSNumber(value: true)))
    let complete: (Bool) -> Void = { [weak self] tracking in
      guard let self = self else { return }
      guard self.loaded, self.resolved, !self.visible else {
        self.completing = false
        self.finish(false)
        return
      }
      if #unavailable(iOS 17.0) { FBAdSettings.setAdvertiserTrackingEnabled(tracking) }
      self.completing = false
      self.finish(true)
      self.channel.invokeMethod("privacyReady", arguments: nil)
    }
    if mayTrack && ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
      ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async { complete(status == .authorized) }
      }
    } else { complete(mayTrack && ATTrackingManager.trackingAuthorizationStatus == .authorized) }
  }

  func cmpDidLoad(info: PingResponse) {
    DispatchQueue.main.async {
      self.loaded = info.cmpLoaded && info.cmpStatus == .loaded
      self.gdprApplies = info.gdprApplies ?? true
      self.usApplies = info.usRegulationApplies
      if self.usApplies,
         let saved = UserDefaults.standard.dictionary(forKey: self.usChoiceKey),
         let gpp = saved["gpp"] as? String, !gpp.isEmpty,
         gpp == UserDefaults.standard.string(forKey: "IABGPP_HDR_GppString"),
         let location = ChoiceCmp.shared.getGeolocation(),
         saved["location"] as? String == "\(location.country)/\(location.region)",
         let optedOut = saved["optOut"] as? Bool {
        self.optOut = optedOut
        self.consents = Self.networkConsents(!optedOut)
        self.resolved = true
        self.finishIfReady()
      }
      if info.gdprApplies == false && !self.usApplies {
        self.optOut = false
        self.consents = Self.networkConsents(true)
        self.resolved = true
        self.finishIfReady()
      }
      // An existing choice is usable only after the CMP validates it. Initial
      // loading alone never implies consent or completes the ad initialization.
      ChoiceCmp.shared.getGDPRData { data in
        if data.eventStatus == .tcloaded && !data.tcString.isEmpty && !self.usApplies {
          self.didReceiveIABVendorConsent(gdprData: data, updated: false)
        }
      }
    }
  }

  func didReceiveIABVendorConsent(gdprData: GDPRData, updated: Bool) {
    DispatchQueue.main.async {
      guard gdprData.gdprApplies != nil else { return }
      self.gdprApplies = gdprData.gdprApplies == true
      guard !self.usApplies else { return }
      let purposes = gdprData.purpose.consents
      let personalized = ["1", "3", "4"].allSatisfy { purposes[$0] == true }
      self.consents = [
        "UnityAds": NSNumber(value: !self.gdprApplies || (personalized && gdprData.vendor.consents["1549"] == true)),
        "Chartboost": NSNumber(value: !self.gdprApplies || (personalized && gdprData.vendor.consents["1601"] == true)),
        // Meta is not an IAB vendor in this property's vendor list. Never
        // manufacture a consent grant from another network's consent.
        "Facebook": NSNumber(value: !self.gdprApplies)
      ]
      self.optOut = false
      self.resolved = gdprData.eventStatus != .cmpuishown
      self.finishIfReady()
    }
  }

  func didReceiveUSRegulationsConsent(usRegData: USRegulationsData) {
    DispatchQueue.main.async {
      self.optOut = usRegData.SaleOptOut == 1 || usRegData.SharingOptOut == 1 ||
        usRegData.TargetedAdvertisingOptOut == 1 || usRegData.PersonalDataConsents == 2
      if let location = ChoiceCmp.shared.getGeolocation(), !usRegData.gppString.isEmpty {
        UserDefaults.standard.set(["gpp": usRegData.gppString,
          "location": "\(location.country)/\(location.region)", "optOut": self.optOut],
          forKey: self.usChoiceKey)
      }
      self.consents = Self.networkConsents(!self.optOut)
      self.resolved = true
      self.finishIfReady()
    }
  }

  func didReceiveCCPAConsent(string: String) {
    DispatchQueue.main.async {
      guard string.count == 4 else { return }
      self.optOut = Array(string)[2] != "N"
      self.consents = Self.networkConsents(!self.optOut)
      self.resolved = true
      self.finishIfReady()
    }
  }

  func cmpUIStatusChanged(info: DisplayInfo) {
    DispatchQueue.main.async {
      self.visible = info.displayStatus == .visible
      if self.visible {
        self.resolved = false
        self.channel.invokeMethod("privacyPending", arguments: nil)
      } else { self.finishIfReady() }
    }
  }

  func cmpDidError(error: Error) {
    DispatchQueue.main.async {
      self.loaded = false
      self.resolved = false
      self.started = false
      self.channel.invokeMethod("privacyError", arguments: nil)
      self.finish(false)
    }
  }

  func userDidMoveToOtherState() {
    DispatchQueue.main.async {
      self.resolved = false
      self.channel.invokeMethod("privacyPending", arguments: nil)
      if UIApplication.shared.applicationState == .active {
        ChoiceCmp.shared.showUSRegulations(ccpaDelegate: self)
      }
    }
  }
  func didReceiveNonIABVendorConsent(nonIabData: NonIABData, updated: Bool) {}
  func didReceiveAdditionalConsent(acData: ACData, updated: Bool) {}
  func didReceiveActionButtonTap(action: ActionButtons) {}
}
