import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/garden/harvest_art.dart';
import 'package:garden_ninja/src/garden/harvest_garden.dart';
import 'package:garden_ninja/src/garden/harvest_model.dart';

const capture = bool.fromEnvironment('GARDEN_CAPTURE');
final boundary = GlobalKey();

Future<void> pumpGarden(
  WidgetTester tester,
  HarvestProgress progress, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => HarvestArt.load());
  if (capture && Platform.isWindows) {
    await tester.runAsync(() async {
      final text = FontLoader('Arial')
        ..addFont(
          File(
            'C:/Windows/Fonts/arial.ttf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([text.load(), icons.load()]);
    });
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Arial'),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: HarvestGarden(
              progress: progress,
              onExit: () {},
              onSave: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!capture) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('build/harvest-preview')
      ..createSync(recursive: true);
    File(
      '${output.path}/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'twelve physical taps pay the order and accessible taps remain available',
    (tester) async {
      final progress = HarvestProgress();
      await pumpGarden(tester, progress);
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.byKey(const ValueKey('harvest-start')));
        await tester.pump(const Duration(seconds: 8));
        for (var i = 0; i < 12; i++) {
          await tester.tapAt(
            tester.getCenter(find.byKey(ValueKey('harvest-crop-$i'))),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(progress.coins, 1020);
        expect(progress.totalOrders, 1);
        final node = tester.getSemantics(
          find.byKey(const ValueKey('harvest-crop-15')),
        );
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node.id,
          ui.SemanticsAction.tap,
        );
        await tester.pump();
        expect(find.text('Tomatoes  1/12'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(seconds: 90));
        expect(find.text('Harvest paused'), findsOneWidget);
        expect(find.text('HARVEST COMPLETE'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.text('Harvest paused'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets('real swipes gather crops on release, with a cancellable pause', (
    tester,
  ) async {
    final progress = HarvestProgress();
    await pumpGarden(tester, progress);
    await screenshot(tester, '01-garden');
    await tester.tap(find.byKey(const ValueKey('harvest-start')));
    await tester.pump(const Duration(seconds: 8));
    final first = tester.getCenter(
      find.byKey(const ValueKey('harvest-crop-0')),
    );
    final second = tester.getCenter(
      find.byKey(const ValueKey('harvest-crop-1')),
    );
    final gesture = await tester.startGesture(first);
    await tester.pump();
    await gesture.moveTo(second);
    await tester.pump();
    expect(find.text('2 CHAIN'), findsOneWidget);
    expect(find.text('Strawberries  0/12'), findsOneWidget);
    await screenshot(tester, '02-harvest');
    await gesture.up();
    await tester.pump();
    expect(find.text('Strawberries  2/12'), findsOneWidget);
    expect(progress.bestChain, 2);
    await tester.tap(find.byKey(const ValueKey('harvest-pause')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 70));
    expect(find.text('Harvest paused'), findsOneWidget);
    expect(find.text('00:52'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('harvest-resume')));
    await tester.pump(const Duration(seconds: 53));
    expect(find.text('HARVEST COMPLETE'), findsOneWidget);
    expect(find.text('Choose your next upgrade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planting, upgrade cards and next-tier requirements are usable', (
    tester,
  ) async {
    final progress = HarvestProgress(coins: 1020);
    await pumpGarden(tester, progress);
    await tester.tap(find.byKey(const ValueKey('harvest-build')));
    await tester.pump();
    await screenshot(tester, '03-upgrades');
    await tester.tap(find.byKey(const ValueKey('harvest-buy-upgrade')));
    await tester.pump();
    expect(progress.coins, 120);
    expect(progress.greenhouse, 1);
    await screenshot(tester, '04-greenhouse-built');
    await tester.tap(find.byKey(const ValueKey('harvest-plant')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('harvest-plant-blueberry')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('harvest-plant-confirm')));
    await tester.pump();
    expect(progress.crops.first, CropKind.blueberry);
    await tester.tap(find.byKey(const ValueKey('harvest-progress')));
    await tester.pump();
    await screenshot(tester, '05-progression');
    expect(find.text('Finish the upgrades above'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'advancing a completed garden resets beds and opens the new tier',
    (tester) async {
      final progress = HarvestProgress(coins: 5000)
        ..greenhouse = 1
        ..terrace = 1
        ..tierOrders = 3;
      for (var i = 0; i < 4; i++) {
        progress.beds[i] = 2;
      }
      await pumpGarden(tester, progress);
      await tester.tap(find.byKey(const ValueKey('harvest-progress')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('harvest-advance-tier')));
      await tester.pump();
      expect(find.text('GARDEN 2'), findsOneWidget);
      expect(progress.tier, 2);
      expect(progress.greenhouse, 1);
      expect(progress.beds, everyElement(1));
      await screenshot(tester, '06-new-garden');
      await tester.tap(find.byKey(const ValueKey('harvest-new-tier-plant')));
      await tester.pump();
      expect(find.text('Plant your garden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact phone and enlarged text keep controls reachable', (
    tester,
  ) async {
    await pumpGarden(
      tester,
      HarvestProgress(coins: 2000),
      size: const Size(320, 640),
      textScale: 1.4,
    );
    for (final key in ['harvest-build', 'harvest-plant', 'harvest-progress']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('harvest-sheet-close')));
      await tester.pump();
    }
    await screenshot(tester, '07-compact');
  });
}
