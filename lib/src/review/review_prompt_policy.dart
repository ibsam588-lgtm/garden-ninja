abstract interface class ReviewPromptStore {
  int get successfulSessions;
  String? get lastSuccessfulSession;
  String? get lastRequestSessionId;
  int? get lastRequestAtMs;
  int get successfulSessionsAtLastRequest;
  int? get cooldownUntilMs;

  Future<void> recordSuccessfulSession({
    required String sessionId,
    required int total,
  });
  Future<void> setLastRequest({
    required int atMs,
    required int sessionCount,
    required String sessionId,
  });
}

class ReviewPromptPolicy {
  ReviewPromptPolicy({
    required ReviewPromptStore store,
    required DateTime Function() clock,
  }) : _store = store,
       _clock = clock;

  static const int firstRequestAfterSessions = 4;
  static const int retryAfterSessions = 4;
  static const Duration minimumCooldown = Duration(days: 30);

  static bool isSafePresentationMoment({
    required bool meaningfulSuccess,
    required bool onboardingComplete,
    required bool resultsScreenStable,
    required bool transitionActive,
    required bool adActive,
    required bool dialogActive,
    required bool keyboardVisible,
  }) =>
      meaningfulSuccess &&
      onboardingComplete &&
      resultsScreenStable &&
      !transitionActive &&
      !adActive &&
      !dialogActive &&
      !keyboardVisible;

  final ReviewPromptStore _store;
  final DateTime Function() _clock;
  final Set<String> _attemptedThisSession = <String>{};
  Future<void> _queue = Future<void>.value();

  Future<void> recordSuccessfulSession(String sessionId) => _serialize(() async {
    if (sessionId.isEmpty || _store.lastSuccessfulSession == sessionId) {
      return;
    }
    try {
      await _store.recordSuccessfulSession(
        sessionId: sessionId,
        total: _store.successfulSessions + 1,
      );
    } catch (_) {
      // Review bookkeeping must not interrupt gameplay if local storage fails.
    }
  });

  Future<bool> requestIfDue({
    required String sessionId,
    required bool safeToPresent,
    required Future<bool> Function() launch,
  }) => _serialize(() async {
    if (sessionId.isEmpty ||
        !safeToPresent ||
        _attemptedThisSession.contains(sessionId) ||
        _store.lastRequestSessionId == sessionId) {
      return false;
    }

    final int total = _store.successfulSessions;
    final int? requestedAt = _store.lastRequestAtMs;
    if (requestedAt == null) {
      if (total < firstRequestAfterSessions ||
          _clock().millisecondsSinceEpoch < (_store.cooldownUntilMs ?? 0)) {
        return false;
      }
    } else {
      final int requiredCount =
          _store.successfulSessionsAtLastRequest + retryAfterSessions;
      final int cooldownEndsAt = maxDate(
        requestedAt + minimumCooldown.inMilliseconds,
        _store.cooldownUntilMs ?? 0,
      );
      if (total < requiredCount ||
          _clock().millisecondsSinceEpoch < cooldownEndsAt) {
        return false;
      }
    }

    _attemptedThisSession.add(sessionId);
    // Reserve the request before crossing the platform boundary. A completion
    // callback only means the Play task completed; it does not mean a card was
    // shown or that the user submitted a review.
    try {
      await _store.setLastRequest(
        atMs: _clock().millisecondsSinceEpoch,
        sessionCount: total,
        sessionId: sessionId,
      );
      return await launch();
    } catch (_) {
      return false;
    }
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<T> result = _queue.then((_) => action());
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  int maxDate(int first, int second) => first > second ? first : second;
}
