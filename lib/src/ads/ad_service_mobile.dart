import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

abstract class AppRewardedAd {
  Future<void> show({
    required Future<void> Function() onRewarded,
    required VoidCallback onClosed,
    required void Function(Object error) onFailedToShow,
  });

  Future<void> dispose();
}

class AdService {
  AdService._();

  static const bool isSuppressedForStoreScreenshots = bool.fromEnvironment(
    'STORE_SCREENSHOTS',
  );
  static const bool levelPlayChildDirected = bool.fromEnvironment(
    'LEVELPLAY_CHILD_DIRECTED',
  );
  static const bool levelPlayTestSuite = bool.fromEnvironment(
    'LEVELPLAY_TEST_SUITE',
  );

  static const String _appKey = String.fromEnvironment('LEVELPLAY_APP_KEY');
  static const String _bannerAdUnitId = String.fromEnvironment(
    'LEVELPLAY_BANNER_AD_UNIT_ID',
  );
  static const String _interstitialAdUnitId = String.fromEnvironment(
    'LEVELPLAY_INTERSTITIAL_AD_UNIT_ID',
  );
  static const String _rewardedAdUnitId = String.fromEnvironment(
    'LEVELPLAY_REWARDED_AD_UNIT_ID',
  );

  static bool _runtimeEnabled = false;
  static bool _initStarted = false;
  static _LevelPlayInterstitialAdHandle? _interstitial;

  static bool get _mobileSupported => Platform.isAndroid || Platform.isIOS;
  static bool get shouldShowAds =>
      !isSuppressedForStoreScreenshots && _mobileSupported && _runtimeEnabled;
  static bool get hasBannerAds =>
      shouldShowAds && _bannerAdUnitId.trim().isNotEmpty;
  static bool get hasInterstitialAds =>
      shouldShowAds && _interstitialAdUnitId.trim().isNotEmpty;
  static bool get hasRewardedAds =>
      shouldShowAds && _rewardedAdUnitId.trim().isNotEmpty;

  static Future<void> initialize() async {
    if (_initStarted || isSuppressedForStoreScreenshots || !_mobileSupported) {
      return;
    }
    _initStarted = true;

    if (_appKey.trim().isEmpty) {
      _log('LevelPlay app key missing; ads disabled for this build.');
      return;
    }

    try {
      await LevelPlayPrivacySettings.setCOPPA(levelPlayChildDirected);
      await LevelPlay.setAdaptersDebug(levelPlayTestSuite);
      if (levelPlayTestSuite) {
        await LevelPlay.setMetaData({
          'is_test_suite': ['enable'],
        });
      }

      final LevelPlayInitRequest initRequest = LevelPlayInitRequest.builder(
        _appKey,
      ).build();
      await LevelPlay.init(
        initRequest: initRequest,
        initListener: const _LevelPlayInitLogger(),
      );
      _runtimeEnabled = true;
      if (levelPlayTestSuite) {
        unawaited(LevelPlay.validateIntegration());
      }
      _preloadInterstitial();
    } catch (error) {
      _runtimeEnabled = false;
      _log('LevelPlay init failed: $error');
    }
  }

  static Future<bool> showInterstitial({
    String placementName = 'level_complete',
  }) async {
    if (!hasInterstitialAds) {
      return false;
    }
    final _LevelPlayInterstitialAdHandle ad =
        _interstitial ?? _createInterstitial();
    return ad.show(placementName: placementName);
  }

  static void loadRewarded({
    required void Function(AppRewardedAd ad) onLoaded,
    required void Function(Object error) onFailed,
  }) {
    if (!hasRewardedAds) {
      onFailed(StateError('LevelPlay rewarded ads are not configured.'));
      return;
    }

    late final _LevelPlayRewardedAdHandle handle;
    handle = _LevelPlayRewardedAdHandle(
      adUnitId: _rewardedAdUnitId,
      onLoaded: () => onLoaded(handle),
      onLoadFailed: onFailed,
    );
    unawaited(handle.load());
  }

  static _LevelPlayInterstitialAdHandle _createInterstitial() {
    final _LevelPlayInterstitialAdHandle ad = _LevelPlayInterstitialAdHandle(
      adUnitId: _interstitialAdUnitId,
      onFinished: _preloadInterstitial,
    );
    _interstitial = ad;
    return ad;
  }

  static void _preloadInterstitial() {
    if (!hasInterstitialAds) {
      return;
    }
    final _LevelPlayInterstitialAdHandle ad = _createInterstitial();
    unawaited(ad.load());
  }

  static void _log(String message) {
    if (!kDebugMode) {
      return;
    }
    // ignore: avoid_print
    print('[AdService] $message');
  }
}

class GardenNinjaBannerAd extends StatefulWidget {
  const GardenNinjaBannerAd({super.key});

  @override
  State<GardenNinjaBannerAd> createState() => _GardenNinjaBannerAdState();
}

class _GardenNinjaBannerAdState extends State<GardenNinjaBannerAd> {
  final GlobalKey<LevelPlayBannerAdViewState> _bannerKey =
      GlobalKey<LevelPlayBannerAdViewState>();
  late final _LevelPlayBannerListener _listener;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _listener = _LevelPlayBannerListener(
      onLoaded: () {
        if (mounted) {
          setState(() => _failed = false);
        }
      },
      onFailed: (error) {
        AdService._log('Banner failed: $error');
        if (mounted) {
          setState(() => _failed = true);
        }
      },
    );
  }

  @override
  void dispose() {
    unawaited(_bannerKey.currentState?.destroy() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.hasBannerAds || _failed) {
      return const SizedBox.shrink();
    }

    return ColoredBox(
      color: const Color(0xF20B2011),
      child: Center(
        child: SizedBox(
          width: LevelPlayAdSize.BANNER.width.toDouble(),
          height: LevelPlayAdSize.BANNER.height.toDouble(),
          child: LevelPlayBannerAdView(
            key: _bannerKey,
            adUnitId: AdService._bannerAdUnitId,
            adSize: LevelPlayAdSize.BANNER,
            listener: _listener,
            placementName: 'garden_ninja_bottom_banner',
            onPlatformViewCreated: () {
              unawaited(_bannerKey.currentState?.loadAd());
            },
          ),
        ),
      ),
    );
  }
}

class _LevelPlayInterstitialAdHandle
    implements LevelPlayInterstitialAdListener {
  _LevelPlayInterstitialAdHandle({
    required String adUnitId,
    required this.onFinished,
  }) : _ad = LevelPlayInterstitialAd(adUnitId: adUnitId) {
    _ad.setListener(this);
  }

  final LevelPlayInterstitialAd _ad;
  final VoidCallback onFinished;
  bool _loaded = false;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) {
      return;
    }
    try {
      await _ad.loadAd();
    } catch (error) {
      AdService._log('Interstitial load failed: $error');
    }
  }

  Future<bool> show({required String placementName}) async {
    if (_disposed) {
      return false;
    }
    try {
      final bool ready = _loaded && await _ad.isAdReady();
      if (!ready) {
        await load();
        return false;
      }
      await _ad.showAd(placementName: placementName);
      return true;
    } catch (error) {
      AdService._log('Interstitial show failed: $error');
      await dispose();
      onFinished();
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _ad.dispose();
    } catch (_) {}
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    _loaded = true;
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    _loaded = false;
    AdService._log('Interstitial load callback failed: $error');
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    unawaited(dispose());
    onFinished();
  }

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    AdService._log('Interstitial display failed: $error');
    unawaited(dispose());
    onFinished();
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}

class _LevelPlayRewardedAdHandle
    implements AppRewardedAd, LevelPlayRewardedAdListener {
  _LevelPlayRewardedAdHandle({
    required String adUnitId,
    required this.onLoaded,
    required this.onLoadFailed,
  }) : _ad = LevelPlayRewardedAd(adUnitId: adUnitId) {
    _ad.setListener(this);
  }

  final LevelPlayRewardedAd _ad;
  final VoidCallback onLoaded;
  final void Function(Object error) onLoadFailed;
  Future<void> Function()? _onRewarded;
  VoidCallback? _onClosed;
  void Function(Object error)? _onFailedToShow;
  bool _rewardGranted = false;
  bool _disposed = false;

  Future<void> load() => _ad.loadAd();

  @override
  Future<void> show({
    required Future<void> Function() onRewarded,
    required VoidCallback onClosed,
    required void Function(Object error) onFailedToShow,
  }) async {
    if (_disposed) {
      return;
    }
    _onRewarded = onRewarded;
    _onClosed = onClosed;
    _onFailedToShow = onFailedToShow;
    try {
      if (!await _ad.isAdReady()) {
        onFailedToShow(StateError('LevelPlay rewarded ad is not ready.'));
        await dispose();
        return;
      }
      await _ad.showAd(placementName: 'bonus_seed_reward');
    } catch (error) {
      onFailedToShow(error);
      await dispose();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _ad.dispose();
    } catch (_) {}
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    if (!_disposed) {
      onLoaded();
    }
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    if (!_disposed) {
      onLoadFailed(error);
      unawaited(dispose());
    }
  }

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) {
    if (_rewardGranted) {
      return;
    }
    _rewardGranted = true;
    final Future<void> Function()? rewardCallback = _onRewarded;
    if (rewardCallback != null) {
      unawaited(rewardCallback());
    }
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    _onClosed?.call();
    unawaited(dispose());
  }

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    _onFailedToShow?.call(error);
    unawaited(dispose());
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}

class _LevelPlayBannerListener implements LevelPlayBannerAdViewListener {
  const _LevelPlayBannerListener({
    required this.onLoaded,
    required this.onFailed,
  });

  final VoidCallback onLoaded;
  final void Function(Object error) onFailed;

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => onLoaded();

  @override
  void onAdLoadFailed(LevelPlayAdError error) => onFailed(error);

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) =>
      onFailed(error);

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}

class _LevelPlayInitLogger implements LevelPlayInitListener {
  const _LevelPlayInitLogger();

  @override
  void onInitFailed(LevelPlayInitError error) {
    AdService._log('LevelPlay init callback failed: $error');
  }

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    AdService._log('LevelPlay init succeeded.');
  }
}
