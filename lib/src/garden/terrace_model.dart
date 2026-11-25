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
    this.timeLimitSeconds,
  );
  final String name;
  final String subtitle;
  final int sourceRow;
  final List<TerraceGoal> goals;
  final List<TerraceTile> tiles;
  final List<int> solution;
  final int timeLimitSeconds;
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
  int level,
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
    101 - level,
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
    1,
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
    2,
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
    3,
  ),
  for (final (index, route) in _campaignRoutes.indexed)
    _routedStage(index + 4, route),
]);

// Row-major diagrams describe the complete water route. Each digit records the
// clockwise taps needed from the starting position; zero denotes a fixed tile.
typedef _Route = (String name, String diagram, String taps);

TerraceStage _routedStage(int level, _Route route) {
  final (name, diagram, taps) = route;
  const channels = {
    '│': (_straight, 0),
    '─': (_straight, 1),
    '└': (_elbow, 0),
    '┌': (_elbow, 1),
    '┐': (_elbow, 2),
    '┘': (_elbow, 3),
    '├': (_tee, 0),
    '┬': (_tee, 1),
    '┤': (_tee, 2),
    '┴': (_tee, 3),
  };
  const flowers = [
    ('bell', 'Bluebell'),
    ('daisy', 'Daisy'),
    ('blossom', 'Blossom'),
  ];
  final cells = diagram.replaceAll('/', '');
  final pieces = <(int, TerraceShape, int, int?)>[];
  final goals = <TerraceGoal>[];
  late int sourceRow;
  for (var i = 0; i < cells.length; i++) {
    if (cells[i] == '.') continue;
    final (shape, correct) = channels[cells[i]]!;
    final steps = int.parse(taps[i]);
    pieces.add((i, shape, correct, steps == 0 ? null : (correct - steps) % 4));
    final ports = terracePorts(shape, correct);
    if (i % 4 == 0 && ports.contains(3)) sourceRow = i ~/ 4;
    if (i % 4 == 3 && ports.contains(1)) {
      final (crop, flower) = flowers[(level + goals.length) % flowers.length];
      goals.add(TerraceGoal(i ~/ 4, crop, flower));
    }
  }
  return _stage(
    name,
    'Bring water to all ${goals.length} flower beds.',
    sourceRow,
    goals,
    pieces,
    level,
  );
}

// Keep each entry in place: the level index and starting turns are used by saved games.
const List<_Route> _campaignRoutes = [
  ('Fern Hollow', '┌─┐┌/│.└┘/┴───', '002300000110'),
  ('Willow Steps', '.┌┐┌/─┘└┤/...└', '021013000000'),
  ('Reed Crossing', '─┬──/┌┘../└───', '100032000001'),
  ('Pebble Run', '┐.┌─/└─┴─/....', '200101300000'),
  ('Cress Brook', '...┌/┌┐.├/┘└─┘', '000101003012'),
  ('Mossy Bank', '─┐.┌/.│.├/.└─┘', '020000020211'),
  ('Foxglove Rise', '┌┐.┌/│└─┤/┘..└', '030211010000'),
  ('Thyme Walk', '..../┐┌──/└┴──', '000003100211'),
  ('Clover Brook', '.┌──/┐├──/└┘..', '031100100300'),
  ('Sage Turn', '┌──┬/┘.┌┘/..└─', '101100030030'),
  ('Mint Channel', '┐.┌┬/│┌┘└/└┘..', '202002210000'),
  ('Hazel Shelf', '┐..┌/└┐.│/.└─┴', '200013010101'),
  ('Poppy Field', '──┐┌/┌─┘│/└──┴', '010311200002'),
  ('Alder Spring', '┐..┌/│.┌┘/└─┴─', '300200020111'),
  ('Iris Vale', '┌──┐/┴─┐└/..└─', '010031120020'),
  ('Jasmine Path', '┐.┌─/└┐│./.└┴─', '202122100000'),
  ('Juniper Bank', '..┌─/──┤┌/..└┘', '003011100023'),
  ('Cedar Fork', '.┌──/┌┘.┌/┴──┘', '001120030103'),
  ('Primrose Steps', '.┌──/┬┘┌─/└─┘.', '011103013100'),
  ('Olive Terrace', '..┌─/┐┌┘./└┴──', '000132102101'),
  ('Honeycomb Hill', '┌─┐./│.│┌/┘.└┴', '001010132022'),
  ('Lavender Fork', '.┌┬─/┌┘└┬/┘..└', '032110021002'),
  ('Heather Hollow', '─┐┌─/.└┤┌/..└┴', '131101030002'),
  ('Lupine Ridge', '┐..┌/└┬─┴/.└──', '200310020211'),
  ('Crocus Bridge', '┌┐┌─/│└┴┬/┘..└', '010110322003'),
  ('Marigold Maze', '──┬─/.┌┘┌/.└─┴', '110102310013'),
  ('Sorrel Steps', '.┌──/.├┬─/─┘└─', '031101201310'),
  ('Cypress Bend', '┌──┬/└─┐└/──┴─', '011020331101'),
  ('Rosemary Rise', '.┌┐┌/┬┘└┴/└───', '000313022111'),
  ('Peony Walk', '─┐┌┬/.││└/.└┴─', '133101120020'),
  ('Lotus Banks', '.┌─┬/┌┘┌┴/┘.└─', '001233211001'),
  ('Camellia Weir', '┐.┌─/│┌┘┌/└┴─┴', '301102032110'),
  ('Maple Stair', '┌┬─┬/┘│.└/.└──', '221201030211'),
  ('Saffron Reach', '┬───/│┌┐┌/└┘└┴', '201112200132'),
  ('Thistle Gorge', '.┌┬┬/┌┘│└/┘.└─', '032021122011'),
  ('Lily Cascade', '..┌─/┌─┘┌/┴──┴', '003121122012'),
  ('Honeysuckle Bend', '┌───/│┌┐┌/┴┘└┴', '201110022331'),
  ('Chestnut Rise', '─┐┌┬/┌┴┘└/└───', '112032230011'),
  ('Violet Quarry', '.┌──/┬┘┌─/└─┴─', '001122213130'),
  ('Birch Aqueduct', '┌┐┌─/│││┌/┘└┴┴', '220111103221'),
  ('Buttercup Cliffs', '┌───/┤.┌─/└─┴─', '311100213131'),
  ('Magnolia Weir', '─┐┌─/┌┴┴─/└───', '122033211110'),
  ('Anemone Stair', '┌┐.┌/│├─┴/┘└──', '320112022211'),
  ('Wisteria Crossing', '┬───/└┐┌─/.└┴─', '111133210301'),
  ('Elmstone Valley', '┬───/└┐┌┬/.└┘└', '311021230221'),
  ('Sweet Pea Ridge', '┌┬──/│├──/┘└──', '231013113201'),
  ('Clematis Hollow', '─┐┌─/┌┘└┬/└──┴', '122110223112'),
  ('Sundew Basin', '─┐.┌/┌┘┌┴/└─┴─', '130113123111'),
  ('Laurel Locks', '.┌┐┌/┌┘└┴/┴───', '023321113111'),
  ('Dahlia Gorge', '.┌┬─/┌┤└─/┘└──', '031123312111'),
  ('Hyacinth Valley', '┌─┬─/│.└─/┴───', '313110313111'),
  ('Pinecrest Weir', '┌───/┤┌┐┌/└┘└┴', '111110331223'),
  ('Verbena Ridge', '┐.┌─/├─┴─/└───', '303131213111'),
  ('Orchid Falls', '.┌┬─/┐││┌/└┘└┴', '021121133222'),
  ('Moonflower Steps', '┌┬┐┌/┘│└┴/.└──', '311321320211'),
  ('Summit Springs', '┌┬──/┘├──/.└──', '331123110311'),
  ('Crown of the Garden', '.┌┐┌/┌┤└┴/┘└──', '022123233111'),
];

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
  final remainingMs = [
    for (final stage in terraceStages) stage.timeLimitSeconds * 1000,
  ];

  int get unlocked =>
      math.min(terraceStages.length - 1, cleared.takeWhile((v) => v).length);
  TerraceStage get stage => terraceStages[stageIndex];
  List<int> get turns => boards[stageIndex];
  void rotate(int cell) {
    if (stage.tiles[cell].fixed ||
        finished[stageIndex] ||
        remainingMs[stageIndex] == 0) {
      return;
    }
    turns[cell] = (turns[cell] + 1) % 4;
    moves[stageIndex] = math.min(9999, moves[stageIndex] + 1);
  }

  void clear() {
    if (remainingMs[stageIndex] == 0 || !traceTerrace(stage, turns).solved) {
      return;
    }
    cleared[stageIndex] = finished[stageIndex] = true;
    best[stageIndex] = math.min(best[stageIndex] ?? 9999, moves[stageIndex]);
  }

  void replay() {
    boards[stageIndex] = stage.startingTurns;
    finished[stageIndex] = false;
    moves[stageIndex] = 0;
    remainingMs[stageIndex] = stage.timeLimitSeconds * 1000;
  }

  Map<String, Object> toJson() => {
    'v': 2,
    'stage': stageIndex,
    'cleared': cleared,
    'finished': finished,
    'best': best,
    'moves': moves,
    'boards': boards,
    'remainingMs': remainingMs,
  };
  TerraceProgress();
  factory TerraceProgress.fromJson(Object? raw) {
    final result = TerraceProgress();
    if (raw is! Map || (raw['v'] != 1 && raw['v'] != 2)) return result;
    Object? at(Object? list, int i) =>
        list is List && list.length > i ? list[i] : null;
    for (final (i, stage) in terraceStages.indexed) {
      // The original release stored just the first three, untimed levels.
      if (raw['v'] == 1 && i == 3) break;
      if (i > 0 && !result.cleared[i - 1]) break;
      result.cleared[i] = at(raw['cleared'], i) == true;
      final moves = at(raw['moves'], i), best = at(raw['best'], i);
      if (moves is int) result.moves[i] = moves.clamp(0, 9999);
      final remaining = at(raw['remainingMs'], i);
      if (raw['v'] == 2 && remaining is int) {
        result.remainingMs[i] = remaining.clamp(
          0,
          stage.timeLimitSeconds * 1000,
        );
      }
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
