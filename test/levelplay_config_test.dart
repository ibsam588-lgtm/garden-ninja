import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/levelplay_config.dart';

void main() {
  const android = LevelPlayConfig(
    appKey: 'android',
    bannerAdUnitId: 'a-banner',
  );
  const ios = LevelPlayConfig(appKey: 'ios', rewardedAdUnitId: 'i-reward');

  test('iOS uses its own app and ad units', () {
    final config = LevelPlayConfig.forPlatform(
      TargetPlatform.iOS,
      androidConfig: android,
      iosConfig: ios,
    );
    expect(config.appKey, 'ios');
    expect(config.rewardedAdUnitId, 'i-reward');
    expect(config.bannerAdUnitId, isEmpty);
  });

  test('missing iOS configuration never falls back to Android', () {
    final config = LevelPlayConfig.forPlatform(
      TargetPlatform.iOS,
      androidConfig: android,
      iosConfig: const LevelPlayConfig(),
    );
    expect(config.appKey, isEmpty);
    expect(config.bannerAdUnitId, isEmpty);
  });

  test('Android retains its existing ad configuration', () {
    final config = LevelPlayConfig.forPlatform(
      TargetPlatform.android,
      androidConfig: android,
      iosConfig: ios,
    );
    expect(config.appKey, 'android');
    expect(config.bannerAdUnitId, 'a-banner');
  });

  test('desktop platforms do not get mobile ad credentials', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        LevelPlayConfig.forPlatform(
          platform,
          androidConfig: android,
          iosConfig: ios,
        ).appKey,
        isEmpty,
      );
    }
  });
}
