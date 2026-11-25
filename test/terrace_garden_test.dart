import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/garden/terrace_garden.dart';
import 'package:garden_ninja/src/garden/terrace_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all 1,104 positions can reach one spill-free route per terrace', () {
    var boards = 0;
    for (final stage in terraceStages.take(3)) {
      final movable = [
        for (final (i, tile) in stage.tiles.indexed)
          if (!tile.fixed) i,
      ];
      final signatures = <String>{};
      for (var code = 0; code < 1 << (movable.length * 2); code++) {
        boards++;
        final turns = stage.startingTurns;
        for (final (j, cell) in movable.indexed) {
          turns[cell] = (code >> (2 * j)) & 3;
        }
        final result = traceTerrace(stage, turns);
        if (result.solved) {
          expect(result.spills, isEmpty);
          expect(result.fed, [for (final goal in stage.goals) goal.row]);
          expect(
            result.wet.length,
            stage.tiles.where((t) => t.shape != TerraceShape.land).length,
          );
          signatures.add(
            [
              for (final cell in movable)
                terracePorts(stage.tiles[cell].shape, turns[cell]).join(),
            ].join('/'),
          );
        }
        var count = 0;
        for (
          var cell = terraceHint(stage, turns);
          cell != null;
          cell = terraceHint(stage, turns)
        ) {
          turns[cell] = (turns[cell] + 1) % 4;
          expect(++count, lessThanOrEqualTo(3 * movable.length));
        }
        expect(traceTerrace(stage, turns).solved, isTrue);
      }
      expect(signatures.length, 1);
    }
    expect(boards, 1104);
    final firstFlow = traceTerrace(
      terraceStages.first,
      terraceStages.first.startingTurns,
    );
    expect(firstFlow.spills.single.cell, 5);
    expect(firstFlow.spills.single.dir, 2);
    expect(traceTerrace(terraceStages[1], terraceStages[1].startingTurns).fed, [
      2,
    ]);
  });

  test(
    'loading respects locked stages, fixed pieces and valid solved flags',
    () {
      final progress = TerraceProgress.fromJson({
        'v': 1,
        'stage': 99,
        'cleared': [true, false, true],
        'finished': [true, false, true],
        'boards': [
          [4, 3, 2, 2, 2, 3],
          null,
          [],
        ],
        'moves': [-7],
        'best': [4],
      });
      expect(progress.stageIndex, 1);
      expect(progress.cleared.take(3), [true, false, false]);
      expect(progress.finished.first, isFalse);
      expect(progress.boards[0][4], terraceStages[0].tiles[4].turn);
      expect(progress.moves.first, 0);
      expect(progress.best.first, 4);
    },
  );

  testWidgets(
    'a spill can be retried, a restored win opens the next terrace, and replay keeps best',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 680);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final release = find.byKey(const ValueKey('terrace-release'));
      final hint = find.byKey(const ValueKey('terrace-hint'));
      Finder cell(int i) => find.byKey(ValueKey('terrace-cell-$i'));
      Future<void> showGarden() async {
        await tester.pumpWidget(const MaterialApp(home: TerraceGardenScreen()));
        await tester.pump();
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await showGarden();
      expect(tester.getSize(cell(5)).shortestSide, greaterThanOrEqualTo(44));
      await tap(release);
      expect(
        find.textContaining('Water spills at row 2, column 2'),
        findsOneWidget,
      );
      await tap(hint);
      expect(
        find.textContaining('Turn the highlighted channel in row 2, column 2'),
        findsOneWidget,
      );
      expect(find.text('0 turns'), findsOneWidget);
      await tap(cell(5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await showGarden();
      expect(find.text('1 turn'), findsOneWidget);
      await tap(cell(2));
      await tap(release);
      expect(find.text('Next terrace'), findsOneWidget);
      expect(find.text('2 turns · Best 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await showGarden();
      expect(find.text('Next terrace'), findsOneWidget);
      await tap(release);
      expect(find.text('Twin Terraces'), findsOneWidget);
      tester.view.physicalSize = const Size(740, 320);
      await tester.pumpAndSettle();
      expect(tester.getSize(cell(5)).shortestSide, greaterThanOrEqualTo(44));
      await tap(find.byKey(const ValueKey('terrace-levels')));
      await tap(find.byKey(const ValueKey('terrace-stage-0')));
      await tap(hint);
      expect(find.text('0 turns · Best 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'only active puzzle time counts; an expired level restores and retries',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final completed = <bool>[];
      final release = find.byKey(const ValueKey('terrace-release'));
      final levels = find.byKey(const ValueKey('terrace-levels'));
      final clock = find.byKey(const ValueKey('terrace-clock'));
      String time() => tester.widget<Text>(clock).data!;
      String asTime(int seconds) =>
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      final seconds = terraceStages.first.timeLimitSeconds;
      Future<void> mount({bool suspended = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TerraceGardenScreen(
              suspended: suspended,
              onRoundCompleted: completed.add,
            ),
          ),
        );
        await tester.pump();
      }

      await mount();
      expect(time(), asTime(seconds));
      await tester.pump(const Duration(seconds: 2));
      expect(time(), asTime(seconds - 2));
      await tester.tap(levels);
      await tester.pumpAndSettle();
      expect(find.text('Levels 1–10'), findsOneWidget);
      await tester.tap(find.byTooltip('Next ten levels'));
      await tester.pump();
      expect(find.text('Levels 11–20'), findsOneWidget);
      final locked = tester.widget<FilledButton>(
        find.byKey(const ValueKey('terrace-stage-10')),
      );
      expect(locked.onPressed, isNull);
      await tester.pump(const Duration(seconds: 7));
      await tester.tap(find.byTooltip('Close levels'));
      await tester.pumpAndSettle();
      expect(time(), asTime(seconds - 2));

      await mount(suspended: true);
      await tester.pump(const Duration(seconds: 12));
      expect(time(), asTime(seconds - 2));
      await mount();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 9));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(time(), asTime(seconds - 4));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      await mount();
      expect(time(), asTime(seconds - 4));
      await tester.pump(Duration(seconds: seconds));
      expect(time(), '0:00');
      expect(find.text('Time’s up'), findsOneWidget);
      expect(completed, [false]);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('terrace-cell-5')))
            .onTap,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(find.text('Retry level'), findsOneWidget);
      expect(completed, [false]);
      await tester.tap(release);
      await tester.pump();
      expect(time(), asTime(seconds));
      expect(find.text('0 turns'), findsOneWidget);
      // A winning release before zero gets the full water animation.
      for (final cell in [5, 2]) {
        await tester.tap(find.byKey(ValueKey('terrace-cell-$cell')));
        await tester.pump();
      }
      await tester.pump(Duration(seconds: seconds - 1));
      expect(time(), '0:01');
      await tester.tap(release);
      await tester.pumpAndSettle();
      expect(find.text('Next terrace'), findsOneWidget);
      expect(completed, [false, true]);
      await tester.pump(Duration(seconds: seconds));
      expect(time(), '0:01');
      expect(completed, [false, true]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
