import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:garden_ninja/src/slicer/planter_chew.dart';
import 'package:garden_ninja/src/slicer/planter_rescue_paint.dart';
import 'package:garden_ninja/src/slicer/slicer_plant_art.dart';
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

Future<void> advanceSlicer(WidgetTester tester, int frames) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder slicerLives(int lives) => find.descendant(
  of: find.byKey(const ValueKey('slicer-life-count')),
  matching: find.text('$lives'),
);

PlanterWarningsPainter warningsPainter(WidgetTester tester) {
  final canvas = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is PlanterWarningsPainter,
  );
  return tester.widget<CustomPaint>(canvas).painter! as PlanterWarningsPainter;
}

Finder slicerTargets() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('target-');
});

SlicerPlantPainter plantPainter(WidgetTester tester, Finder target) {
  final paintedPlant = find.descendant(
    of: target,
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is SlicerPlantPainter,
    ),
  );
  return tester.widget<CustomPaint>(paintedPlant).painter!
      as SlicerPlantPainter;
}

PlanterCropPainter cropPainter(WidgetTester tester, int index) {
  final canvas = find.descendant(
    of: find.byKey(ValueKey('garden-plant-$index')),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is PlanterCropPainter,
    ),
  );
  return tester.widget<CustomPaint>(canvas).painter! as PlanterCropPainter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final art = await SlicerPlantArt.load();
    for (final kind in SlicerPlantKind.values) {
      final sprite = art.sprite(kind);
      expect(sprite, isNotNull, reason: '${kind.assetName} must decode');
      expect(
        sprite!.hasChew,
        kind == SlicerPlantKind.thorn || kind == SlicerPlantKind.bramble,
      );
    }
    for (final crop in PlanterCrop.values) {
      expect(art.crop(crop)?.width, crop.sourceWidth);
      expect(art.crop(crop)?.height, PlanterCrop.sourceHeight);
    }
  });

  testWidgets('Terrace Garden opens from home and Android back returns home', (
    tester,
  ) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('open-terrace-garden')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('terrace-release')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('primary-PLAY')), findsOneWidget);
  });

  testWidgets('Garden Ninja shows home and can start play', (tester) async {
    await pumpGardenNinja(tester);

    expect(find.text('Garden'), findsAtLeastNWidgets(1));
    expect(find.text('NINJA'), findsAtLeastNWidgets(1));
    expect(find.text('Terrace Garden'), findsOneWidget);
    expect(find.text('840'), findsWidgets);
    expect(find.text('PLAY'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('Wave 1'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-safe-0')), findsOneWidget);

    final weed = find.byKey(const ValueKey('target-1'));
    expect(weed, findsOneWidget);
    final firstFrame = plantPainter(tester, weed).pose.frame;

    final center = tester.getCenter(weed);
    await tester.dragFrom(center + const Offset(-46, 18), const Offset(92, 0));
    await advanceSlicer(tester, 3);

    expect(find.text('82'), findsOneWidget);
    expect(weed, findsOneWidget);
    expect(find.text('+82 | 1 cuts'), findsOneWidget);
    expect(plantPainter(tester, weed).pose.frame, isNot(firstFrame));
    expect(find.byKey(const ValueKey('slicer-effects')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ClipPath && widget.clipper is SliceHalfClipper,
      ),
      findsNothing,
    );

    final bramble = find.byKey(const ValueKey('target-2'));
    expect(plantPainter(tester, bramble).sprite.kind, SlicerPlantKind.bramble);
    final destinations = warningsPainter(
      tester,
    ).warnings.map((warning) => warning.flower.dx);
    expect(destinations, [67, 195]);
  });

  testWidgets('Water sweeps out weeds on contact and leaves flowers', (
    tester,
  ) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    final weed = find.byKey(const ValueKey('target-1'));
    final sweptWeed = find.byKey(const ValueKey('water-target-1'));
    final flower = find.byKey(const ValueKey('garden-plant-0'));
    await tester.tap(find.text('Water x1'));
    await tester.pump();

    expect(weed, findsNothing);
    expect(sweptWeed, findsOneWidget);
    expect(find.text('180'), findsOneWidget);
    expect(find.text('+6 seeds'), findsNothing);
    expect(flower, findsOneWidget);

    await advanceSlicer(tester, 8);
    expect(find.text('Water x0'), findsOneWidget);
    expect(sweptWeed, findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await advanceSlicer(tester, 20);
    expect(sweptWeed, findsOneWidget);
    await tester.tap(find.text('RESUME'));
    await advanceSlicer(tester, 8);

    expect(sweptWeed, findsNothing);
    expect(find.text('+6 seeds'), findsNWidgets(2));
    expect(flower, findsOneWidget);
    expect(find.byKey(const ValueKey('slicer-puddles')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is SlicerCutFramePainter,
      ),
      findsNWidgets(4),
    );
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

  testWidgets('both weeds wind up and bite their own planters', (tester) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    await advanceSlicer(tester, 100);
    expect(find.byKey(const ValueKey('garden-bite-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-bite-1')), findsOneWidget);
    final countdowns = warningsPainter(
      tester,
    ).warnings.map((warning) => warning.biteProgress);
    expect(countdowns, everyElement(isNotNull));
    expect(slicerLives(3), findsOneWidget);

    final thorn = find.byKey(const ValueKey('target-1'));
    final windupFrame = plantPainter(tester, thorn).pose.chewFrame;
    expect(windupFrame, isNotNull);
    expect(cropPainter(tester, 0).damage, 0);
    expect(cropPainter(tester, 1).damage, 0);
    await advanceSlicer(tester, 5);
    final openFrame = plantPainter(tester, thorn).pose.chewFrame!;
    expect(openFrame, greaterThan(windupFrame!));
    expect(
      PlanterChew.frameAt(openFrame / (PlanterChew.frameCount - 1)).gape,
      greaterThan(.85),
    );

    await advanceSlicer(tester, 5);
    final snapFrame = plantPainter(tester, thorn).pose.chewFrame!;
    expect(
      PlanterChew.frameAt(snapFrame / (PlanterChew.frameCount - 1)).gape,
      lessThan(.35),
    );
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.firstCut);
    expect(cropPainter(tester, 1).damage, 0);
    final piecePaint =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is PlanterFragmentsPainter,
                  ),
                )
                .painter!
            as PlanterFragmentsPainter;
    expect(piecePaint.fragments.single.before, 0);
    expect(piecePaint.fragments.single.after, PlanterCrop.bell.firstCut);
    await advanceSlicer(tester, 9);
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.secondCut);
    expect(cropPainter(tester, 1).damage, PlanterCrop.daisy.firstCut);
    expect(cropPainter(tester, 2).damage, 0);
    expect(slicerLives(3), findsOneWidget);

    await advanceSlicer(tester, 10);
    expect(find.byKey(const ValueKey('garden-damage-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-plant-0')), findsNothing);
    expect(slicerLives(2), findsOneWidget);
    expect(find.text('Plant eaten!'), findsWidgets);
    expect(find.byKey(const ValueKey('garden-plant-1')), findsOneWidget);
    await advanceSlicer(tester, 13);
    expect(find.byKey(const ValueKey('garden-damage-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-plant-2')), findsOneWidget);
    expect(slicerLives(1), findsOneWidget);
    await advanceSlicer(tester, 51);
    expect(find.text('Wave 2'), findsOneWidget);
    final next = warningsPainter(tester).warnings;
    expect(next, hasLength(1));
    expect(next.single.flower.dx, 323);
  });

  testWidgets('Ice stalls a bite and Water saves the flower', (tester) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    await advanceSlicer(tester, 110);
    final bite = find.byKey(const ValueKey('garden-bite-0'));
    final flower = find.byKey(const ValueKey('garden-plant-0'));
    final thorn = find.byKey(const ValueKey('target-1'));
    final beforeIce = warningsPainter(tester).warnings;
    final biteFrame = plantPainter(tester, thorn).pose.chewFrame;
    expect(biteFrame, isNotNull);
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.firstCut);
    await tester.tap(find.text('Ice x1'));
    await advanceSlicer(tester, 44);
    expect(warningsPainter(tester).frozen, isTrue);
    expect(warningsPainter(tester).warnings, beforeIce);
    expect(plantPainter(tester, thorn).pose.chewFrame, biteFrame);
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.firstCut);
    expect(bite, findsOneWidget);
    expect(flower, findsOneWidget);
    expect(slicerLives(3), findsOneWidget);

    await tester.tap(find.text('Water x1'));
    await tester.pump();
    final swept = find.byKey(const ValueKey('water-target-1'));
    expect(plantPainter(tester, swept).pose.chewFrame, biteFrame);
    await advanceSlicer(tester, 10);
    expect(find.text('Saved +12'), findsNWidgets(2));
    await advanceSlicer(tester, 14);
    expect(bite, findsNothing);
    expect(flower, findsOneWidget);
    expect(slicerLives(3), findsOneWidget);
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.firstCut);

    // Bramble comes for the same damaged flower in the next wave.
    for (
      var i = 0;
      i < 190 && cropPainter(tester, 0).damage == PlanterCrop.bell.firstCut;
      i++
    ) {
      await advanceSlicer(tester, 1);
    }
    expect(cropPainter(tester, 0).damage, closeTo(.6279, .0001));
  });

  testWidgets('a finishing slice during the bite earns a rescue bonus', (
    tester,
  ) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    final weed = find.byKey(const ValueKey('target-1'));
    await advanceSlicer(tester, 110);
    await tester.tapAt(tester.getCenter(weed));
    await advanceSlicer(tester, 5);
    expect(find.byKey(const ValueKey('garden-bite-0')), findsOneWidget);
    await tester.tapAt(tester.getCenter(weed));
    await tester.pump();
    expect(weed, findsNothing);
    expect(find.byKey(const ValueKey('garden-bite-0')), findsNothing);
    expect(find.byKey(const ValueKey('garden-bite-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-plant-0')), findsOneWidget);
    expect(cropPainter(tester, 0).damage, PlanterCrop.bell.firstCut);
    expect(find.text('Saved +12'), findsOneWidget);
  });

  testWidgets('ice power visibly freezes active weeds', (tester) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('Ice x1'), findsOneWidget);

    await tester.tap(find.text('Ice x1'));
    await tester.pump();

    final weed = find.byKey(const ValueKey('target-1'));
    expect(find.text('Freeze!'), findsOneWidget);
    expect(find.text('Ice 5s x0'), findsOneWidget);
    expect(plantPainter(tester, weed).frozen, isTrue);
    expect(find.byKey(const ValueKey('slicer-effects')), findsOneWidget);

    await advanceSlicer(tester, 10);
    expect(plantPainter(tester, weed).frost, 1);
    await tester.tapAt(tester.getCenter(weed) + const Offset(0, 18));
    await advanceSlicer(tester, 5);
    expect(plantPainter(tester, weed).cuts, 1);
    await tester.tapAt(tester.getCenter(weed) + const Offset(0, 18));
    await tester.pump();

    expect(weed, findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is SlicerCutFramePainter &&
            (widget.painter! as SlicerCutFramePainter).frozen,
      ),
      findsNWidgets(2),
    );
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
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('target-1'))),
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('target-2'))),
    );
    await tester.pump();
    expect(find.text('Avoid flowers!'), findsOneWidget);
  });

  testWidgets('a partial Bramble hit keeps the damaged plant in play', (
    tester,
  ) async {
    await pumpGardenNinja(tester);
    await tester.tap(find.text('Tutorial'));
    await tester.pump(const Duration(milliseconds: 64));

    Future<void> cut(int id) async {
      final target = find.byKey(ValueKey('target-$id'));
      await tester.tapAt(tester.getCenter(target));
      await advanceSlicer(tester, 5);
    }

    await cut(1);
    await cut(3);
    await cut(4);
    await cut(4);
    await cut(4);
    await advanceSlicer(tester, 5);

    final bramble = find.byKey(const ValueKey('target-6'));
    expect(plantPainter(tester, bramble).sprite.kind, SlicerPlantKind.bramble);
    expect(plantPainter(tester, bramble).cuts, 2);
    await cut(6);
    expect(plantPainter(tester, bramble).cuts, 1);
    expect(find.byKey(const ValueKey('slicer-effects')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ClipPath && widget.clipper is SliceHalfClipper,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'the first run funds a Rain Barrel that supplies two Water casts in the next run',
    (tester) async {
      await pumpGardenNinja(
        tester,
        prefs: {
          'garden_ninja_garden_v4': jsonEncode({'version': 9, 'seeds': 0}),
        },
      );

      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 64));
      expect(find.text('Water x1'), findsOneWidget);

      final build = find.byKey(const ValueKey('build-slicer-rain-barrel'));
      for (var i = 0; i < 80 && build.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Garden overrun'), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);
      expect(find.text('+24'), findsOneWidget);
      await tester.tap(build);
      await tester.pump();
      expect(find.text('Equipped · Water x2 next run'), findsOneWidget);
      expect(build, findsNothing);
      final prefs = await SharedPreferences.getInstance();
      Map saved() =>
          jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved()['seeds'], 0);
      expect(saved()['slicerRainBarrelBuilt'], isTrue);
      expect(saved()['slicerStarterSeedsGranted'], isTrue);

      await tester.tap(find.byKey(const ValueKey('primary-PLAY NEXT RUN')));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Water x2'), findsOneWidget);
      expect(cropPainter(tester, 0).damage, 0);
      expect(cropPainter(tester, 1).damage, 0);
      expect(cropPainter(tester, 2).damage, 0);
      await tester.tap(find.text('Water x2'));
      await advanceSlicer(tester, 80);
      expect(find.text('Wave 2'), findsOneWidget);
      expect(find.text('Water x1'), findsOneWidget);
      await tester.tap(find.text('Water x1'));
      await advanceSlicer(tester, 24);
      expect(find.text('Water x0'), findsOneWidget);
      expect(slicerTargets(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const GardenNinjaApp());
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved()['waterCharges'], 0);
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Water x2'), findsOneWidget);
      expect(find.text('Ice x1'), findsOneWidget);
    },
  );

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

  testWidgets(
    'avatar, audio preferences, and purchased ice survive use and restart',
    (tester) async {
      await pumpGardenNinja(
        tester,
        prefs: {
          'garden_ninja_garden_v4': jsonEncode({
            'version': 8,
            'seeds': 500,
            'iceCharges': 2,
            'selectedAvatar': 1,
            'selectedMusicTrack': 2,
            'musicEnabled': false,
            'sfxEnabled': false,
          }),
        },
      );
      final prefs = await SharedPreferences.getInstance();
      var saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['version'], 9);
      expect(saved['selectedAvatar'], 1);
      expect(saved['selectedMusicTrack'], 2);
      expect(saved['musicEnabled'], isFalse);
      expect(saved['sfxEnabled'], isFalse);
      expect(saved['iceCharges'], 2);

      await tester.tap(find.byKey(const ValueKey('home-menu-Shop')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Male Ninja'));
      await tester.pump();
      await tester.tap(find.text('Female Ninja'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.music_off_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.music_note_rounded));
      await tester.pump();
      await tester.tap(find.text('Weed Invasion'));
      await tester.pump();
      await tester.ensureVisible(find.text('Garden Groove'));
      await tester.pump();
      await tester.tap(find.text('Garden Groove'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.volume_off_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
      await tester.pump();
      saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['selectedAvatar'], 1);
      expect(saved['selectedMusicTrack'], 2);
      expect(saved['musicEnabled'], isFalse);
      expect(saved['sfxEnabled'], isFalse);

      await tester.ensureVisible(find.text('Frost Vine'));
      await tester.pump();
      await tester.tap(find.text('Frost Vine'));
      await tester.pump(const Duration(milliseconds: 100));
      saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['seeds'], 360);
      expect(saved['iceCharges'], 3);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Ice x1'), findsOneWidget);
      expect(find.text('3 reserve'), findsOneWidget);
      await tester.tap(find.text('Ice x1'));
      await advanceSlicer(tester, 86);
      saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['iceCharges'], 3);
      expect(find.text('Ice x3'), findsOneWidget);
      await tester.tap(find.text('Ice x3'));
      await tester.pump(const Duration(milliseconds: 100));
      saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['iceCharges'], 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(const GardenNinjaApp());
      await tester.pump(const Duration(milliseconds: 100));
      saved = jsonDecode(prefs.getString('garden_ninja_garden_v4')!) as Map;
      expect(saved['selectedAvatar'], 1);
      expect(saved['selectedMusicTrack'], 2);
      expect(saved['musicEnabled'], isFalse);
      expect(saved['sfxEnabled'], isFalse);
      expect(saved['iceCharges'], 2);
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Ice x1'), findsOneWidget);
      expect(find.text('2 reserve'), findsOneWidget);
      expect(find.text('Ice x3'), findsNothing);
    },
  );

  testWidgets(
    'clearing repeated waves leaves the full minute to defend the planters',
    (tester) async {
      await pumpGardenNinja(tester);
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 236; i++) {
        final keys = slicerTargets()
            .evaluate()
            .map((element) => element.widget.key!)
            .toList();
        for (final key in keys) {
          final target = find.byKey(key);
          if (target.evaluate().isNotEmpty) {
            await tester.tapAt(tester.getCenter(target));
          }
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Perfect rescue'), findsNothing);
      expect(find.text('0:01'), findsOneWidget);
      expect(slicerLives(3), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 920));
      expect(find.text('Perfect rescue'), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('NEXT LEVEL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('primary-NEXT LEVEL')));
      await tester.pump();
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('Wave 1'), findsOneWidget);
    },
  );

  testWidgets('Rate App opens the platform Play listing action', (
    tester,
  ) async {
    const channel = MethodChannel('garden_ninja/play_review');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var opened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openStoreListing') {
        opened = true;
        return true;
      }
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await pumpGardenNinja(tester);
    await tester.tap(find.byKey(const ValueKey('rate-app')));
    await tester.pump();
    expect(opened, isTrue);
  });
}
