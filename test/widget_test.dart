import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpGardenNinja(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const GardenNinjaApp());
  await tester.pump(const Duration(milliseconds: 20));
}

String gardenDayKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

void main() {
  testWidgets('Garden Ninja shows home and can start play', (tester) async {
    await pumpGardenNinja(tester);

    expect(find.text('Garden'), findsAtLeastNWidgets(1));
    expect(find.text('NINJA'), findsAtLeastNWidgets(1));
    expect(find.text('SWIPE. SLASH. SAVE THE GARDEN!'), findsOneWidget);
    expect(find.text('1,250'), findsWidgets);
    expect(find.text('PLAY'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-safe-0')), findsOneWidget);

    final weed = find.byKey(const ValueKey('target-1'));
    expect(weed, findsOneWidget);

    await tester.tap(weed);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('82'), findsOneWidget);
    expect(weed, findsOneWidget);
    expect(find.text('+82 | 1 cuts'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ClipPath && widget.clipper is SliceHalfClipper,
      ),
      findsAtLeastNWidgets(2),
    );

    final flower = find.byKey(const ValueKey('target-2'));
    expect(flower, findsOneWidget);

    await tester.tap(flower);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('-150 Plant'), findsAtLeastNWidgets(1));
    expect(find.text('Garden Saved'), findsNothing);
  });

  testWidgets('forced Play update blocks app after cancelled update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    debugForcePlayUpdateChecks = true;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const channel = MethodChannel('de.ffuf.in_app_update/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    try {
      var immediateUpdateCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'checkForUpdate':
            return {
              'updateAvailability': 2,
              'immediateAllowed': true,
              'immediateAllowedPreconditions': <int>[],
              'flexibleAllowed': false,
              'flexibleAllowedPreconditions': <int>[],
              'availableVersionCode': 2,
              'installStatus': 0,
              'packageName': 'com.gardenninja.garden_ninja',
              'clientVersionStalenessDays': 0,
              'updatePriority': 5,
            };
          case 'performImmediateUpdate':
            immediateUpdateCalls += 1;
            throw PlatformException(code: 'USER_DENIED_UPDATE');
        }
        return null;
      });

      await tester.pumpWidget(const GardenNinjaApp());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Update Required'), findsOneWidget);
      expect(
        find.text(
          'Update required. Install the latest version to keep playing.',
        ),
        findsOneWidget,
      );
      expect(find.text('UPDATE NOW'), findsOneWidget);
      expect(immediateUpdateCalls, 1);

      await tester.tap(find.text('UPDATE NOW'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(immediateUpdateCalls, 2);
      expect(find.text('Update Required'), findsOneWidget);
    } finally {
      debugForcePlayUpdateChecks = false;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('escaped weeds visibly damage the garden', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    var gardenWasDamaged = false;
    for (var i = 0; i < 420 && !gardenWasDamaged; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      gardenWasDamaged = find
          .byKey(const ValueKey('garden-damage-0'))
          .evaluate()
          .isNotEmpty;
    }

    expect(gardenWasDamaged, isTrue);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('ice power visibly freezes active weeds', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('Ice x2'), findsOneWidget);

    await tester.tap(find.text('Ice x2'));
    await tester.pump();

    expect(find.text('Freeze!'), findsOneWidget);
    expect(find.text('Ice 7s x1'), findsOneWidget);
    expect(find.byIcon(Icons.ac_unit_rounded), findsAtLeastNWidgets(1));

    await tester.pump(const Duration(milliseconds: 1100));

    expect(find.byIcon(Icons.ac_unit_rounded), findsAtLeastNWidgets(1));
  });

  testWidgets('new players can start the interactive tutorial', (tester) async {
    await pumpGardenNinja(tester);

    expect(find.text('Tutorial'), findsOneWidget);

    await tester.tap(find.text('Tutorial'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Slash the weed'), findsOneWidget);
    expect(find.text('Swipe through the weed to cut it.'), findsOneWidget);
    expect(find.byKey(const ValueKey('target-1')), findsOneWidget);
    expect(find.byIcon(Icons.swipe_rounded), findsOneWidget);
  });

  testWidgets('players can continue after a completed run', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    var reachedResults = false;
    for (var i = 0; i < 900 && !reachedResults; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      reachedResults = find
          .byKey(const ValueKey('primary-NEXT LEVEL'))
          .evaluate()
          .isNotEmpty;
    }

    expect(reachedResults, isTrue);

    await tester.tap(find.byKey(const ValueKey('primary-NEXT LEVEL')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('back on home asks before quitting', (tester) async {
    await pumpGardenNinja(tester);

    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Quit Garden Ninja?'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Quit Garden Ninja?'), findsNothing);
  });

  testWidgets('players can tend the larger garden', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('COTTAGE YARD'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('garden-plant-target-glow-3')),
      findsOneWidget,
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Water me'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-nursery-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('garden-tool-clear')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-tool-sun')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-world-selector')), findsOneWidget);
    expect(find.text('Orchard Grove'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-zoom-in')), findsNothing);
    expect(find.byKey(const ValueKey('garden-zoom-out')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('garden-world-next')));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('Bamboo Zen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-world-next')));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('Bamboo Zen'), findsOneWidget);
    expect(find.text('Moon Lotus unlocks at 3,200 pts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-tool-plant')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-3')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-nursery-sheet')), findsOneWidget);
    expect(find.text('Choose plant for this plot'), findsOneWidget);
    expect(find.text('Tap a card, then press Plant.'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-plant-option-0')), findsOneWidget);
    expect(find.text('Apple Tree'), findsOneWidget);
    expect(find.text('PLANT DAISY HERE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('garden-plant-option-6')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('PLANT APPLE TREE HERE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('garden-plant-option-2')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('PLANT PINK BLOOM HERE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('garden-confirm-plant')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Pink Bloom planted: ready in 12h'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-3')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('Watered Pink Bloom. Ready in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-tool-sun')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-3')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('Sun boost: ready in'), findsOneWidget);
  });

  testWidgets('garden shows streak, forecast, and locked meadow plots', (
    tester,
  ) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-streak-chip')), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-forecast')), findsOneWidget);
    expect(
      find.text('Cut grass to prepare the next backyard bed'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('player-garden-plot-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-garden-plot-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-garden-plot-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-garden-plot-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-garden-plot-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-garden-plot-9')), findsOneWidget);
    expect(find.byIcon(Icons.home_work_rounded), findsWidgets);
    expect(find.text('Cut grass'), findsOneWidget);
    expect(find.text('Bigger house'), findsWidgets);
  });

  testWidgets('expanding the garden opens a real meadow plot', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      find.textContaining('Use Clear to cut this grass first'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('garden-tool-clear')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('Grass cut'), findsOneWidget);
    expect(find.text('260 seeds'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('New backyard bed unlocked'), findsOneWidget);
    expect(find.byIcon(Icons.home_work_rounded), findsWidgets);
    expect(find.text('1,004'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-nursery-sheet')), findsOneWidget);
  });

  testWidgets('garden supports plant upgrades and house upgrades', (
    tester,
  ) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    await tester.tap(find.byKey(const ValueKey('garden-tool-clear')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-2')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('upgraded to Lv 2'), findsOneWidget);
    expect(find.text('Lv 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-5')));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-5')));
    await tester.pump(const Duration(milliseconds: 160));

    await tester.tap(find.byKey(const ValueKey('garden-house-upgrade')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('FAMILY BACKYARD'), findsOneWidget);
    expect(find.textContaining('Family Backyard unlocked'), findsOneWidget);
  });

  testWidgets('welcome back card recaps the garden after time away', (
    tester,
  ) async {
    final DateTime now = DateTime.now();
    await pumpGardenNinja(
      tester,
      prefs: {
        'garden_ninja_garden_v4': jsonEncode({
          'version': 2,
          'gardenLastLoginDay': gardenDayKey(now),
          'gardenLastVisitMs': now
              .subtract(const Duration(hours: 8))
              .millisecondsSinceEpoch,
        }),
      },
    );

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-welcome-card')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('ready to gather'), findsWidgets);
    expect(find.textContaining('% grown'), findsWidgets);

    await tester.tap(find.text('Welcome back'));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-welcome-card')), findsNothing);
  });

  testWidgets('overnight gift waits after a tended day', (tester) async {
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    await pumpGardenNinja(
      tester,
      prefs: {
        'garden_ninja_garden_v4': jsonEncode({
          'version': 2,
          'gardenLastLoginDay': gardenDayKey(yesterday),
          'gardenLastTendedDay': gardenDayKey(yesterday),
        }),
      },
    );

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Day 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-gift')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-gift')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.textContaining('Gift:'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-gift')), findsNothing);
  });

  testWidgets('tending every plant stamps the garden day', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('garden-tended-star')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-0')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-2')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.textContaining('Garden tended'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-tended-star')), findsOneWidget);
  });

  testWidgets('garden plants collect blooms in the orchard layout', (
    tester,
  ) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Weed!'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-1')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Collected blooms: +260 pts, +135 seeds'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-1')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      find.textContaining('Watered Blossom Bush. Ready in'),
      findsOneWidget,
    );
  });
}
