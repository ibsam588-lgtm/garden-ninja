import 'package:flutter/foundation.dart';

/// Each store has its own LevelPlay app and ad units. Android credentials must
/// never be used as a fallback for an iOS build.
class LevelPlayConfig {
  const LevelPlayConfig({
    this.appKey = '',
    this.bannerAdUnitId = '',
    this.interstitialAdUnitId = '',
    this.rewardedAdUnitId = '',
  });

  final String appKey;
  final String bannerAdUnitId;
  final String interstitialAdUnitId;
  final String rewardedAdUnitId;

  static const android = LevelPlayConfig(
    appKey: String.fromEnvironment('LEVELPLAY_APP_KEY'),
    bannerAdUnitId: String.fromEnvironment('LEVELPLAY_BANNER_AD_UNIT_ID'),
    interstitialAdUnitId: String.fromEnvironment(
      'LEVELPLAY_INTERSTITIAL_AD_UNIT_ID',
    ),
    rewardedAdUnitId: String.fromEnvironment('LEVELPLAY_REWARDED_AD_UNIT_ID'),
  );

  static const ios = LevelPlayConfig(
    appKey: String.fromEnvironment('LEVELPLAY_IOS_APP_KEY'),
    bannerAdUnitId: String.fromEnvironment('LEVELPLAY_IOS_BANNER_AD_UNIT_ID'),
    interstitialAdUnitId: String.fromEnvironment(
      'LEVELPLAY_IOS_INTERSTITIAL_AD_UNIT_ID',
    ),
    rewardedAdUnitId: String.fromEnvironment(
      'LEVELPLAY_IOS_REWARDED_AD_UNIT_ID',
    ),
  );

  static LevelPlayConfig forPlatform(
    TargetPlatform platform, {
    LevelPlayConfig androidConfig = android,
    LevelPlayConfig iosConfig = ios,
  }) => switch (platform) {
    TargetPlatform.android => androidConfig,
    TargetPlatform.iOS => iosConfig,
    _ => const LevelPlayConfig(),
  };
}
