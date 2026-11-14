import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/game_center/game_center_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SharedPreferences prefs;
  late GameCenterService service;
  late List<MethodCall> calls;
  var authenticated = false;
  var acceptReport = true;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = GameCenterService()..initialize(prefs);
    calls = [];
    authenticated = false;
    acceptReport = true;
    messenger.setMockMethodCallHandler(GameCenterService.channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'status':
          return {
            'authenticated': authenticated,
            'playerId': authenticated ? 'player-a' : '',
          };
        case 'authenticate':
          return authenticated;
        case 'report':
          return acceptReport;
        case 'showDashboard':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(GameCenterService.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android never calls GameKit or creates a service save', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    service.initialize(prefs);
    service.recordArcadeScore(500);
    service.recordHarvest(orders: 10, tier: 2);
    await service.flush();
    expect(await service.openDashboard(), isFalse);
    expect(calls, isEmpty);
    expect(prefs.containsKey(GameCenterService.saveKey), isFalse);
  });

  test(
    'declining sign-in preserves records without submitting or opening UI',
    () async {
      service.recordArcadeScore(500);
      service.recordHarvest(orders: 10, tier: 2);
      await pumpEventQueue();
      expect(await service.openDashboard(), isFalse);
      expect(
        calls.where((c) => c.method == 'report' || c.method == 'showDashboard'),
        isEmpty,
      );
      final saved = jsonDecode(prefs.getString(GameCenterService.saveKey)!);
      expect(saved, {'arcadeScore': 500, 'orders': 10, 'tier': 2});
    },
  );

  test(
    'restores earned records and only submits to an authenticated player',
    () async {
      service.recordArcadeScore(2500);
      service.recordArcadeScore(30);
      service.recordHarvest(orders: 15, tier: 3);
      service.recordHarvest(orders: 2, tier: 1);
      await pumpEventQueue();
      service = GameCenterService()..initialize(prefs);
      authenticated = true;
      expect(await service.openDashboard(), isTrue);
      final report = calls.singleWhere((c) => c.method == 'report');
      expect(report.arguments, {
        'arcadeScore': 2500,
        'orders': 15,
        'tier': 3,
        'playerId': 'player-a',
      });
      await service.flush();
      expect(calls.where((c) => c.method == 'report').length, 1);
    },
  );

  test(
    'failed upload is retried and does not prevent dashboard access',
    () async {
      service.recordArcadeScore(10000);
      await pumpEventQueue();
      authenticated = true;
      acceptReport = false;
      expect(await service.openDashboard(), isTrue);
      acceptReport = true;
      await service.flush();
      expect(calls.where((c) => c.method == 'report').length, 2);
      expect(prefs.getString(GameCenterService.saveKey), contains('10000'));
    },
  );

  test(
    'records earned during an in-flight upload are submitted afterwards',
    () async {
      final firstReport = Completer<bool>();
      final reports = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(GameCenterService.channel, (
        call,
      ) async {
        if (call.method == 'status') {
          return {'authenticated': true, 'playerId': 'player-a'};
        }
        if (call.method == 'report') {
          reports.add(Map<Object?, Object?>.from(call.arguments as Map));
          return reports.length == 1 ? firstReport.future : true;
        }
        return true;
      });
      service.recordArcadeScore(100);
      await pumpEventQueue();
      service.recordArcadeScore(200);
      service.recordHarvest(orders: 3, tier: 2);
      await pumpEventQueue();
      firstReport.complete(true);
      await pumpEventQueue();
      expect(reports.length, 2);
      expect(reports.last['arcadeScore'], 200);
      expect(reports.last['orders'], 3);
    },
  );

  test(
    'missing native service and corrupted saves do not prevent play',
    () async {
      await prefs.setString(GameCenterService.saveKey, '{damaged');
      service = GameCenterService()..initialize(prefs);
      messenger.setMockMethodCallHandler(GameCenterService.channel, (_) async {
        throw PlatformException(code: 'UNAVAILABLE');
      });
      service.recordHarvest(orders: 1, tier: 1);
      await pumpEventQueue();
      expect(await service.openDashboard(), isFalse);
      expect(
        jsonDecode(prefs.getString(GameCenterService.saveKey)!)['orders'],
        1,
      );
    },
  );
}
