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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'record a real harvest and arcade session',
    (tester) async {
      Future<void> animate(Duration duration) async {
        final elapsed = Stopwatch()..start();
        while (elapsed.elapsed < duration) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      var pointer = 1;
      Future<TestGesture> startGesture(Offset position) async {
        final gesture = TestGesture(
          pointer: pointer++,
          dispatcher: (event) async {
            final previous = binding.shouldPropagateDevicePointerEvents;
            binding.shouldPropagateDevicePointerEvents = true;
            try {
              binding.handlePointerEventForSource(
                event,
                source: TestBindingEventSource.device,
              );
            } finally {
              binding.shouldPropagateDevicePointerEvents = previous;
            }
          },
        );
        await gesture.down(position);
        return gesture;
      }

      Future<void> tapAt(Offset position) async {
        final gesture = await startGesture(position);
        await gesture.up();
      }

      Future<void> tap(Finder finder) => tapAt(tester.getCenter(finder));

      SharedPreferences.setMockInitialValues({
        'garden_ninja_garden_tutorial_v3': true,
      });
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await HarvestArt.load();
      await tester.pumpWidget(const GardenNinjaApp());
      await animate(const Duration(seconds: 3));
      final context = tester.element(find.byType(GardenNinjaScreen));
      await precacheImage(
        const AssetImage('assets/images/backgrounds/garden_playfield.png'),
        context,
      );
      File(
        '${Directory.systemTemp.path}/garden_ninja_preview_ready',
      ).writeAsStringSync('ready');
      // Start only when simctl confirms it is actually recording.
      final recording = File(
        '${Directory.systemTemp.path}/garden_ninja_preview_recording',
      );
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!recording.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('The native simulator recorder did not start');
        }
        await animate(const Duration(milliseconds: 100));
      }
      await animate(const Duration(milliseconds: 800));
      await tap(find.byKey(const ValueKey('home-menu-Garden')));
      await animate(const Duration(seconds: 1));
      await tap(find.byKey(const ValueKey('harvest-start')));
      await animate(const Duration(seconds: 8));
      for (var row = 0; row < 3; row++) {
        final start = row * 4;
        final gesture = await startGesture(
          tester.getCenter(find.byKey(ValueKey('harvest-crop-$start'))),
        );
        for (var col = 1; col < 4; col++) {
          await gesture.moveTo(
            tester.getCenter(
              find.byKey(ValueKey('harvest-crop-${start + col}')),
            ),
          );
          await animate(const Duration(milliseconds: 160));
        }
        await gesture.up();
        await animate(const Duration(milliseconds: 350));
      }
      await tap(find.byKey(const ValueKey('harvest-pause')));
      await animate(const Duration(milliseconds: 300));
      await tap(find.byKey(const ValueKey('harvest-finish')));
      await animate(const Duration(milliseconds: 900));
      await tap(find.byKey(const ValueKey('harvest-sheet-close')));
      await animate(const Duration(milliseconds: 200));
      await tap(find.byKey(const ValueKey('harvest-back')));
      await animate(const Duration(milliseconds: 400));
      await tap(find.byKey(const ValueKey('primary-PLAY')));
      await animate(const Duration(milliseconds: 150));
      for (var i = 0; i < 18; i++) {
        final weeds = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('target-'),
        );
        // Only cut weeds; flowers remain protected during the recorded session.
        if (i == 0) {
          await tapAt(tester.getCenter(find.byKey(const ValueKey('target-1'))));
        }
        if (i == 4 || i == 9) {
          final key = ValueKey('target-${i == 4 ? 3 : 5}');
          if (find.byKey(key).evaluate().isNotEmpty) {
            await tapAt(tester.getCenter(find.byKey(key)));
          }
        }
        expect(weeds.evaluate().isNotEmpty, isTrue);
        await animate(const Duration(milliseconds: 420));
      }
      expect(tester.takeException(), isNull);
      File(
        '${Directory.systemTemp.path}/garden_ninja_preview_done',
      ).writeAsStringSync('done');
      await animate(const Duration(seconds: 2));
      // Dispose the real native AudioPlayers before the test binding shuts down.
      await tester.pumpWidget(const SizedBox.shrink());
      await animate(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
