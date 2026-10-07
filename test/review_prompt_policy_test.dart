import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/review/review_prompt_policy.dart';
import 'package:garden_ninja/src/review/shared_preferences_review_prompt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeReviewPromptStore implements ReviewPromptStore {
  int count = 0;
  String? lastSession;
  String? lastRequestSession;
  int? lastRequest;
  int countAtRequest = 0;
  int? cooldownUntil;

  @override
  int get successfulSessions => count;
  @override
  String? get lastSuccessfulSession => lastSession;
  @override
  String? get lastRequestSessionId => lastRequestSession;
  @override
  int? get lastRequestAtMs => lastRequest;
  @override
  int get successfulSessionsAtLastRequest => countAtRequest;
  @override
  int? get cooldownUntilMs => cooldownUntil;

  @override
  Future<void> recordSuccessfulSession({
    required String sessionId,
    required int total,
  }) async {
    count = total;
    lastSession = sessionId;
  }
  @override
  Future<void> setLastRequest({
    required int atMs,
    required int sessionCount,
    required String sessionId,
  }) async {
    lastRequest = atMs;
    countAtRequest = sessionCount;
    lastRequestSession = sessionId;
  }
}

void main() {
  test('review count and request reservation persist in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesReviewPromptStore(preferences);
    for (var i = 1; i <= 4; i++) {
      await store.recordSuccessfulSession(sessionId: 'launch-$i', total: i);
    }
    await store.setLastRequest(
      atMs: DateTime.utc(2026).millisecondsSinceEpoch,
      sessionCount: 4,
      sessionId: 'launch-4',
    );

    final reloaded = SharedPreferencesReviewPromptStore(
      await SharedPreferences.getInstance(),
    );
    expect(reloaded.successfulSessions, 4);
    expect(reloaded.lastSuccessfulSession, 'launch-4');
    expect(reloaded.lastRequestSessionId, 'launch-4');
    expect(reloaded.successfulSessionsAtLastRequest, 4);
  });

  test('first review request waits for four persisted successful sessions', () async {
    final store = FakeReviewPromptStore();
    final policy = ReviewPromptPolicy(store: store, clock: () => DateTime.utc(2026));
    for (var i = 1; i <= 3; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }
    var requests = 0;
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-3',
        safeToPresent: true,
        launch: () async { requests += 1; return true; },
      ),
      isFalse,
    );
    await policy.recordSuccessfulSession('launch-4');
    // A recreated policy reads the same durable store, as after relaunch.
    final afterRestart = ReviewPromptPolicy(
      store: store,
      clock: () => DateTime.utc(2026),
    );
    expect(
      await afterRestart.requestIfDue(
        sessionId: 'launch-4',
        safeToPresent: true,
        launch: () async { requests += 1; return true; },
      ),
      isTrue,
    );
    expect(requests, 1);
  });

  test('duplicate success and concurrent request events count once per session', () async {
    final store = FakeReviewPromptStore();
    final policy = ReviewPromptPolicy(store: store, clock: () => DateTime.utc(2026));
    for (var i = 1; i <= 3; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }
    await policy.recordSuccessfulSession('launch-4');
    await policy.recordSuccessfulSession('launch-4');
    expect(store.count, 4);

    final pendingLaunch = Completer<bool>();
    var requests = 0;
    final first = policy.requestIfDue(
      sessionId: 'launch-4',
      safeToPresent: true,
      launch: () { requests += 1; return pendingLaunch.future; },
    );
    final duplicate = policy.requestIfDue(
      sessionId: 'launch-4',
      safeToPresent: true,
      launch: () async { requests += 1; return true; },
    );
    pendingLaunch.complete(true);
    expect(await first, isTrue);
    expect(await duplicate, isFalse);
    expect(requests, 1);
    final recreatedPolicy = ReviewPromptPolicy(
      store: store,
      clock: () => DateTime.utc(2026),
    );
    expect(
      await recreatedPolicy.requestIfDue(
        sessionId: 'launch-4',
        safeToPresent: true,
        launch: () async { requests += 1; return true; },
      ),
      isFalse,
    );
    expect(requests, 1);
  });

  test('retry requires both four more successes and thirty days', () async {
    final store = FakeReviewPromptStore();
    var now = DateTime.utc(2026, 1, 1);
    var policy = ReviewPromptPolicy(store: store, clock: () => now);
    for (var i = 1; i <= 4; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }
    await policy.requestIfDue(
      sessionId: 'launch-4',
      safeToPresent: true,
      launch: () async => true,
    );
    for (var i = 5; i <= 8; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }

    now = now.add(const Duration(days: 29));
    policy = ReviewPromptPolicy(store: store, clock: () => now);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-8', safeToPresent: true, launch: () async => true,
      ),
      isFalse,
    );
    now = now.add(const Duration(days: 1));
    policy = ReviewPromptPolicy(store: store, clock: () => now);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-8', safeToPresent: true, launch: () async => true,
      ),
      isTrue,
    );
  });

  test('an existing longer cooldown is retained', () async {
    final store = FakeReviewPromptStore()
      ..count = 8
      ..lastRequest = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch
      ..countAtRequest = 4
      ..cooldownUntil = DateTime.utc(2026, 3, 1).millisecondsSinceEpoch;
    var now = DateTime.utc(2026, 2, 15);
    var policy = ReviewPromptPolicy(
      store: store,
      clock: () => now,
    );
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-8', safeToPresent: true, launch: () async => true,
      ),
      isFalse,
    );
    now = DateTime.utc(2026, 3, 1).add(const Duration(minutes: 1));
    policy = ReviewPromptPolicy(store: store, clock: () => now);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-8',
        safeToPresent: true,
        launch: () async => true,
      ),
      isTrue,
    );
  });

  test('retry still requires four additional successful sessions', () async {
    final store = FakeReviewPromptStore();
    var now = DateTime.utc(2026, 1, 1);
    var policy = ReviewPromptPolicy(store: store, clock: () => now);
    for (var i = 1; i <= 4; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }
    await policy.requestIfDue(
      sessionId: 'launch-4',
      safeToPresent: true,
      launch: () async => true,
    );
    for (var i = 5; i <= 7; i++) {
      await policy.recordSuccessfulSession('launch-$i');
    }
    now = now.add(const Duration(days: 31));
    policy = ReviewPromptPolicy(store: store, clock: () => now);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-7',
        safeToPresent: true,
        launch: () async => true,
      ),
      isFalse,
    );
    await policy.recordSuccessfulSession('launch-8');
    policy = ReviewPromptPolicy(store: store, clock: () => now);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-8',
        safeToPresent: true,
        launch: () async => true,
      ),
      isTrue,
    );
  });

  test('unavailable/failed platform attempts are safe and never repeat this session', () async {
    final store = FakeReviewPromptStore()..count = 4;
    final policy = ReviewPromptPolicy(store: store, clock: () => DateTime.utc(2026));
    var requests = 0;
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-4', safeToPresent: false,
        launch: () async { requests += 1; return true; },
      ),
      isFalse,
    );
    expect(store.lastRequest, isNull);
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-4', safeToPresent: true,
        launch: () async { requests += 1; return false; },
      ),
      isFalse,
    );
    expect(
      await policy.requestIfDue(
        sessionId: 'launch-4', safeToPresent: true,
        launch: () async { requests += 1; return true; },
      ),
      isFalse,
    );
    expect(requests, 1);
  });

  test('review cannot overlap an ad, dialog, keyboard, or onboarding', () {
    bool safe({
      bool ad = false,
      bool dialog = false,
      bool keyboard = false,
      bool transition = false,
      bool onboarding = true,
      bool success = true,
    }) =>
        ReviewPromptPolicy.isSafePresentationMoment(
          meaningfulSuccess: success,
          onboardingComplete: onboarding,
          resultsScreenStable: true,
          transitionActive: transition,
          adActive: ad,
          dialogActive: dialog,
          keyboardVisible: keyboard,
        );
    expect(safe(), isTrue);
    expect(safe(ad: true), isFalse);
    expect(safe(transition: true), isFalse);
    expect(safe(dialog: true), isFalse);
    expect(safe(keyboard: true), isFalse);
    expect(safe(onboarding: false), isFalse);
    expect(safe(success: false), isFalse);
  });
}
