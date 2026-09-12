import 'dart:math';

enum CropKind { strawberry, tomato, blueberry, pumpkin, eggplant, pepper }

extension CropDescription on CropKind {
  String get label => switch (this) {
    CropKind.strawberry => 'Strawberries',
    CropKind.tomato => 'Tomatoes',
    CropKind.blueberry => 'Blueberries',
    CropKind.pumpkin => 'Pumpkins',
    CropKind.eggplant => 'Eggplants',
    CropKind.pepper => 'Golden peppers',
  };
  int get sprite => switch (this) {
    CropKind.strawberry => 0,
    CropKind.tomato => 1,
    CropKind.blueberry => 2,
    CropKind.pumpkin => 3,
    CropKind.eggplant => 4,
    CropKind.pepper => 5,
  };
  int get greenhouseLevel => switch (this) {
    CropKind.strawberry || CropKind.tomato => 0,
    CropKind.blueberry => 1,
    CropKind.pumpkin => 2,
    CropKind.eggplant => 3,
    CropKind.pepper => 4,
  };
}

enum GardenUpgrade { greenhouse, terrace }

const gardenTierNames = [
  'Stone Courtyard',
  'Sunlit Orchard',
  'Autumn Retreat',
  'Walled Conservatory',
  'Mountain Garden',
  'Grand Estate',
];

int _integer(Object? value, int fallback, int low, int high) =>
    value is num && value.isFinite ? value.toInt().clamp(low, high) : fallback;

/// Persistent player ownership. Round state is deliberately kept separately.
class HarvestProgress {
  HarvestProgress({this.coins = 840});

  int coins;
  int tier = 1;
  int greenhouse = 0;
  int terrace = 0;
  int tierOrders = 0;
  int totalOrders = 0;
  int bestChain = 0;
  int rounds = 0;
  final List<CropKind> crops = [
    CropKind.strawberry,
    CropKind.strawberry,
    CropKind.strawberry,
    CropKind.tomato,
    CropKind.strawberry,
    CropKind.strawberry,
  ];
  final List<int> beds = List.filled(6, 1);

  String get tierName => gardenTierNames[tier - 1];
  int get bedCount => terrace > 0 ? 6 : 4;
  int get targetOrders => tier + 2;
  int get upgradeCost => 900 + (tier - 1) * 350;
  int get bedCost => 120 + (tier - 1) * 60;
  int get advanceCost => 400 + (tier - 1) * 200;
  bool get rareCropsUnlocked => greenhouse > 0;
  Iterable<CropKind> get unlockedCrops => CropKind.values.where(isCropUnlocked);
  CropKind get newestCrop => unlockedCrops.last;
  bool isCropUnlocked(CropKind crop) => greenhouse >= crop.greenhouseLevel;
  int get upgradedBeds => beds.take(4).where((level) => level >= 2).length;
  bool get tierComplete =>
      greenhouse >= tier &&
      terrace >= tier &&
      upgradedBeds == 4 &&
      tierOrders >= targetOrders;
  bool get finalTier => tier == gardenTierNames.length;
  double get tierProgress =>
      ((greenhouse >= tier ? 1 : 0) +
          (terrace >= tier ? 1 : 0) +
          upgradedBeds / 4 +
          min(1.0, tierOrders / targetOrders)) /
      4;

  bool ownsUpgrade(GardenUpgrade upgrade) =>
      (upgrade == GardenUpgrade.greenhouse ? greenhouse : terrace) >= tier;

  bool buyUpgrade(GardenUpgrade upgrade) {
    if (ownsUpgrade(upgrade) || coins < upgradeCost) return false;
    coins -= upgradeCost;
    if (upgrade == GardenUpgrade.greenhouse) {
      greenhouse = tier;
    } else {
      terrace = tier;
    }
    return true;
  }

  bool plant(int bed, CropKind crop) {
    if (bed < 0 || bed >= bedCount || !isCropUnlocked(crop)) {
      return false;
    }
    crops[bed] = crop;
    return true;
  }

  bool improveBed(int bed) {
    if (bed < 0 || bed >= bedCount || beds[bed] >= 2 || coins < bedCost) {
      return false;
    }
    coins -= bedCost;
    beds[bed] = 2;
    return true;
  }

  bool advanceTier() {
    if (!tierComplete || finalTier || coins < advanceCost) return false;
    coins -= advanceCost;
    tier++;
    tierOrders = 0;
    // Start the next garden's planting work afresh, preserving landmarks,
    // currency, crop unlocks and lifetime records.
    for (var i = 0; i < 6; i++) {
      beds[i] = 1;
      crops[i] = switch (i) {
        0 => newestCrop,
        3 => CropKind.tomato,
        _ => CropKind.strawberry,
      };
    }
    return true;
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'tier': tier,
    'greenhouse': greenhouse,
    'terrace': terrace,
    'tierOrders': tierOrders,
    'totalOrders': totalOrders,
    'bestChain': bestChain,
    'rounds': rounds,
    'crops': crops.map((crop) => crop.name).toList(),
    'beds': beds.toList(),
  };

  factory HarvestProgress.fromJson(Object? raw, {int coins = 840}) {
    final progress = HarvestProgress(coins: max(0, coins));
    if (raw is! Map) return progress;
    progress.tier = _integer(raw['tier'], 1, 1, gardenTierNames.length);
    progress.greenhouse = _integer(raw['greenhouse'], 0, 0, progress.tier);
    progress.terrace = _integer(raw['terrace'], 0, 0, progress.tier);
    progress.tierOrders = _integer(raw['tierOrders'], 0, 0, 1000000);
    progress.totalOrders = _integer(raw['totalOrders'], 0, 0, 1000000);
    progress.bestChain = _integer(raw['bestChain'], 0, 0, 1000);
    progress.rounds = _integer(raw['rounds'], 0, 0, 1000000);
    final rawCrops = raw['crops'];
    final rawBeds = raw['beds'];
    for (var i = 0; i < 6; i++) {
      if (rawCrops is List && i < rawCrops.length) {
        final crop = CropKind.values
            .where((c) => c.name == rawCrops[i])
            .firstOrNull;
        if (crop != null && progress.isCropUnlocked(crop)) {
          progress.crops[i] = crop;
        }
      }
      if (rawBeds is List && i < rawBeds.length) {
        progress.beds[i] = _integer(rawBeds[i], 1, 1, 2);
      }
    }
    return progress;
  }
}

class HarvestCrop {
  HarvestCrop({
    required this.id,
    required this.bed,
    required this.slot,
    required this.kind,
    this.ripeAt = 0,
  });
  final int id;
  final int bed;
  final int slot;
  final CropKind kind;
  double ripeAt;
  bool isRipe(double elapsed) => elapsed >= ripeAt;
}

class HarvestResult {
  const HarvestResult({this.count = 0, this.orders = 0, this.coins = 0});
  final int count;
  final int orders;
  final int coins;
}

/// Pure round rules; the UI feeds elapsed *active* time and gesture hits.
class HarvestRound {
  HarvestRound(this.progress) {
    final seed = progress.rounds + progress.tier * 17;
    for (var bed = 0; bed < progress.bedCount; bed++) {
      for (var slot = 0; slot < 5; slot++) {
        final id = bed * 5 + slot;
        crops.add(
          HarvestCrop(
            id: id,
            bed: bed,
            slot: slot,
            kind: progress.crops[bed],
            ripeAt: (id + seed) % 5 == 0 ? 4.0 + (id % 3) : 0,
          ),
        );
      }
    }
    orderKind = progress.crops.first;
  }

  final HarvestProgress progress;
  final List<HarvestCrop> crops = [];
  final List<int> chain = [];
  final Set<int> _visited = {};
  late CropKind orderKind;
  double elapsed = 0;
  bool running = false;
  bool paused = false;
  bool finished = false;
  bool _gestureBlocked = false;
  int collected = 0;
  int orders = 0;
  int earnings = 0;
  int bestChain = 0;
  int get secondsLeft => max(0, (60 - elapsed).ceil());
  int get orderTarget => 12 + (progress.tier - 1) * 2;
  int get orderReward =>
      180 +
      (progress.tier - 1) * 40 +
      (orderKind.greenhouseLevel > 0 ? 60 + (progress.greenhouse - 1) * 20 : 0);
  double get regrowSeconds => max(2.4, 5.5 - progress.terrace * .4);
  bool get acceptsInput => running && !paused && !finished;

  void start() {
    if (running || finished) return;
    running = true;
    progress.rounds++;
  }

  void tick(double seconds) {
    if (!acceptsInput || !seconds.isFinite || seconds <= 0) return;
    elapsed = min(60, elapsed + seconds);
    if (elapsed >= 60) finish();
  }

  void beginGesture() {
    cancelGesture();
    _gestureBlocked = false;
  }

  bool hit(int id) {
    if (!acceptsInput || _gestureBlocked || _visited.contains(id)) return false;
    final crop = crops.where((crop) => crop.id == id).firstOrNull;
    if (crop == null) return false;
    _visited.add(id);
    if (!crop.isRipe(elapsed) ||
        (chain.isNotEmpty &&
            crops.firstWhere((c) => c.id == chain.first).kind != crop.kind)) {
      // Preserve the valid prefix. It is gathered only on pointer release.
      _gestureBlocked = true;
      return false;
    }
    chain.add(id);
    return true;
  }

  HarvestResult release() {
    if (!acceptsInput || chain.isEmpty) {
      cancelGesture();
      return const HarvestResult();
    }
    final picked = chain
        .map((id) => crops.firstWhere((c) => c.id == id))
        .toList();
    final count = picked.length;
    bestChain = max(bestChain, count);
    progress.bestChain = max(progress.bestChain, count);
    final kind = picked.first.kind;
    final yield = picked.fold<int>(
      0,
      (sum, crop) => sum + progress.beds[crop.bed],
    );
    for (final crop in picked) {
      crop.ripeAt = elapsed + regrowSeconds + (crop.id % 3) * .2;
    }
    cancelGesture();
    int awarded = 0;
    int completed = 0;
    if (kind == orderKind) {
      collected += yield;
      while (collected >= orderTarget) {
        collected -= orderTarget;
        awarded += orderReward;
        completed++;
      }
      if (completed > 0) {
        orders += completed;
        earnings += awarded;
        progress.coins += awarded;
        progress.tierOrders += completed;
        progress.totalOrders += completed;
        // Alternate only between crops actually planted, so orders are solvable.
        final planted = progress.crops.take(progress.bedCount).toSet().toList();
        if (collected == 0) orderKind = planted[orders % planted.length];
      }
    }
    return HarvestResult(count: count, orders: completed, coins: awarded);
  }

  void cancelGesture() {
    chain.clear();
    _visited.clear();
  }

  void pause() {
    if (running && !finished) paused = true;
    cancelGesture();
  }

  void resume() {
    if (!finished) paused = false;
  }

  void finish() {
    finished = true;
    running = false;
    paused = false;
    cancelGesture();
  }
}
