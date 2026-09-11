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
  SharedPreferences.setMockInitialValues({
    'garden_ninja_garden_tutorial_v3': true,
    ...prefs,
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const GardenNinjaApp());
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('Garden Ninja shows home and can start play', (tester) async {
    await pumpGardenNinja(tester);

    expect(find.text('Garden'), findsAtLeastNWidgets(1));
    expect(find.text('NINJA'), findsAtLeastNWidgets(1));
    expect(find.text('SWIPE. SLASH. SAVE THE GARDEN!'), findsOneWidget);
    expect(find.text('840'), findsWidgets);
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

  testWidgets('quitting a run requires confirmation', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('QUIT RUN'), findsOneWidget);

    await tester.tap(find.text('QUIT RUN'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Quit this run?'), findsOneWidget);
    expect(find.text('Keep playing'), findsOneWidget);

    await tester.tap(find.text('Quit run'));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byKey(const ValueKey('primary-PLAY')), findsOneWidget);
    expect(find.text('Quit this run?'), findsNothing);
  });

  testWidgets('approved harvest garden replaces the old care toolbar', (
    tester,
  ) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('harvest-garden')), findsOneWidget);
    expect(find.text('My Garden'), findsOneWidget);
    expect(find.text('Start harvest'), findsOneWidget);
    expect(find.text('Strawberries  0/12'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-tool-water')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('harvest-back')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('primary-PLAY')), findsOneWidget);
  });

  testWidgets(
    'legacy balance and plots survive a new garden upgrade and reopening',
    (tester) async {
      await pumpGardenNinja(
        tester,
        prefs: {
          'garden_ninja_garden_v4': jsonEncode({
            'seeds': 1500,
            'gardenLevel': 3,
            'gardenHouseTier': 0,
            'plots': [
              {'id': 0, 'plantIndex': 6, 'mature': true, 'growth': 1},
            ],
          }),
        },
      );
      await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1,500'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('harvest-build')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('harvest-buy-upgrade')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('600'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['seeds'], 600);
      expect(saved['harvestMastery']['greenhouse'], 1);
      expect((saved['plots'] as List).first['plantIndex'], 6);
      await tester.tap(find.byKey(const ValueKey('harvest-back')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('harvest-build')));
      await tester.pump();
      expect(find.text('Level 1 complete'), findsOneWidget);
    },
  );
}
