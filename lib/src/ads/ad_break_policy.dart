class AdBreakPolicy {
  AdBreakPolicy({this.runsPerInterstitial = 1})
    : assert(runsPerInterstitial > 0);

  final int runsPerInterstitial;
  int _completedRunsSinceAd = 0;

  int get completedRunsSinceAd => _completedRunsSinceAd;
  bool get isInterstitialDue => _completedRunsSinceAd >= runsPerInterstitial;

  void recordRunCompleted() {
    _completedRunsSinceAd += 1;
  }

  void recordAdExperience() {
    _completedRunsSinceAd = 0;
  }
}
