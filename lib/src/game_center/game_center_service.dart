import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Game Center is optional. Device records survive cancellation and failed uploads.
class GameCenterService {
  static const channel = MethodChannel('garden_ninja/game_center');
  static const saveKey = 'garden_ninja_game_center_v1';
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  SharedPreferences? _prefs;
  int _arcadeScore = 0;
  int _orders = 0;
  int _tier = 1;
  final Map<String, String> _submitted = {};
  Future<void> _writes = Future<void>.value();
  bool _flushing = false;
  bool _opening = false;

  void initialize(SharedPreferences prefs) {
    if (!supported) return;
    _prefs = prefs;
    try {
      final saved = jsonDecode(prefs.getString(saveKey) ?? '{}');
      if (saved is Map) {
        _arcadeScore = _integer(saved['arcadeScore'], 0, 1000000000);
        _orders = _integer(saved['orders'], 0, 1000000);
        _tier = max(1, _integer(saved['tier'], 1, 6));
      }
    } on FormatException {
      // A damaged optional service record must not prevent local play.
    }
  }

  static int _integer(Object? value, int fallback, int maximum) =>
      value is num && value.isFinite
      ? value.toInt().clamp(0, maximum)
      : fallback;

  void recordArcadeScore(int score) {
    if (!supported || score <= _arcadeScore) return;
    _arcadeScore = score.clamp(0, 1000000000);
    _save();
  }

  void recordHarvest({required int orders, required int tier}) {
    if (!supported) return;
    final nextOrders = max(_orders, orders.clamp(0, 1000000));
    final nextTier = max(_tier, tier.clamp(1, 6));
    if (_orders == nextOrders && _tier == nextTier) return;
    _orders = nextOrders;
    _tier = nextTier;
    _save();
  }

  Map<String, int> get _records => {
    'arcadeScore': _arcadeScore,
    'orders': _orders,
    'tier': _tier,
  };

  void _save() {
    final prefs = _prefs;
    if (prefs == null) return;
    final payload = jsonEncode(_records);
    _writes = _writes
        .then((_) async {
          await prefs.setString(saveKey, payload);
        })
        .catchError((Object _) {});
    unawaited(_writes.then((_) => flush()));
  }

  Future<void> flush() async {
    if (!supported || _prefs == null || _flushing) return;
    _flushing = true;
    try {
      final status = await channel.invokeMapMethod<String, Object?>('status');
      final player = status?['playerId'];
      if (status?['authenticated'] != true ||
          player is! String ||
          player.isEmpty) {
        return;
      }
      // Acknowledgements belong to a player and are never written on failure.
      while (true) {
        final snapshot = Map<String, int>.of(_records);
        final payload = jsonEncode(snapshot);
        if (_submitted[player] == payload) return;
        final accepted = await channel.invokeMethod<bool>('report', {
          ...snapshot,
          'playerId': player,
        });
        if (accepted != true) return;
        _submitted[player] = payload;
        if (payload == jsonEncode(_records)) return;
      }
    } on PlatformException {
      // Keep the durable records and retry on resume or the next Game Center visit.
    } on MissingPluginException {
      // Widget tests and unsupported hosts continue with local saves.
    } finally {
      _flushing = false;
    }
  }

  Future<bool> openDashboard() async {
    if (!supported || _opening) return false;
    _opening = true;
    try {
      if (await channel.invokeMethod<bool>('authenticate') != true) {
        return false;
      }
      await flush();
      return await channel.invokeMethod<bool>('showDashboard') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      _opening = false;
    }
  }
}
