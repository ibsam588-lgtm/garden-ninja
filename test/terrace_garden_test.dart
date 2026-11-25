import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/garden/terrace_garden.dart';
import 'package:garden_ninja/src/garden/terrace_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all 1,104 positions can reach one spill-free route per terrace', () {
    var boards = 0;
    for (final stage in terraceStages) {
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
      expect(progress.cleared, [true, false, false]);
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
      await tap(find.byKey(const ValueKey('terrace-stage-0')));
      await tap(hint);
      expect(find.text('0 turns · Best 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
