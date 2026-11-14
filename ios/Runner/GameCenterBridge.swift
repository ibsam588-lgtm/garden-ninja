import Flutter
import GameKit
import UIKit

final class GameCenterBridge: NSObject, GKGameCenterControllerDelegate {
  private let channel: FlutterMethodChannel
  private var authenticationResults: [FlutterResult] = []
  private var authenticating = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "garden_ninja/game_center", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      switch call.method {
      case "status":
        let player = GKLocalPlayer.local
        result(["authenticated": player.isAuthenticated,
                "playerId": player.isAuthenticated ? player.gamePlayerID : ""])
      case "authenticate":
        self.authenticate(result)
      case "showDashboard":
        guard GKLocalPlayer.local.isAuthenticated,
              let presenter = self.presenter, presenter.presentedViewController == nil else {
          result(false)
          return
        }
        let dashboard = GKGameCenterViewController(state: .default)
        dashboard.gameCenterDelegate = self
        presenter.present(dashboard, animated: true) { result(true) }
      case "report":
        self.report(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var presenter: UIViewController? {
    guard UIApplication.shared.applicationState == .active else { return nil }
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows.first { $0.isKeyWindow }?.rootViewController
  }

  private func authenticate(_ result: @escaping FlutterResult) {
    if GKLocalPlayer.local.isAuthenticated { result(true); return }
    guard presenter != nil else { result(false); return }
    authenticationResults.append(result)
    guard !authenticating else { return }
    authenticating = true
    // Set only after a player taps Game Center; decline never blocks gameplay.
    GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let controller = controller {
          guard let presenter = self.presenter, presenter.presentedViewController == nil else {
            self.finishAuthentication(false)
            return
          }
          presenter.present(controller, animated: true)
        } else {
          self.finishAuthentication(error == nil && GKLocalPlayer.local.isAuthenticated)
        }
      }
    }
  }

  private func finishAuthentication(_ success: Bool) {
    authenticating = false
    let results = authenticationResults
    authenticationResults.removeAll()
    results.forEach { $0(success) }
  }

  private func report(_ arguments: Any?, result: @escaping FlutterResult) {
    let player = GKLocalPlayer.local
    guard player.isAuthenticated,
          let values = arguments as? [String: Any],
          values["playerId"] as? String == player.gamePlayerID,
          let score = values["arcadeScore"] as? Int,
          let orders = values["orders"] as? Int,
          let tier = values["tier"] as? Int,
          (0...1_000_000_000).contains(score), (0...1_000_000).contains(orders),
          (1...6).contains(tier) else { result(false); return }

    let group = DispatchGroup()
    // All callbacks settle on the main queue so completion state stays serialized.
    var succeeded = true
    for (id, value) in [("arcade_score", score), ("harvest_orders", orders)] where value > 0 {
      group.enter()
      GKLeaderboard.submitScore(value, context: 0, player: player,
        leaderboardIDs: ["com.corsairlabs.gardenNinja.\(id)"]) { error in
        DispatchQueue.main.async {
          succeeded = succeeded && error == nil
          group.leave()
        }
      }
    }
    let progress: [(String, Double)] = [
      ("first_slice", score > 0 ? 100 : 0),
      ("score_10000", min(100, Double(score) / 100)),
      ("first_harvest", orders > 0 ? 100 : 0),
      ("harvest_100", min(100, Double(orders))),
      ("grand_estate", Double(tier - 1) * 20),
    ]
    let achievements = progress.filter { $0.1 > 0 }.map { id, percent -> GKAchievement in
      let achievement = GKAchievement(identifier: "com.corsairlabs.gardenNinja.\(id)")
      achievement.percentComplete = percent
      achievement.showsCompletionBanner = true
      return achievement
    }
    if !achievements.isEmpty {
      group.enter()
      GKAchievement.report(achievements) { error in
        DispatchQueue.main.async {
          succeeded = succeeded && error == nil
          group.leave()
        }
      }
    }
    group.notify(queue: .main) { result(succeeded) }
  }

  func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
    gameCenterViewController.dismiss(animated: true)
  }
}
