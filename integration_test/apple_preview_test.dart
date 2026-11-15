// A real iOS simulator play session for App Store Preview capture.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:garden_ninja/src/garden/harvest_art.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'record a real harvest and arcade session',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'garden_ninja_garden_tutorial_v3': true,
      });
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await HarvestArt.load();
      await tester.pumpWidget(const GardenNinjaApp());
      await tester.pump(const Duration(seconds: 3));
      File(
        '${Directory.systemTemp.path}/garden_ninja_preview_ready',
      ).writeAsStringSync('ready');
      // Give simctl's recorder time to start, then perform actual UI interactions.
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('harvest-start')));
      await tester.pump(const Duration(seconds: 8));
      for (var row = 0; row < 3; row++) {
        final start = row * 4;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey('harvest-crop-$start'))),
        );
        for (var col = 1; col < 4; col++) {
          await gesture.moveTo(
            tester.getCenter(
              find.byKey(ValueKey('harvest-crop-${start + col}')),
            ),
          );
          await tester.pump(const Duration(milliseconds: 160));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.tap(find.byKey(const ValueKey('harvest-pause')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('harvest-finish')));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.byKey(const ValueKey('harvest-sheet-close')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('harvest-back')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 150));
      for (var i = 0; i < 18; i++) {
        final weeds = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('target-'),
        );
        // Only cut weeds; flowers remain protected during the recorded session.
        if (i == 0) await tester.tap(find.byKey(const ValueKey('target-1')));
        if (i == 4 || i == 9) {
          final key = ValueKey('target-${i == 4 ? 3 : 5}');
          if (find.byKey(key).evaluate().isNotEmpty) {
            await tester.tap(find.byKey(key));
          }
        }
        expect(weeds.evaluate().isNotEmpty, isTrue);
        await tester.pump(const Duration(milliseconds: 420));
      }
      expect(tester.takeException(), isNull);
      File(
        '${Directory.systemTemp.path}/garden_ninja_preview_done',
      ).writeAsStringSync('done');
      await tester.pump(const Duration(seconds: 2));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
