import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [
    const Size(375, 667),
    const Size(393, 852),
    const Size(768, 1024),
  ]) {
    testWidgets('iOS home, harvest and arcade work at $size', (tester) async {
      SharedPreferences.setMockInitialValues({
        'garden_ninja_garden_tutorial_v3': true,
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugForcePlayUpdateChecks = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      // Approximate the top sensor and bottom home-indicator safe areas.
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        debugForcePlayUpdateChecks = false;
        tester.view.reset();
      });
      var playUpdateChecks = 0;
      const updates = MethodChannel('de.ffuf.in_app_update/methods');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(updates, (_) async {
        playUpdateChecks++;
        throw PlatformException(code: 'ANDROID_ONLY');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(updates, null));

      try {
        await tester.pumpWidget(const GardenNinjaApp());
        await tester.pump(const Duration(milliseconds: 200));
        expect(playUpdateChecks, 0);
        expect(find.text('Update Required'), findsNothing);
        expect(find.byKey(const ValueKey('rate-app')), findsNothing);
        expect(find.byKey(const ValueKey('game-center')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('harvest-garden')), findsOneWidget);
        expect(find.text('Start harvest'), findsOneWidget);
        await tester.tap(find.text('Start harvest'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        // Recreate the screen before checking arcade play to end the harvest timer.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(const GardenNinjaApp());
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('SCORE'), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        debugForcePlayUpdateChecks = false;
      }
    });
  }
}
