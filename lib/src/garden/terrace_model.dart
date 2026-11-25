import 'dart:math' as math;

enum TerraceShape { straight, elbow, tee, land }

class TerraceTile {
  const TerraceTile(this.shape, this.turn, {required this.fixed});
  final TerraceShape shape;
  final int turn;
  final bool fixed;
}

class TerraceGoal {
  const TerraceGoal(this.row, this.crop, this.name);
  final int row;
  final String crop;
  final String name;
}

class TerraceStage {
  TerraceStage._(
    this.name,
    this.subtitle,
    this.sourceRow,
    this.goals,
    this.tiles,
    this.solution,
  );
  final String name;
  final String subtitle;
  final int sourceRow;
  final List<TerraceGoal> goals;
  final List<TerraceTile> tiles;
  final List<int> solution;
  List<int> get startingTurns => [for (final tile in tiles) tile.turn];
}

// A channel has a cell, shape, solved turn and optional starting turn.
// Built-in channels stay fixed; brass channels have a starting turn.
TerraceStage _stage(
  String name,
  String subtitle,
  int sourceRow,
  List<TerraceGoal> goals,
  List<(int, TerraceShape, int, int?)> channels,
) {
  final tiles = List.filled(
    12,
    const TerraceTile(TerraceShape.land, 0, fixed: true),
  );
  final solution = List.filled(12, 0);
  for (final (cell, shape, correct, start) in channels) {
    tiles[cell] = TerraceTile(shape, start ?? correct, fixed: start == null);
    solution[cell] = correct;
  }
  return TerraceStage._(
    name,
    subtitle,
    sourceRow,
    List.unmodifiable(goals),
    List.unmodifiable(tiles),
    List.unmodifiable(solution),
  );
}

const _straight = TerraceShape.straight,
    _elbow = TerraceShape.elbow,
    _tee = TerraceShape.tee;
final terraceStages = List<TerraceStage>.unmodifiable([
  _stage(
    'Bluebell Bend',
    'Carry the spring around the bend to Bluebell.',
    1,
    [const TerraceGoal(0, 'bell', 'Bluebell')],
    [
      (4, _straight, 1, null),
      (5, _elbow, 3, 2),
      (1, _elbow, 1, null),
      (2, _straight, 1, 0),
      (3, _straight, 1, null),
    ],
  ),
  _stage(
    'Twin Terraces',
    'Keep Daisy watered and open a second branch to Bluebell.',
    1,
    [
      const TerraceGoal(0, 'bell', 'Bluebell'),
      const TerraceGoal(2, 'daisy', 'Daisy'),
    ],
    [
      (4, _straight, 1, null),
      (5, _tee, 2, 1),
      (1, _elbow, 1, 0),
      (2, _straight, 1, 0),
      (3, _straight, 1, null),
      (9, _elbow, 0, null),
      (10, _straight, 1, null),
      (11, _straight, 1, null),
    ],
  ),
  _stage(
    'Switchback Orchard',
    'Route the lower spring around the stone wall to both orchards.',
    2,
    [
      const TerraceGoal(0, 'daisy', 'Daisy'),
      const TerraceGoal(2, 'blossom', 'Blossom'),
    ],
    [
      (8, _elbow, 3, 2),
      (4, _straight, 0, null),
      (0, _elbow, 1, 0),
      (1, _straight, 1, null),
      (2, _tee, 1, 2),
      (3, _straight, 1, null),
      (6, _straight, 0, 1),
      (10, _elbow, 0, 3),
      (11, _straight, 1, null),
    ],
  ),
]);

/// Clockwise openings: north, east, south and west.
List<int> terracePorts(TerraceShape shape, int turn) {
  final base = switch (shape) {
    TerraceShape.straight => const [0, 2],
    TerraceShape.elbow => const [0, 1],
    TerraceShape.tee => const [0, 1, 2],
    TerraceShape.land => const <int>[],
  };
  return [for (final direction in base) (direction + turn) % 4]..sort();
}

class TerraceSpill {
  const TerraceSpill(this.cell, this.dir);
  final int cell;
  final int dir;
}

class TerraceFlow {
  const TerraceFlow(this.wet, this.depth, this.fed, this.spills, this.solved);
  final List<int> wet;
  final List<int> depth;
  final List<int> fed;
  final List<TerraceSpill> spills;
  final bool solved;
}

TerraceFlow traceTerrace(TerraceStage stage, List<int> turns) {
  final ports = [
    for (final (i, tile) in stage.tiles.indexed)
      terracePorts(tile.shape, tile.fixed ? tile.turn : turns[i]),
  ];
  final inlet = stage.sourceRow * 4;
  final goals = stage.goals.map((goal) => goal.row).toSet();
  final wet = <int>[],
      depth = List.filled(12, -1),
      fed = <int>{},
      spills = <TerraceSpill>[];
  if (ports[inlet].contains(3)) {
    wet.add(inlet);
    depth[inlet] = 0;
  } else {
    spills.add(TerraceSpill(inlet, 3));
  }
  const dy = [-1, 0, 1, 0], dx = [0, 1, 0, -1];
  for (var head = 0; head < wet.length; head++) {
    final cell = wet[head], row = cell ~/ 4, col = cell % 4;
    for (final dir in ports[cell]) {
      if (cell == inlet && dir == 3) continue;
      if (col == 3 && dir == 1 && goals.contains(row)) {
        fed.add(row);
        continue;
      }
      final r = row + dy[dir], c = col + dx[dir], next = r * 4 + c;
      if (r < 0 ||
          r >= 3 ||
          c < 0 ||
          c >= 4 ||
          !ports[next].contains((dir + 2) % 4)) {
        spills.add(TerraceSpill(cell, dir));
      } else if (depth[next] < 0) {
        wet.add(next);
        depth[next] = depth[cell] + 1;
      }
    }
  }
  return TerraceFlow(
    wet,
    depth,
    [
      for (final row in goals)
        if (fed.contains(row)) row,
    ],
    spills,
    fed.length == goals.length && spills.isEmpty,
  );
}

int? terraceHint(TerraceStage stage, List<int> turns) {
  if (traceTerrace(stage, turns).solved) return null;
  for (final i in traceTerrace(stage, stage.solution).wet) {
    final tile = stage.tiles[i];
    if (tile.fixed) continue;
    // A straight channel has the same openings after a half-turn.
    final period = tile.shape == TerraceShape.straight ? 2 : 4;
    if ((turns[i] - stage.solution[i]) % period != 0) return i;
  }
  return null;
}

class TerraceProgress {
  static const storageKey = 'terrace_garden_progress_v1';
  var stageIndex = 0;
  final cleared = List.filled(terraceStages.length, false);
  final finished = List.filled(terraceStages.length, false);
  final best = List<int?>.filled(terraceStages.length, null);
  final moves = List.filled(terraceStages.length, 0);
  final boards = [for (final stage in terraceStages) stage.startingTurns];

  int get unlocked =>
      math.min(terraceStages.length - 1, cleared.takeWhile((v) => v).length);
  TerraceStage get stage => terraceStages[stageIndex];
  List<int> get turns => boards[stageIndex];
  void rotate(int cell) {
    if (stage.tiles[cell].fixed || finished[stageIndex]) return;
    turns[cell] = (turns[cell] + 1) % 4;
    moves[stageIndex] = math.min(9999, moves[stageIndex] + 1);
  }

  void clear() {
    cleared[stageIndex] = finished[stageIndex] = true;
    best[stageIndex] = math.min(best[stageIndex] ?? 9999, moves[stageIndex]);
  }

  void replay() {
    boards[stageIndex] = stage.startingTurns;
    finished[stageIndex] = false;
    moves[stageIndex] = 0;
  }

  Map<String, Object> toJson() => {
    'v': 1,
    'stage': stageIndex,
    'cleared': cleared,
    'finished': finished,
    'best': best,
    'moves': moves,
    'boards': boards,
  };
  TerraceProgress();
  factory TerraceProgress.fromJson(Object? raw) {
    final result = TerraceProgress();
    if (raw is! Map || raw['v'] != 1) return result;
    Object? at(Object? list, int i) =>
        list is List && list.length > i ? list[i] : null;
    for (final (i, stage) in terraceStages.indexed) {
      if (i > 0 && !result.cleared[i - 1]) break;
      result.cleared[i] = at(raw['cleared'], i) == true;
      final moves = at(raw['moves'], i), best = at(raw['best'], i);
      if (moves is int) result.moves[i] = moves.clamp(0, 9999);
      if (best is int && result.cleared[i]) {
        result.best[i] = best.clamp(0, 9999);
      }
      for (final (j, tile) in stage.tiles.indexed) {
        final value = at(at(raw['boards'], i), j);
        if (!tile.fixed && value is int && value >= 0 && value < 4) {
          result.boards[i][j] = value;
        }
      }
      result.finished[i] =
          result.cleared[i] &&
          at(raw['finished'], i) == true &&
          traceTerrace(stage, result.boards[i]).solved;
    }
    final index = raw['stage'];
    if (index is int) result.stageIndex = index.clamp(0, result.unlocked);
    return result;
  }
}
