import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/garden/terrace_model.dart';

/// Search only the channels actually reached by water. A shortcut that left
/// an unused section dry would still be counted here if it fed every bed.
int? cheapestWateredRoute(TerraceStage stage) {
  final selected = List<int?>.filled(12, null);
  final inlet = stage.sourceRow * 4;
  final outlets = {for (final goal in stage.goals) goal.row * 4 + 3};
  int? best;

  void visit(List<(int, int)> pending, int taps) {
    if (best != null && taps >= best!) return;
    if (pending.isEmpty) {
      if (outlets.every((cell) => ((selected[cell] ?? 0) & 2) != 0)) {
        best = taps;
      }
      return;
    }
    final (cell, entry) = pending.last;
    final rest = pending.sublist(0, pending.length - 1);
    final existing = selected[cell];
    if (existing != null) {
      if (existing & (1 << entry) != 0) visit(rest, taps);
      return;
    }
    final tile = stage.tiles[cell];
    final rotations = tile.fixed
        ? 1
        : tile.shape == TerraceShape.straight
        ? 2
        : 4;
    for (var extra = 0; extra < rotations; extra++) {
      final ports = terracePorts(tile.shape, (tile.turn + extra) % 4);
      if (!ports.contains(entry)) continue;
      var leaks = false;
      final next = [...rest];
      for (final port in ports) {
        if (cell == inlet && port == 3 || outlets.contains(cell) && port == 1) {
          continue;
        }
        final x = cell % 4 + const [0, 1, 0, -1][port];
        final y = cell ~/ 4 + const [-1, 0, 1, 0][port];
        if (x < 0 || x >= 4 || y < 0 || y >= 3) {
          leaks = true;
          break;
        }
        next.add((y * 4 + x, (port + 2) % 4));
      }
      if (!leaks) {
        selected[cell] = ports.fold<int>(0, (mask, p) => mask | (1 << p));
        visit(next, taps + extra);
        selected[cell] = null;
      }
    }
  }

  visit([(inlet, 3)], 0);
  return best;
}

void main() {
  test('60 distinct routes have a steadily increasing minimum pace', () {
    expect(terraceStages.length, 60);
    expect(terraceStages.map((s) => s.name).toSet(), hasLength(60));
    final layouts = <String>{};
    var previousMoves = 0, previousSeconds = 101;
    for (final (index, stage) in terraceStages.indexed) {
      final description = 'Level ${index + 1}: ${stage.name}';
      final cells = [
        for (final (cell, tile) in stage.tiles.indexed)
          terracePorts(tile.shape, stage.solution[cell]).join(),
      ];
      expect(layouts.add(cells.join('|')), isTrue, reason: description);
      expect(traceTerrace(stage, stage.startingTurns).solved, isFalse);
      final optimal = cheapestWateredRoute(stage);
      expect(optimal, isNotNull, reason: description);
      final moves = optimal!;
      expect(moves, greaterThanOrEqualTo(previousMoves), reason: description);
      expect(
        stage.timeLimitSeconds,
        lessThan(previousSeconds),
        reason: description,
      );
      expect(
        moves / stage.timeLimitSeconds,
        greaterThan(previousMoves / previousSeconds),
      );

      final turns = stage.startingTurns;
      for (var tap = 0; tap < moves; tap++) {
        final hint = terraceHint(stage, turns);
        expect(hint, isNotNull, reason: description);
        turns[hint!] = (turns[hint] + 1) % 4;
      }
      final flow = traceTerrace(stage, turns);
      expect(flow.solved, isTrue, reason: description);
      expect(flow.fed.length, stage.goals.length);
      expect(
        flow.wet.length,
        stage.tiles.where((t) => t.shape != TerraceShape.land).length,
      );
      previousMoves = moves;
      previousSeconds = stage.timeLimitSeconds;
    }
    expect(previousMoves, 21);
    expect(previousSeconds, 41);
  });

  test('v1 saves retain their three boards and open level four', () {
    final legacy = TerraceProgress();
    for (var i = 0; i < 3; i++) {
      legacy.stageIndex = i;
      for (
        var cell = terraceHint(legacy.stage, legacy.turns);
        cell != null;
        cell = terraceHint(legacy.stage, legacy.turns)
      ) {
        legacy.rotate(cell);
      }
      legacy.clear();
    }
    final data = legacy.toJson();
    for (final key in ['cleared', 'finished', 'best', 'moves', 'boards']) {
      data[key] = (data[key]! as List).take(3).toList();
    }
    data.remove('remainingMs');
    data['v'] = 1;
    final restored = TerraceProgress.fromJson(data);
    expect(restored.unlocked, 3);
    expect(restored.stageIndex, 2);
    expect(restored.best.take(3), [2, 3, 7]);
    expect(restored.finished.take(4), [true, true, true, false]);
    expect(restored.turns, legacy.turns);
    expect(
      restored.remainingMs,
      terraceStages.map((s) => s.timeLimitSeconds * 1000),
    );
  });

  test('timer persists per attempt, and expired attempts require a retry', () {
    final progress = TerraceProgress();
    progress.rotate(5);
    progress.remainingMs.first = 0;
    final loaded = TerraceProgress.fromJson(progress.toJson());
    expect(loaded.moves.first, 1);
    expect(loaded.remainingMs.first, 0);
    loaded.rotate(5);
    loaded.clear();
    expect(loaded.unlocked, 0);
    expect(loaded.moves.first, 1);
    loaded.replay();
    expect(loaded.turns, loaded.stage.startingTurns);
    expect(loaded.moves.first, 0);
    expect(loaded.remainingMs.first, 100000);
    loaded.remainingMs.first = 83337;
    expect(TerraceProgress.fromJson(loaded.toJson()).remainingMs.first, 83337);
  });
}
