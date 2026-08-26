import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_break_policy.dart';

void main() {
  test('interstitial becomes due after three completed runs', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    policy.recordRunCompleted();
    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isFalse);

    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isTrue);
  });

  test('any completed ad experience resets the ad break cadence', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    for (int i = 0; i < 3; i += 1) {
      policy.recordRunCompleted();
    }
    policy.recordAdExperience();

    expect(policy.completedRunsSinceAd, 0);
    expect(policy.isInterstitialDue, isFalse);
  });
}
