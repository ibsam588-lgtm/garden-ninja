import 'dart:math';

import 'package:garden_ninja/src/slicer/slicer_plant_art.dart';

typedef PlanterAttack = ({
  SlicerPlantKind kind,
  int planter,
  double marchSeconds,
  double biteSeconds,
  int cuts,
});

abstract final class PlanterRescue {
  static const roundSeconds = 60.0;
  static const betweenWaves = 2.45;
  static const lastSpawnSeconds = 3.0;
  static const freezeSeconds = 4.2;
  static const rainBarrelCost = 24;
  static const firstRoundSeeds = 24;
  static const clearSeeds = 6;
  static const rescueSeeds = 12;

  static const _patterns = [
    (thorn: 0, bramble: 1, thornMarch: 4.85, brambleMarch: 4.95),
    (thorn: 2, bramble: 0, thornMarch: 4.35, brambleMarch: 5.20),
    (thorn: 1, bramble: 2, thornMarch: 4.72, brambleMarch: 4.85),
    (thorn: 0, bramble: 2, thornMarch: 4.20, brambleMarch: 4.70),
    (thorn: 2, bramble: 1, thornMarch: 3.95, brambleMarch: 4.50),
    (thorn: 1, bramble: 0, thornMarch: 4.05, brambleMarch: 4.32),
  ];

  static Iterable<PlanterAttack> wave({
    required int index,
    required int level,
    required Iterable<int> livePlanters,
  }) sync* {
    final remaining = livePlanters.toList();
    if (remaining.isEmpty) return;

    final pattern = _patterns[index % _patterns.length];
    final speedup =
        .17 * (index ~/ _patterns.length) + min(.75, .10 * (level - 1));
    final thornBed = remaining.remove(pattern.thorn)
        ? pattern.thorn
        : remaining.removeAt(0);
    yield (
      kind: SlicerPlantKind.thorn,
      planter: thornBed,
      marchSeconds: max(3.3, pattern.thornMarch - speedup),
      biteSeconds: 1.58,
      cuts: 2,
    );

    if (remaining.isNotEmpty) {
      yield (
        kind: SlicerPlantKind.bramble,
        planter: remaining.contains(pattern.bramble)
            ? pattern.bramble
            : remaining.first,
        marchSeconds: max(3.3, pattern.brambleMarch - speedup),
        biteSeconds: 2.12,
        cuts: 3,
      );
    }
  }
}
