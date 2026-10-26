import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_break_policy.dart';

void main() {
  test('interstitial is due after every three completed rounds', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    for (var run = 0; run < 2; run++) {
      policy.recordRunCompleted();
      expect(policy.isInterstitialDue, isFalse);
    }
    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isTrue);

    policy.recordAdExperience();
    expect(policy.isInterstitialDue, isFalse);

    policy.recordRunCompleted();
    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isFalse);
    policy.recordRunCompleted();
    expect(policy.isInterstitialDue, isTrue);
  });

  test('unavailable ads remain due until an ad was actually shown', () {
    final AdBreakPolicy policy = AdBreakPolicy();
    for (var run = 0; run < 4; run++) {
      policy.recordRunCompleted();
    }
    expect(policy.completedRunsSinceAd, 4);
    expect(policy.isInterstitialDue, isTrue);
    policy.recordAdExperience();
    expect(policy.isInterstitialDue, isFalse);
  });

  test('any completed ad experience resets the ad break cadence', () {
    final AdBreakPolicy policy = AdBreakPolicy();

    policy.recordRunCompleted();
    policy.recordAdExperience();

    expect(policy.completedRunsSinceAd, 0);
    expect(policy.isInterstitialDue, isFalse);
  });
}
