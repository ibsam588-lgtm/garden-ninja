import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_break_policy.dart';

void main() {
  test('interstitial is due after the first and every completed run', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isTrue);

    policy.recordAdExperience();
    expect(policy.isInterstitialDue, isFalse);

    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isTrue);
  });

  test('any completed ad experience resets the ad break cadence', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    policy.recordRunCompleted();
    policy.recordAdExperience();

    expect(policy.completedRunsSinceAd, 0);
    expect(policy.isInterstitialDue, isFalse);
  });
}
