import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'review_prompt_policy.dart';

class SharedPreferencesReviewPromptStore implements ReviewPromptStore {
  SharedPreferencesReviewPromptStore(this._preferences);

  static const String storageKey = 'garden_ninja_review_state_v1';
  final SharedPreferences _preferences;

  Map<String, dynamic> get _state {
    final String? raw = _preferences.getString(storageKey);
    if (raw == null) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  int get successfulSessions => (_state['successfulSessions'] as num?)?.toInt() ?? 0;

  @override
  String? get lastSuccessfulSession => _state['lastSuccessfulSession'] as String?;

  @override
  String? get lastRequestSessionId => _state['lastRequestSessionId'] as String?;

  @override
  int? get lastRequestAtMs => (_state['lastRequestAtMs'] as num?)?.toInt();

  @override
  int get successfulSessionsAtLastRequest =>
      (_state['successfulSessionsAtLastRequest'] as num?)?.toInt() ?? 0;

  @override
  int? get cooldownUntilMs => (_state['cooldownUntilMs'] as num?)?.toInt();

  @override
  Future<void> recordSuccessfulSession({
    required String sessionId,
    required int total,
  }) async {
    final Map<String, dynamic> next = _state
      ..['successfulSessions'] = total
      ..['lastSuccessfulSession'] = sessionId;
    await _preferences.setString(storageKey, jsonEncode(next));
  }

  @override
  Future<void> setLastRequest({
    required int atMs,
    required int sessionCount,
    required String sessionId,
  }) async {
    final Map<String, dynamic> next = _state
      ..['lastRequestAtMs'] = atMs
      ..['successfulSessionsAtLastRequest'] = sessionCount
      ..['lastRequestSessionId'] = sessionId;
    await _preferences.setString(storageKey, jsonEncode(next));
  }
}
