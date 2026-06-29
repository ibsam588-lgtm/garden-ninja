import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';

Future<void> pumpGardenNinja(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const GardenNinjaApp());
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
    expect(find.text('-150 Plant'), findsOneWidget);
    expect(find.text('Garden Saved'), findsNothing);
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

    expect(find.textContaining('MY GARDEN'), findsOneWidget);
    expect(find.text('Pick a plant, tap an empty plot'), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-plant-option-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('garden-tool-clear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-tool-clear')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-8')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('+18 seeds, tap plot to plant'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garden-tool-plant')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('garden-plant-option-2')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Pink Bloom planted: +150 pts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Watered Pink Bloom'), findsOneWidget);
  });

  testWidgets('garden plants harvest into points and weeds stay capped', (
    tester,
  ) async {
    await pumpGardenNinja(tester);

    await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Weed!'), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 90));
    expect(find.text('Weed!'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('garden-plant-option-0')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 120));

    for (var i = 0; i < 3; i += 1) {
      await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('Daisy ready: +80 pts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-garden-plot-4')));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('+80 pts, +46 seeds'), findsOneWidget);
  });
}
