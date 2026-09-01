import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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

  static final ValueNotifier<int> _availability = ValueNotifier<int>(0);

  static ValueListenable<int> get availability => _availability;

  static const bool isSuppressedForStoreScreenshots = bool.fromEnvironment(
    'STORE_SCREENSHOTS',
  );

  static bool get shouldShowAds => false;
  static bool get hasBannerAds => false;
  static bool get hasInterstitialAds => false;
  static bool get hasRewardedAds => false;
  static bool get isInterstitialReady => false;
  static bool get isRewardedReady => false;

  static Future<void> initialize() async {}
  static Future<bool> showInterstitial({String placementName = ''}) async {
    return false;
  }

  static void loadRewarded({
    required void Function(AppRewardedAd ad) onLoaded,
    required void Function(Object error) onFailed,
  }) {}
}

class GardenNinjaBannerAd extends StatelessWidget {
  const GardenNinjaBannerAd({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
