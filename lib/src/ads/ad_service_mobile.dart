import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:garden_ninja/src/ads/ad_load_gate.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

abstract class AppRewardedAd {
  Future<void> show({
    required String placementName,
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
  static _LevelPlayRewardedAdHandle? _rewarded;
  static Timer? _initRetryTimer;
  static Timer? _interstitialRetryTimer;
  static Timer? _rewardedRetryTimer;
  static final ValueNotifier<int> _availability = ValueNotifier<int>(0);

  static ValueListenable<int> get availability => _availability;

  static bool get _mobileSupported => Platform.isAndroid || Platform.isIOS;
  static bool get shouldShowAds =>
      !isSuppressedForStoreScreenshots && _mobileSupported && _runtimeEnabled;
  static bool get hasBannerAds =>
      shouldShowAds && _bannerAdUnitId.trim().isNotEmpty;
  static bool get hasInterstitialAds =>
      shouldShowAds && _interstitialAdUnitId.trim().isNotEmpty;
  static bool get hasRewardedAds =>
      shouldShowAds && _rewardedAdUnitId.trim().isNotEmpty;
  static bool get isInterstitialReady =>
      hasInterstitialAds && (_interstitial?.isReady ?? false);
  static bool get isRewardedReady =>
      hasRewardedAds && (_rewarded?.isReady ?? false);

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
      final Completer<bool> initResult = Completer<bool>();
      await LevelPlay.init(
        initRequest: initRequest,
        initListener: _LevelPlayInitLogger(
          onSuccess: () {
            if (!initResult.isCompleted) {
              initResult.complete(true);
            }
          },
          onFailed: (error) {
            if (!initResult.isCompleted) {
              initResult.complete(false);
            }
          },
        ),
      );
      final bool initialized = await initResult.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log('LevelPlay init callback timed out; ads disabled.');
          return false;
        },
      );
      _runtimeEnabled = initialized;
      _notifyAvailability();
      if (!initialized) {
        _initStarted = false;
        _scheduleInitRetry();
        return;
      }
      _initRetryTimer?.cancel();
      if (levelPlayTestSuite) {
        unawaited(LevelPlay.validateIntegration());
      }
      _preloadVideoAds();
    } catch (error) {
      _runtimeEnabled = false;
      _initStarted = false;
      _notifyAvailability();
      _log('LevelPlay init failed: $error');
      _scheduleInitRetry();
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
    final bool shown = await ad.show(placementName: placementName);
    if (!shown) {
      _preloadInterstitial();
    }
    return shown;
  }

  static void loadRewarded({
    required void Function(AppRewardedAd ad) onLoaded,
    required void Function(Object error) onFailed,
  }) {
    if (!hasRewardedAds) {
      onFailed(StateError('LevelPlay rewarded ads are not configured.'));
      return;
    }

    final _LevelPlayRewardedAdHandle ad = _rewarded ?? _createRewarded();
    unawaited(
      ad.load().then((bool loaded) {
        _notifyAvailability();
        if (loaded) {
          onLoaded(ad);
          return;
        }
        _scheduleRewardedRetry();
        onFailed(StateError('LevelPlay rewarded video did not load.'));
      }),
    );
  }

  static _LevelPlayInterstitialAdHandle _createInterstitial() {
    late final _LevelPlayInterstitialAdHandle ad;
    ad = _LevelPlayInterstitialAdHandle(
      adUnitId: _interstitialAdUnitId,
      onStateChanged: _notifyAvailability,
      onFinished: () {
        if (identical(_interstitial, ad)) {
          _interstitial = null;
        }
        _notifyAvailability();
        _preloadInterstitial();
      },
    );
    _interstitial = ad;
    return ad;
  }

  static _LevelPlayRewardedAdHandle _createRewarded() {
    late final _LevelPlayRewardedAdHandle ad;
    ad = _LevelPlayRewardedAdHandle(
      adUnitId: _rewardedAdUnitId,
      onStateChanged: _notifyAvailability,
      onFinished: () {
        if (identical(_rewarded, ad)) {
          _rewarded = null;
        }
        _notifyAvailability();
        _preloadRewarded();
      },
    );
    _rewarded = ad;
    return ad;
  }

  static void _preloadVideoAds() {
    _preloadInterstitial();
    _preloadRewarded();
  }

  static void _preloadInterstitial() {
    if (!hasInterstitialAds) {
      return;
    }
    _interstitialRetryTimer?.cancel();
    final _LevelPlayInterstitialAdHandle ad =
        _interstitial ?? _createInterstitial();
    unawaited(
      ad.load().then((bool loaded) {
        _notifyAvailability();
        if (!loaded && identical(_interstitial, ad)) {
          _scheduleInterstitialRetry();
        }
      }),
    );
  }

  static void _preloadRewarded() {
    if (!hasRewardedAds) {
      return;
    }
    _rewardedRetryTimer?.cancel();
    final _LevelPlayRewardedAdHandle ad = _rewarded ?? _createRewarded();
    unawaited(
      ad.load().then((bool loaded) {
        _notifyAvailability();
        if (!loaded && identical(_rewarded, ad)) {
          _scheduleRewardedRetry();
        }
      }),
    );
  }

  static void _scheduleInterstitialRetry() {
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = Timer(
      const Duration(seconds: 20),
      _preloadInterstitial,
    );
  }

  static void _scheduleInitRetry() {
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer(const Duration(seconds: 30), () {
      unawaited(initialize());
    });
  }

  static void _scheduleRewardedRetry() {
    _rewardedRetryTimer?.cancel();
    _rewardedRetryTimer = Timer(const Duration(seconds: 20), _preloadRewarded);
  }

  static void _notifyAvailability() {
    _availability.value += 1;
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
  const GardenNinjaBannerAd({required this.placementName, super.key});

  final String placementName;

  @override
  State<GardenNinjaBannerAd> createState() => _GardenNinjaBannerAdState();
}

class _GardenNinjaBannerAdState extends State<GardenNinjaBannerAd> {
  final GlobalKey<LevelPlayBannerAdViewState> _bannerKey =
      GlobalKey<LevelPlayBannerAdViewState>();
  late final _LevelPlayBannerListener _listener;
  Timer? _retryTimer;
  bool _platformReady = false;

  @override
  void initState() {
    super.initState();
    _listener = _LevelPlayBannerListener(
      onLoaded: () {
        _retryTimer?.cancel();
        _retryTimer = null;
      },
      onFailed: (error) {
        AdService._log('Banner failed: $error');
        _scheduleRetry();
      },
    );
  }

  void _loadBanner() {
    if (!mounted || !_platformReady) {
      return;
    }
    unawaited(
      (_bannerKey.currentState?.loadAd() ?? Future<void>.value()).catchError((
        Object error,
      ) {
        AdService._log('Banner load request failed: $error');
        _scheduleRetry();
      }),
    );
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 20), _loadBanner);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_bannerKey.currentState?.destroy() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.hasBannerAds) {
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
            placementName: widget.placementName,
            onPlatformViewCreated: () {
              _platformReady = true;
              _loadBanner();
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
    required this.onStateChanged,
    required this.onFinished,
  }) : _ad = LevelPlayInterstitialAd(adUnitId: adUnitId) {
    _ad.setListener(this);
  }

  final LevelPlayInterstitialAd _ad;
  final VoidCallback onStateChanged;
  final VoidCallback onFinished;
  final AdLoadGate _loadGate = AdLoadGate();
  bool _disposed = false;
  bool _showing = false;
  bool _finishNotified = false;
  Completer<bool>? _showCompleter;

  bool get isReady => !_disposed && _loadGate.isReady;

  Future<bool> load() async {
    if (_disposed) {
      return false;
    }
    if (_loadGate.isReady) {
      try {
        if (await _ad.isAdReady()) {
          return true;
        }
      } catch (_) {}
      _loadGate.consume();
    }

    final bool loaded = await _loadGate.load(_ad.loadAd);
    if (!loaded || _disposed) {
      return false;
    }
    try {
      final bool ready = await _ad.isAdReady();
      if (!ready) {
        _loadGate.markFailed();
        onStateChanged();
      }
      return ready;
    } catch (_) {
      _loadGate.markFailed();
      onStateChanged();
      return false;
    }
  }

  Future<bool> show({required String placementName}) async {
    if (_disposed || _showing) {
      return false;
    }
    try {
      final bool ready = await load();
      if (!ready) {
        return false;
      }
      _showing = true;
      _loadGate.consume();
      onStateChanged();
      final Completer<bool> completion = Completer<bool>();
      _showCompleter = completion;
      await _ad.showAd(placementName: placementName);
      return await completion.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          AdService._log('Interstitial close callback timed out.');
          _completeShow(false);
          unawaited(dispose());
          _notifyFinished();
          return false;
        },
      );
    } catch (error) {
      AdService._log('Interstitial show failed: $error');
      _completeShow(false);
      await dispose();
      _notifyFinished();
      return false;
    }
  }

  void _completeShow(bool shown) {
    _showing = false;
    final Completer<bool>? completer = _showCompleter;
    _showCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(shown);
    }
  }

  void _notifyFinished() {
    if (_finishNotified) {
      return;
    }
    _finishNotified = true;
    onFinished();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _loadGate.dispose();
    try {
      await _ad.dispose();
    } catch (_) {}
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    _loadGate.markLoaded();
    onStateChanged();
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    _loadGate.markFailed();
    onStateChanged();
    AdService._log('Interstitial load callback failed: $error');
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    _completeShow(true);
    unawaited(dispose());
    _notifyFinished();
  }

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    AdService._log('Interstitial display failed: $error');
    _completeShow(false);
    unawaited(dispose());
    _notifyFinished();
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
    required this.onStateChanged,
    required this.onFinished,
  }) : _ad = LevelPlayRewardedAd(adUnitId: adUnitId) {
    _ad.setListener(this);
  }

  final LevelPlayRewardedAd _ad;
  final VoidCallback onStateChanged;
  final VoidCallback onFinished;
  final AdLoadGate _loadGate = AdLoadGate();
  Future<void> Function()? _onRewarded;
  VoidCallback? _onClosed;
  void Function(Object error)? _onFailedToShow;
  bool _rewardGranted = false;
  bool _disposed = false;
  bool _finishNotified = false;

  bool get isReady => !_disposed && _loadGate.isReady;

  Future<bool> load() async {
    if (_disposed) {
      return false;
    }
    if (_loadGate.isReady) {
      try {
        if (await _ad.isAdReady()) {
          return true;
        }
      } catch (_) {}
      _loadGate.consume();
    }

    final bool loaded = await _loadGate.load(_ad.loadAd);
    if (!loaded || _disposed) {
      return false;
    }
    try {
      final bool ready = await _ad.isAdReady();
      if (!ready) {
        _loadGate.markFailed();
        onStateChanged();
      }
      return ready;
    } catch (_) {
      _loadGate.markFailed();
      onStateChanged();
      return false;
    }
  }

  @override
  Future<void> show({
    required String placementName,
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
      if (!await load()) {
        onFailedToShow(StateError('LevelPlay rewarded ad is not ready.'));
        await dispose();
        return;
      }
      _loadGate.consume();
      onStateChanged();
      await _ad.showAd(placementName: placementName);
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
    _loadGate.dispose();
    try {
      await _ad.dispose();
    } catch (_) {}
    _notifyFinished();
  }

  void _notifyFinished() {
    if (_finishNotified) {
      return;
    }
    _finishNotified = true;
    onFinished();
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    if (!_disposed) {
      _loadGate.markLoaded();
      onStateChanged();
    }
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    if (!_disposed) {
      _loadGate.markFailed();
      onStateChanged();
      AdService._log('Rewarded load callback failed: $error');
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
  const _LevelPlayInitLogger({required this.onSuccess, required this.onFailed});

  final VoidCallback onSuccess;
  final void Function(LevelPlayInitError error) onFailed;

  @override
  void onInitFailed(LevelPlayInitError error) {
    AdService._log('LevelPlay init callback failed: $error');
    onFailed(error);
  }

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    AdService._log('LevelPlay init succeeded.');
    onSuccess();
  }
}
