import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class GardenNinjaApp extends StatelessWidget {
  const GardenNinjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Garden Ninja',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F9F22)),
        fontFamily: 'Arial',
        useMaterial3: true,
      ),
      home: const GardenNinjaScreen(),
    );
  }
}

enum GamePhase { home, playing, paused, results, upgrades }

enum TargetType { weed, flower, bonus, reward }

class GardenTarget {
  GardenTarget({
    required this.id,
    required this.type,
    required this.asset,
    required this.position,
    required this.velocity,
    required this.size,
    required this.radius,
    required this.spin,
    required int cutsRequired,
  }) : angle = 0,
       maxCuts = cutsRequired,
       cutsRemaining = cutsRequired,
       walkPhase = 0;

  final int id;
  final TargetType type;
  final String asset;
  Offset position;
  Offset velocity;
  double size;
  final double radius;
  final double spin;
  final int maxCuts;
  int cutsRemaining;
  double angle;
  double cooldown = 0;
  double walkPhase;
  double splitAngle = 0;
  double splitAmount = 0;
}

class SlashTrail {
  SlashTrail(this.start, this.end, this.life);

  Offset start;
  Offset end;
  double life;
}

class SliceShard {
  SliceShard({
    required this.asset,
    required this.position,
    required this.velocity,
    required this.size,
    required this.angle,
    required this.spin,
    required this.cutAngle,
    required this.keepPositiveSide,
  });

  final String asset;
  Offset position;
  Offset velocity;
  final double size;
  double angle;
  final double spin;
  final double cutAngle;
  final bool keepPositiveSide;
  double life = 0.56;
}

class FloatingBurst {
  FloatingBurst({
    required this.position,
    required this.label,
    required this.color,
  });

  Offset position;
  final String label;
  final Color color;
  double life = 0.8;
}

class GardenNinjaScreen extends StatefulWidget {
  const GardenNinjaScreen({super.key});

  @override
  State<GardenNinjaScreen> createState() => _GardenNinjaScreenState();
}

class _GardenNinjaScreenState extends State<GardenNinjaScreen>
    with SingleTickerProviderStateMixin {
  static const double _worldWidth = 390;
  static const double _worldHeight = 844;
  static const double _gardenDamageLineY = _worldHeight - 106;
  static const double _minSlashSegment = 7;
  static const int _maxSlashTrails = 22;
  static const int _maxSliceShards = 20;
  static const List<String> _weedAssets = [
    'assets/images/sprites/weed_spike.png',
    'assets/images/sprites/weed_vine.png',
    'assets/images/sprites/weed_leaf.png',
    'assets/images/sprites/weed_thorn_sprout.png',
    'assets/images/sprites/weed_vine_gobbler.png',
    'assets/images/sprites/weed_bramble_bulb.png',
    'assets/images/sprites/weed_seed_chomper.png',
  ];
  static const List<String> _flowerAssets = [
    'assets/images/sprites/flower_daisy.png',
    'assets/images/sprites/flower_shield.png',
    'assets/images/sprites/pink_blossom_plant.png',
    'assets/images/sprites/blue_bell_bloom.png',
    'assets/images/sprites/cherry_blossom_sapling.png',
    'assets/images/sprites/pink_blossom_bush.png',
  ];
  static const List<String> _gardenPatchAssets = [
    'assets/images/sprites/flower_shield.png',
    'assets/images/sprites/pink_blossom_plant.png',
    'assets/images/sprites/cherry_blossom_sapling.png',
  ];
  static const List<String> _avatarAssets = [
    'assets/images/sprites/avatar_male.png',
    'assets/images/sprites/avatar_female.png',
  ];
  static const List<String> _backgrounds = [
    'assets/images/backgrounds/garden_playfield.png',
    'assets/images/backgrounds/bamboo_dawn.png',
    'assets/images/backgrounds/greenhouse_night.png',
    'assets/images/backgrounds/rainy_garden.png',
    'assets/images/backgrounds/autumn_pond.png',
    'assets/images/backgrounds/cherry_blossom_bridge.png',
    'assets/images/backgrounds/moonlit_lotus.png',
    'assets/images/backgrounds/winter_conservatory.png',
    'assets/images/backgrounds/mushroom_grove.png',
    'assets/images/backgrounds/desert_cactus_bloom.png',
    'assets/images/backgrounds/rooftop_greenhouse.png',
    'assets/images/backgrounds/crystal_cave_garden.png',
    'assets/images/backgrounds/tropical_orchid_jungle.png',
  ];

  final Random _random = Random();
  final List<GardenTarget> _targets = [];
  final List<SliceShard> _shards = [];
  final List<SlashTrail> _slashes = [];
  final List<FloatingBurst> _bursts = [];

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  GamePhase _phase = GamePhase.home;
  GamePhase _phaseBeforePause = GamePhase.home;

  int _nextTargetId = 1;
  int _level = 1;
  int _score = 0;
  int _bestScore = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _lives = 3;
  int _gardenDamage = 0;
  int _weedsSlashed = 0;
  int _flowersSaved = 0;
  int _seeds = 1250;
  int _sunDrops = 4;
  int _waterCharges = 3;
  int _iceCharges = 2;
  int _rewardSeeds = 0;
  int _selectedAvatar = 0;
  bool _lastRunWon = false;
  double _spawnTimer = 0;
  double _timeLeft = 60;
  double _iceTime = 0;
  double _sunTime = 0;
  double _flowerPenaltyCooldown = 0;
  double _gardenDamageFlash = 0;
  double _gardenDamageCooldown = 0;
  double _motionTime = 0;
  Offset? _lastSlashPoint;

  int get _goalWeeds => 18 + (_level * 4);

  String get _currentBackground =>
      _backgrounds[(_level - 1) % _backgrounds.length];

  String get _currentAvatar => _avatarAssets[_selectedAvatar];

  String _formatNumber(int value) {
    final String text = value.toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < text.length; i += 1) {
      if (i > 0 && (text.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }

    final double dt =
        ((elapsed - _lastElapsed).inMicroseconds /
                Duration.microsecondsPerSecond)
            .clamp(0.0, 0.05)
            .toDouble();
    _lastElapsed = elapsed;

    if (_phase == GamePhase.playing) {
      setState(() {
        _motionTime += dt;
        _step(dt);
      });
      return;
    }

    if (_phase == GamePhase.home) {
      setState(() {
        _motionTime += dt;
      });
    }
  }

  void _startRun({bool restartLevel = false}) {
    setState(() {
      if (!restartLevel) {
        _level = max(1, _level);
      }
      _phase = GamePhase.playing;
      _score = 0;
      _combo = 0;
      _maxCombo = 0;
      _lives = 3;
      _gardenDamage = 0;
      _weedsSlashed = 0;
      _flowersSaved = 0;
      _spawnTimer = 0.1;
      _timeLeft = max(42, 62 - (_level * 2)).toDouble();
      _iceTime = 0;
      _sunTime = 0;
      _flowerPenaltyCooldown = 0;
      _gardenDamageFlash = 0;
      _gardenDamageCooldown = 0;
      _lastSlashPoint = null;
      _targets.clear();
      _shards.clear();
      _slashes.clear();
      _bursts.clear();
      _spawnOpeningWave();
    });
  }

  void _step(double dt) {
    _timeLeft -= dt;
    if (_timeLeft <= 0) {
      _finishRun(won: _weedsSlashed >= (_goalWeeds * 0.75));
      return;
    }

    _iceTime = max(0, _iceTime - dt);
    _sunTime = max(0, _sunTime - dt);
    _flowerPenaltyCooldown = max(0, _flowerPenaltyCooldown - dt);
    _gardenDamageFlash = max(0, _gardenDamageFlash - dt * 2.4);
    _gardenDamageCooldown = max(0, _gardenDamageCooldown - dt);

    final bool iceActive = _iceTime > 0;
    final double speedScale = iceActive ? 0.08 : 1;
    final double animationScale = iceActive ? 0.18 : 1;
    for (final target in List<GardenTarget>.from(_targets)) {
      target.cooldown = max(0, target.cooldown - dt);
      target.splitAmount = max(0, target.splitAmount - dt * 2.8);
      target.walkPhase +=
          dt * (target.type == TargetType.weed ? 8.5 : 2.2) * animationScale;

      if (target.type == TargetType.weed) {
        target.angle =
            sin(target.walkPhase * 1.15) * 0.075 +
            cos(target.walkPhase * 0.52) * 0.025;
        target.position += target.velocity * dt * speedScale;
      } else if (target.type != TargetType.flower) {
        target.angle += target.spin * dt * speedScale;
        target.position += target.velocity * dt * speedScale;
      } else {
        target.angle = 0;
      }

      if (target.position.dx < 34 || target.position.dx > _worldWidth - 34) {
        target.velocity = Offset(-target.velocity.dx, target.velocity.dy);
      }

      if (target.position.dy > _gardenDamageLineY) {
        _targets.remove(target);
        if (target.type == TargetType.weed) {
          _damageGardenFromWeed(target);
          if (_lives <= 0) {
            _finishRun(won: false);
            return;
          }
        }
      }
    }

    _spawnTimer -= dt * (iceActive ? 0.3 : 1);
    if (_spawnTimer <= 0 && _targets.length < 7 + min(_level, 3)) {
      _spawnTarget();
      _spawnTimer =
          (1.05 - min(_level * 0.055, 0.35)) *
          (0.75 + _random.nextDouble() * 0.65);
    }

    for (final slash in _slashes) {
      slash.life -= dt * 2.8;
    }
    _slashes.removeWhere((slash) => slash.life <= 0);

    for (final shard in _shards) {
      shard.life -= dt * 1.55;
      shard.position += shard.velocity * dt;
      shard.velocity = Offset(
        shard.velocity.dx * 0.96,
        shard.velocity.dy + 280 * dt,
      );
      shard.angle += shard.spin * dt;
    }
    _shards.removeWhere((shard) => shard.life <= 0);

    for (final burst in _bursts) {
      burst.life -= dt;
      burst.position -= Offset(0, 42 * dt);
    }
    _bursts.removeWhere((burst) => burst.life <= 0);
  }

  void _spawnTarget() {
    final double roll = _random.nextDouble();
    late TargetType type;
    late String asset;
    late double size;
    late double radius;
    int cutsRequired = 1;

    if (roll < 0.64) {
      type = TargetType.weed;
      asset = _weedAssets[_random.nextInt(_weedAssets.length)];
      size = 70 + _random.nextDouble() * 20;
      radius = size * 0.4;
      cutsRequired = _weedCutCountFor(asset);
    } else if (roll < 0.82) {
      type = TargetType.flower;
      asset = _flowerAssets[_random.nextInt(_flowerAssets.length)];
      size = 76 + _random.nextDouble() * 20;
      radius = size * 0.42;
      _flowersSaved += 1;
    } else if (roll < 0.93) {
      type = TargetType.bonus;
      asset = 'assets/images/sprites/ladybug.png';
      size = 58;
      radius = 28;
    } else {
      type = TargetType.reward;
      asset = 'assets/images/sprites/seed_bag.png';
      size = 64;
      radius = 28;
    }

    final double x = 58 + _random.nextDouble() * (_worldWidth - 116);
    final double y = type == TargetType.weed
        ? 120 + _random.nextDouble() * 180
        : 230 + _random.nextDouble() * 360;
    final double levelSpeed = 18 + _level * 4.5;
    final Offset velocity = type == TargetType.flower
        ? Offset.zero
        : Offset(
            (_random.nextDouble() - 0.5) * (28 + _level * 2),
            levelSpeed + _random.nextDouble() * 26,
          );

    _targets.add(
      GardenTarget(
        id: _nextTargetId++,
        type: type,
        asset: asset,
        position: Offset(x, y),
        velocity: velocity,
        size: size,
        radius: radius,
        spin: type == TargetType.flower
            ? 0
            : (_random.nextDouble() - 0.5) * 0.7,
        cutsRequired: cutsRequired,
      ),
    );
  }

  int _weedCutCountFor(String asset) {
    if (asset.contains('weed_bramble_bulb')) {
      return 4;
    }
    if (asset.contains('weed_vine_gobbler') || asset.contains('weed_vine')) {
      return 3;
    }
    if (asset.contains('weed_leaf') || asset.contains('weed_thorn_sprout')) {
      return 2;
    }
    return _random.nextDouble() < 0.34 + min(_level, 5) * 0.05 ? 2 : 1;
  }

  void _spawnOpeningWave() {
    _targets.add(
      GardenTarget(
        id: _nextTargetId++,
        type: TargetType.weed,
        asset: 'assets/images/sprites/weed_thorn_sprout.png',
        position: const Offset(_worldWidth / 2, 315),
        velocity: Offset(8.0 + _level, 24.0 + _level * 2),
        size: 82,
        radius: 36,
        spin: 0.18,
        cutsRequired: 2,
      ),
    );
    _targets.add(
      GardenTarget(
        id: _nextTargetId++,
        type: TargetType.flower,
        asset: 'assets/images/sprites/pink_blossom_plant.png',
        position: const Offset(92, 560),
        velocity: Offset.zero,
        size: 78,
        radius: 32,
        spin: 0,
        cutsRequired: 1,
      ),
    );
    _flowersSaved += 1;
  }

  void _handleSlash(Offset localPosition, Size size) {
    if (_phase != GamePhase.playing) {
      return;
    }

    final Offset world = _toWorld(localPosition, size);
    if (!_isSlashInPlayArea(world)) {
      _lastSlashPoint = world;
      return;
    }

    final Offset? previous = _lastSlashPoint;
    final Offset start = previous ?? world;
    if (previous != null && (world - start).distance < _minSlashSegment) {
      return;
    }

    _slashes.add(SlashTrail(start, world, previous == null ? 0.45 : 0.65));
    if (_slashes.length > _maxSlashTrails) {
      _slashes.removeRange(0, _slashes.length - _maxSlashTrails);
    }
    _lastSlashPoint = world;
    _checkHits(start, world);
  }

  void _endSlash() {
    _lastSlashPoint = null;
  }

  Offset _toWorld(Offset local, Size size) {
    return Offset(
      local.dx / size.width * _worldWidth,
      local.dy / size.height * _worldHeight,
    );
  }

  bool _isSlashInPlayArea(Offset point) {
    return point.dy > 82 && point.dy < _worldHeight - 104;
  }

  void _checkHits(Offset start, Offset end) {
    final Offset direction = end - start;
    int hitCount = 0;
    for (final target in List<GardenTarget>.from(_targets)) {
      if (target.cooldown > 0) {
        continue;
      }
      if (_distanceToSegment(target.position, start, end) <= target.radius) {
        _hitTarget(target, direction);
        hitCount += 1;
        if (_phase != GamePhase.playing || hitCount >= 3) {
          break;
        }
      }
    }
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final Offset segment = end - start;
    final double lengthSquared = segment.distanceSquared;
    if (lengthSquared <= 0.001) {
      return (point - end).distance;
    }

    final double projection =
        (((point.dx - start.dx) * segment.dx) +
            ((point.dy - start.dy) * segment.dy)) /
        lengthSquared;
    final double t = projection.clamp(0.0, 1.0).toDouble();
    final Offset closest = start + segment * t;
    return (point - closest).distance;
  }

  void _hitTarget(GardenTarget target, Offset direction) {
    switch (target.type) {
      case TargetType.weed:
        _spawnSliceShards(target, direction);
        _combo += 1;
        _maxCombo = max(_maxCombo, _combo);
        target.cutsRemaining -= 1;
        target.cooldown = 0.22;
        final bool defeated = target.cutsRemaining <= 0;
        final int base = defeated ? 140 + (_combo * 15) : 70 + (_combo * 12);
        final int earned = _sunTime > 0 ? base * 2 : base;
        _score += earned;
        if (defeated) {
          _targets.remove(target);
          _weedsSlashed += 1;
          _addBurst(target.position, '+$earned Weed', const Color(0xFFEFFF94));
          if (_weedsSlashed >= _goalWeeds) {
            _finishRun(won: true);
          }
        } else {
          target.size *= 0.91;
          final Offset slash = _safeDirection(direction);
          target.splitAngle = atan2(slash.dy, slash.dx);
          target.splitAmount = 1;
          final Offset shove = slash * 26;
          target.position += shove;
          target.velocity += shove * 0.8;
          _addBurst(
            target.position,
            '+$earned | ${target.cutsRemaining} cuts',
            const Color(0xFFEFFF94),
          );
        }
      case TargetType.flower:
        target.cooldown = 0.7;
        _combo = 0;
        _score = max(0, _score - 150);
        _flowersSaved = max(0, _flowersSaved - 1);
        _flowerPenaltyCooldown = 0.45;
        _addBurst(target.position, '-150 Plant', const Color(0xFFFF9FCA));
      case TargetType.bonus:
        _targets.remove(target);
        _combo += 1;
        _maxCombo = max(_maxCombo, _combo);
        _score += 320 + (_combo * 10);
        _waterCharges = min(5, _waterCharges + 1);
        _addBurst(target.position, '+Nice +Water', const Color(0xFF86E7FF));
      case TargetType.reward:
        _targets.remove(target);
        _seeds += 55;
        _score += 180;
        _addBurst(target.position, '+55 Seeds', const Color(0xFFFFD36A));
    }
  }

  Offset _safeDirection(Offset direction) {
    if (direction.distance < 0.001) {
      return const Offset(1, -0.25);
    }
    return direction / direction.distance;
  }

  void _spawnSliceShards(GardenTarget target, Offset direction) {
    if (_shards.length > _maxSliceShards - 2) {
      _shards.removeRange(0, _shards.length - (_maxSliceShards - 2));
    }

    final Offset slash = _safeDirection(direction);
    final Offset normal = Offset(-slash.dy, slash.dx);
    final double cutAngle = atan2(slash.dy, slash.dx);
    for (int i = 0; i < 2; i += 1) {
      final double side = i == 0 ? 1 : -1;
      final double jitter = (_random.nextDouble() - 0.5) * 36;
      _shards.add(
        SliceShard(
          asset: target.asset,
          position: target.position + normal * side * 5,
          velocity:
              slash * (55 + _random.nextDouble() * 45) +
              normal * side * (150 + _random.nextDouble() * 80) +
              Offset(jitter, -80 - _random.nextDouble() * 45),
          size: target.size * 0.95,
          angle: target.angle,
          spin: side * (4.8 + _random.nextDouble() * 3.4),
          cutAngle: cutAngle,
          keepPositiveSide: side > 0,
        ),
      );
    }
  }

  void _damageGardenFromWeed(GardenTarget weed) {
    if (_gardenDamageCooldown > 0) {
      return;
    }

    _lives = max(0, _lives - 1);
    _gardenDamage = min(3, _gardenDamage + 1);
    _gardenDamageFlash = 1;
    _gardenDamageCooldown = 2.8;
    _flowersSaved = max(0, _flowersSaved - 1);
    _combo = 0;

    final double x = weed.position.dx.clamp(64.0, _worldWidth - 64).toDouble();
    _addBurst(
      Offset(x, _worldHeight - 176),
      'Plants hit!',
      const Color(0xFFFFC857),
    );
  }

  void _addBurst(Offset position, String label, Color color) {
    _bursts.add(FloatingBurst(position: position, label: label, color: color));
  }

  void _activateWater() {
    if (_phase != GamePhase.playing || _waterCharges <= 0) {
      return;
    }
    setState(() {
      _waterCharges -= 1;
      final weeds = _targets.where((t) => t.type == TargetType.weed).toList();
      for (final weed in weeds) {
        _spawnSliceShards(weed, const Offset(0, -1));
        _targets.remove(weed);
        _weedsSlashed += 1;
        _score += 90;
        _addBurst(weed.position, 'Splash', const Color(0xFF8DEBFF));
      }
      _combo += weeds.length;
      _maxCombo = max(_maxCombo, _combo);
      if (_weedsSlashed >= _goalWeeds) {
        _finishRun(won: true);
      }
    });
  }

  void _activateSun() {
    if (_phase != GamePhase.playing || _sunDrops <= 0) {
      return;
    }
    setState(() {
      _sunDrops -= 1;
      _sunTime = 7;
      _score += 250;
      _addBurst(
        const Offset(_worldWidth / 2, 150),
        'Sun boost',
        const Color(0xFFFFE66B),
      );
    });
  }

  void _activateIce() {
    if (_phase != GamePhase.playing || _iceCharges <= 0) {
      return;
    }
    setState(() {
      _iceCharges -= 1;
      _iceTime = max(_iceTime, 6.5);
      _addBurst(
        const Offset(_worldWidth / 2, 220),
        'Freeze!',
        const Color(0xFF8EF5FF),
      );
    });
  }

  void _finishRun({required bool won}) {
    _lastRunWon = won;
    _bestScore = max(_bestScore, _score);
    _rewardSeeds = (won ? 110 : 45) + (_weedsSlashed * 2) + (_maxCombo * 3);
    _seeds += _rewardSeeds;
    _targets.clear();
    _shards.clear();
    _slashes.clear();
    _bursts.clear();
    _phase = GamePhase.results;
  }

  void _pause() {
    if (_phase != GamePhase.playing) {
      return;
    }
    setState(() {
      _phaseBeforePause = _phase;
      _phase = GamePhase.paused;
    });
  }

  void _resume() {
    if (_phase != GamePhase.paused) {
      return;
    }
    setState(() {
      _phase = _phaseBeforePause;
    });
  }

  void _openUpgrades() {
    setState(() {
      _phase = GamePhase.upgrades;
    });
  }

  void _selectAvatar(int index) {
    setState(() {
      _selectedAvatar = index.clamp(0, _avatarAssets.length - 1).toInt();
    });
  }

  void _buyCharge(String kind, int cost) {
    if (_seeds < cost) {
      return;
    }
    setState(() {
      _seeds -= cost;
      switch (kind) {
        case 'water':
          _waterCharges += 1;
        case 'sun':
          _sunDrops += 1;
        case 'ice':
          _iceCharges += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102716),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF143C1B), Color(0xFF061B12)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double width = min(
                  constraints.maxWidth,
                  constraints.maxHeight * (_worldWidth / _worldHeight),
                );
                final double height = width * (_worldHeight / _worldWidth);
                return SizedBox(
                  width: width,
                  height: height,
                  child: LayoutBuilder(
                    builder: (context, gameConstraints) {
                      final Size size = gameConstraints.biggest;
                      return _buildGameSurface(size);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameSurface(Size size) {
    final bool acceptsSlashInput = _phase == GamePhase.playing;
    final Widget surface = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackdrop(),
          if (_phase == GamePhase.playing || _phase == GamePhase.paused) ...[
            _buildGardenHealthBed(),
            ..._targets.map((target) => _buildTarget(target, size)),
            ..._shards.map((shard) => _buildShard(shard, size)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: SlashPainter(
                    trails: List<SlashTrail>.from(_slashes),
                    worldSize: const Size(_worldWidth, _worldHeight),
                  ),
                ),
              ),
            ),
            ..._bursts.map((burst) => _buildBurst(burst, size)),
            if (_gardenDamageFlash > 0) _buildGardenDamageFlash(),
            _buildHud(),
            _buildPowerUps(),
          ],
          if (_phase == GamePhase.home) _buildHomeLayer(),
          if (_phase == GamePhase.paused) _buildPausedLayer(),
          if (_phase == GamePhase.results) _buildResultsLayer(),
          if (_phase == GamePhase.upgrades) _buildUpgradesLayer(),
        ],
      ),
    );

    if (!acceptsSlashInput) {
      return surface;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _handleSlash(details.localPosition, size),
      onPanUpdate: (details) => _handleSlash(details.localPosition, size),
      onPanEnd: (_) => _endSlash(),
      onTapDown: (details) => _handleSlash(details.localPosition, size),
      child: surface,
    );
  }

  Widget _buildGardenHealthBed() {
    return Positioned(
      left: 40,
      right: 40,
      bottom: 120,
      height: 72,
      child: IgnorePointer(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            3,
            (index) => _GardenPatch(
              index: index,
              asset: _gardenPatchAssets[index % _gardenPatchAssets.length],
              damaged: index < _gardenDamage,
              active: _gardenDamageFlash > 0 && index == _gardenDamage - 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGardenDamageFlash() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: (_gardenDamageFlash * 0.65).clamp(0.0, 0.65),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomCenter,
                radius: 0.82,
                colors: [
                  Color(0xCCB94123),
                  Color(0x6631180D),
                  Color(0x0011170B),
                ],
                stops: [0, 0.46, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop() {
    final bool useSplash = _phase == GamePhase.home;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          useSplash
              ? 'assets/images/splash/home_garden_path.png'
              : _currentBackground,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: useSplash
                  ? const [
                      Color(0x11FFFFFF),
                      Color(0x00000000),
                      Color(0x220B2A0D),
                      Color(0x6607190B),
                    ]
                  : const [
                      Color(0x5511290D),
                      Color(0x0011290D),
                      Color(0x8811290D),
                    ],
              stops: useSplash ? const [0, 0.34, 0.7, 1] : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShard(SliceShard shard, Size size) {
    final double pixelSize = shard.size / _worldWidth * size.width;
    final double left =
        shard.position.dx / _worldWidth * size.width - pixelSize / 2;
    final double top =
        shard.position.dy / _worldHeight * size.height - pixelSize / 2;
    return Positioned(
      left: left,
      top: top,
      width: pixelSize,
      height: pixelSize,
      child: Opacity(
        opacity: shard.life.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: shard.angle,
          child: ClipPath(
            clipper: SliceHalfClipper(
              cutAngle: shard.cutAngle,
              keepPositiveSide: shard.keepPositiveSide,
            ),
            child: Image.asset(shard.asset, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _buildTarget(GardenTarget target, Size size) {
    final double pixelSize = target.size / _worldWidth * size.width;
    final double left =
        target.position.dx / _worldWidth * size.width - pixelSize / 2;
    final double top =
        target.position.dy / _worldHeight * size.height - pixelSize / 2;
    final bool flowerCooling =
        target.type == TargetType.flower && target.cooldown > 0;
    final double pulse =
        1 + (flowerCooling ? sin(target.cooldown * 18) * 0.08 : 0);
    final bool isWeed = target.type == TargetType.weed;
    final bool isFrozen =
        _iceTime > 0 &&
        target.type != TargetType.flower &&
        target.type != TargetType.reward;
    final bool weedCooling = isWeed && target.cooldown > 0;
    final double hitPulse = weedCooling
        ? 1 + sin(target.cooldown * 42).abs() * 0.12
        : 1;
    final double walkBob = isWeed ? sin(target.walkPhase) * 4 : 0;
    final double walkHop = isWeed ? -sin(target.walkPhase * 2).abs() * 2.4 : 0;
    final double walkSide = isWeed ? cos(target.walkPhase * 0.75) * 2.5 : 0;
    final double walkLean = isWeed ? target.angle : 0;
    final double walkSquash = isWeed
        ? 1 + sin(target.walkPhase * 2.2) * 0.05
        : 1;

    return Positioned(
      key: ValueKey('target-${target.id}'),
      left: left,
      top: top,
      width: pixelSize,
      height: pixelSize,
      child: Transform.translate(
        offset: Offset(walkSide, walkBob + walkHop),
        child: Transform.scale(
          scale: hitPulse,
          child: Transform.rotate(
            angle: walkLean,
            child: Transform.scale(
              scaleX: walkSquash,
              scaleY: pulse / walkSquash,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isWeed)
                    Positioned(
                      left: pixelSize * 0.2,
                      right: pixelSize * 0.2,
                      bottom: pixelSize * 0.06,
                      height: pixelSize * 0.12,
                      child: Transform.scale(
                        scaleX: 1.1 + sin(target.walkPhase * 2).abs() * 0.16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x66081507),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  if (target.type == TargetType.flower)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFB6F2FF,
                            ).withValues(alpha: 0.5),
                            blurRadius: 22,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ColorFiltered(
                    colorFilter: isFrozen
                        ? const ColorFilter.mode(
                            Color(0xFFBDEFFF),
                            BlendMode.modulate,
                          )
                        : const ColorFilter.mode(
                            Colors.white,
                            BlendMode.modulate,
                          ),
                    child: _buildTargetImage(target),
                  ),
                  if (isFrozen)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xAA8EF5FF),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF8EF5FF,
                                ).withValues(alpha: 0.42),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (isFrozen)
                    Positioned(
                      right: 0,
                      top: 4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xEE163E4D),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFBDF8FF),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.ac_unit_rounded,
                          color: Color(0xFFBDF8FF),
                          size: 15,
                        ),
                      ),
                    ),
                  if (isWeed && target.maxCuts > 1)
                    Positioned(
                      left: pixelSize * 0.2,
                      right: pixelSize * 0.2,
                      top: 0,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            target.maxCuts,
                            (index) => Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.4,
                              ),
                              decoration: BoxDecoration(
                                color: index < target.cutsRemaining
                                    ? const Color(0xFFFFE66B)
                                    : const Color(0x88412713),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF3B260C),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (weedCooling)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xAAEEFF79),
                          width: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetImage(GardenTarget target) {
    final double split = target.type == TargetType.weed
        ? target.splitAmount.clamp(0.0, 1.0)
        : 0;
    if (split <= 0) {
      return Image.asset(target.asset, fit: BoxFit.contain);
    }

    final double easedSplit = Curves.easeOutCubic.transform(split);
    final Offset normal = Offset(
      -sin(target.splitAngle),
      cos(target.splitAngle),
    );
    final double gap = 18 * easedSplit;
    final double tilt = 0.16 * easedSplit;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.translate(
          offset: normal * gap,
          child: Transform.rotate(
            angle: tilt,
            child: ClipPath(
              clipper: SliceHalfClipper(
                cutAngle: target.splitAngle,
                keepPositiveSide: true,
              ),
              child: Image.asset(target.asset, fit: BoxFit.contain),
            ),
          ),
        ),
        Transform.translate(
          offset: normal * -gap,
          child: Transform.rotate(
            angle: -tilt,
            child: ClipPath(
              clipper: SliceHalfClipper(
                cutAngle: target.splitAngle,
                keepPositiveSide: false,
              ),
              child: Image.asset(target.asset, fit: BoxFit.contain),
            ),
          ),
        ),
        CustomPaint(
          painter: SliceEdgePainter(
            cutAngle: target.splitAngle,
            opacity: easedSplit,
          ),
        ),
      ],
    );
  }

  Widget _buildBurst(FloatingBurst burst, Size size) {
    final double opacity = burst.life.clamp(0.0, 1.0);
    final double left = burst.position.dx / _worldWidth * size.width - 42;
    final double top = burst.position.dy / _worldHeight * size.height - 20;
    return Positioned(
      left: left,
      top: top,
      width: 84,
      child: Opacity(
        opacity: opacity,
        child: Text(
          burst.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: burst.color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: Color(0xFF17330D), blurRadius: 6),
              Shadow(color: Color(0xFF17330D), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Positioned(
      left: 14,
      right: 14,
      top: 12,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 362,
              child: Row(
                children: [
                  _StatPill(label: 'Score', value: _formatNumber(_score)),
                  const SizedBox(width: 8),
                  _StatPill(label: 'Combo', value: 'x$_combo'),
                  const Spacer(),
                  _IconPill(icon: Icons.favorite_rounded, value: '$_lives'),
                  const SizedBox(width: 8),
                  _IconPill(
                    icon: Icons.timer_rounded,
                    value: '${_timeLeft.ceil()}',
                  ),
                  const SizedBox(width: 8),
                  _RoundIconButton(
                    icon: Icons.pause_rounded,
                    onPressed: _pause,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (_weedsSlashed / _goalWeeds).clamp(0.0, 1.0),
              backgroundColor: const Color(0x88335C22),
              color: _sunTime > 0
                  ? const Color(0xFFFFE66B)
                  : const Color(0xFF79D13C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerUps() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: 18,
      child: Row(
        children: [
          Expanded(
            child: _PowerButton(
              asset: 'assets/images/icons/sun_boost.png',
              label: 'Sun',
              count: _sunDrops,
              active: _sunTime > 0,
              onTap: _activateSun,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PowerButton(
              asset: 'assets/images/icons/water_drop.png',
              label: 'Water',
              count: _waterCharges,
              active: false,
              onTap: _activateWater,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PowerButton(
              asset: 'assets/images/icons/ice_freeze.png',
              label: _iceTime > 0 ? 'Ice ${_iceTime.ceil()}s' : 'Ice',
              count: _iceCharges,
              active: _iceTime > 0,
              onTap: _activateIce,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeLayer() {
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: _worldWidth,
        height: _worldHeight,
        child: _buildHomeContent(),
      ),
    );
  }

  Widget _buildHomeContent() {
    final double t = _motionTime;
    final double logoBob = sin(t * 1.35) * 3.0;
    final double playPulse = 1 + sin(t * 2.6) * 0.028;
    final double mascotBob = sin(t * 2.05) * 5.0;
    final double weedBob = sin(t * 2.8 + 0.7) * 4.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        ..._buildHomeAtmosphere(t),
        Positioned(left: 18, right: 18, top: 14, child: _buildHomeTopBar()),
        Positioned(
          left: 8,
          right: 8,
          top: 76 + logoBob,
          child: Transform.scale(
            scale: 1 + sin(t * 1.1) * 0.01,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: 374, child: _buildHomeLogo()),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 284,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 342,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _AnimatedHomeFeature(
                    icon: Icons.shield_rounded,
                    label: 'Protect',
                    detail: 'plants',
                    phase: t,
                    delay: 0,
                  ),
                  _AnimatedHomeFeature(
                    icon: Icons.cut_rounded,
                    label: 'Slash',
                    detail: 'weeds',
                    phase: t,
                    delay: 0.6,
                  ),
                  _AnimatedHomeFeature(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Power',
                    detail: 'ups',
                    phase: t,
                    delay: 1.2,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 56,
          right: 56,
          top: 374,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xE0153B17),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDEB78), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xAA071808),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'SWIPE. SLASH. SAVE THE GARDEN!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -6,
          bottom: 134 + mascotBob,
          child: Transform.rotate(
            angle: sin(t * 1.9) * 0.025,
            child: Image.asset(
              _currentAvatar,
              width: 151,
              height: 182,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          right: -8,
          top: 356 + weedBob,
          child: Transform.rotate(
            angle: sin(t * 3.1) * 0.08,
            child: Image.asset(
              'assets/images/sprites/weed_leaf.png',
              width: 64,
              height: 72,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 438 + sin(t * 2.2 + 1.4) * 3,
          child: Transform.rotate(
            angle: -0.16 + sin(t * 2.5) * 0.025,
            child: Image.asset(
              'assets/images/sprites/weed_spike.png',
              width: 72,
              height: 80,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          left: 26,
          right: 26,
          top: 462,
          child: Transform.scale(
            scale: playPulse,
            child: _PrimaryButton(
              label: 'PLAY',
              icon: Icons.play_arrow_rounded,
              onPressed: () => _startRun(restartLevel: true),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _AnimatedHomeMenuTile(
                      icon: Icons.task_alt_rounded,
                      label: 'Missions',
                      onTap: _openUpgrades,
                      phase: t,
                      delay: 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnimatedHomeMenuTile(
                      icon: Icons.storefront_rounded,
                      label: 'Shop',
                      onTap: _openUpgrades,
                      phase: t,
                      delay: 0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnimatedHomeMenuTile(
                      icon: Icons.local_florist_rounded,
                      label: 'Garden',
                      onTap: _openUpgrades,
                      phase: t,
                      delay: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CurrencyChip(
                    asset: 'assets/images/icons/seed_coin.png',
                    value: _formatNumber(_seeds),
                    showPlus: true,
                  ),
                  const SizedBox(width: 8),
                  _CurrencyChip(
                    asset: 'assets/images/icons/sun_boost.png',
                    value: '$_sunDrops',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHomeAtmosphere(double t) {
    const specs = [
      (x: 28.0, y: 232.0, size: 18.0, delay: 0.0),
      (x: 342.0, y: 242.0, size: 15.0, delay: 1.0),
      (x: 78.0, y: 612.0, size: 14.0, delay: 2.1),
      (x: 318.0, y: 644.0, size: 17.0, delay: 3.0),
      (x: 210.0, y: 404.0, size: 12.0, delay: 4.0),
    ];

    return [
      for (final spec in specs)
        Positioned(
          left: spec.x + sin(t * 0.85 + spec.delay) * 7,
          top: spec.y + ((t * 18 + spec.delay * 23) % 36) - 18,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.35 + sin(t * 1.3 + spec.delay).abs() * 0.28,
              child: Transform.rotate(
                angle: t * 0.8 + spec.delay,
                child: Icon(
                  Icons.eco_rounded,
                  color: const Color(0xFFDFFF8A),
                  size: spec.size,
                  shadows: const [
                    Shadow(color: Color(0xAA245710), blurRadius: 5),
                  ],
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: 16,
        right: 16,
        top: 92,
        height: 170,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildHomeTopBar() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 350,
        child: Row(
          children: [
            _RoundIconButton(
              icon: Icons.settings_rounded,
              onPressed: _openUpgrades,
            ),
            const Spacer(),
            _CurrencyChip(
              asset: 'assets/images/icons/seed_coin.png',
              value: _formatNumber(_seeds),
              showPlus: true,
            ),
            const SizedBox(width: 8),
            _CurrencyChip(
              asset: 'assets/images/icons/sun_boost.png',
              value: '$_sunDrops',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeLogo() {
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 24,
            top: 76,
            child: Transform.rotate(
              angle: -0.12,
              child: Image.asset(
                'assets/images/sprites/blue_bell_bloom.png',
                width: 54,
                height: 54,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            right: 28,
            top: 78,
            child: Transform.rotate(
              angle: 0.14,
              child: Image.asset(
                'assets/images/sprites/pink_blossom_plant.png',
                width: 52,
                height: 52,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _OutlinedTitle(
                  text: 'Garden',
                  size: 76,
                  fill: Color(0xFF9AF044),
                  stroke: Color(0xFF17310F),
                  strokeWidth: 8,
                ),
                Transform.translate(
                  offset: const Offset(0, -14),
                  child: const _OutlinedTitle(
                    text: 'NINJA',
                    size: 72,
                    fill: Color(0xFFF9FAF3),
                    stroke: Color(0xFF17310F),
                    strokeWidth: 8,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFB937),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF55370E),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xAA2D1908),
                          blurRadius: 0,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'PLANT SLASH',
                      style: TextStyle(
                        color: Color(0xFF55370E),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedLayer() {
    return _DimmedPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Paused',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            label: 'RESUME',
            icon: Icons.play_arrow_rounded,
            onPressed: _resume,
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'HOME',
            icon: Icons.home_rounded,
            onPressed: () => setState(() => _phase = GamePhase.home),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsLayer() {
    final int stars = _lastRunWon ? (_lives >= 3 ? 3 : 2) : 1;
    return _DimmedPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _lastRunWon ? 'Level Complete' : 'Garden Saved',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (index) => Icon(
                Icons.star_rounded,
                color: index < stars
                    ? const Color(0xFFFFD84D)
                    : const Color(0xFF5F743F),
                size: 46,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ResultLine(label: 'Score', value: _formatNumber(_score)),
          _ResultLine(label: 'Weeds slashed', value: '$_weedsSlashed'),
          _ResultLine(label: 'Flowers protected', value: '$_flowersSaved'),
          _ResultLine(label: 'Max combo', value: 'x$_maxCombo'),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CurrencyChip(
                asset: 'assets/images/icons/seed_coin.png',
                value: '+$_rewardSeeds',
              ),
              const SizedBox(width: 10),
              _CurrencyChip(
                asset: 'assets/images/icons/star_reward.png',
                value: 'Best ${_formatNumber(_bestScore)}',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            label: 'NEXT LEVEL',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              _level += 1;
              _startRun(restartLevel: true);
            },
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'UPGRADES',
            icon: Icons.construction_rounded,
            onPressed: _openUpgrades,
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradesLayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0C2613).withValues(alpha: 0.72),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 18,
          child: Row(
            children: [
              _RoundIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => setState(() => _phase = GamePhase.home),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tools',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _CurrencyChip(
                asset: 'assets/images/icons/seed_coin.png',
                value: _formatNumber(_seeds),
              ),
            ],
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 86,
          bottom: 24,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _UpgradeTile(
                        asset: 'assets/images/icons/leaf_blade.png',
                        title: 'Leaf Blade',
                        body: 'Starter slash',
                        status: 'Equipped',
                        onTap: null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _UpgradeTile(
                        asset: 'assets/images/icons/bamboo_cutter.png',
                        title: 'Bamboo',
                        body: '+1 Water',
                        status: '120 seeds',
                        onTap: () => _buyCharge('water', 120),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _UpgradeTile(
                        asset: 'assets/images/icons/golden_shears.png',
                        title: 'Shears',
                        body: '+1 Sun',
                        status: '160 seeds',
                        onTap: () => _buyCharge('sun', 160),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _UpgradeTile(
                        asset: 'assets/images/icons/ice_freeze.png',
                        title: 'Frost Vine',
                        body: '+1 Ice',
                        status: '140 seeds',
                        onTap: () => _buyCharge('ice', 140),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _UpgradeTile(
                        asset: _avatarAssets[0],
                        title: 'Male Ninja',
                        body: 'Leaf hero',
                        status: _selectedAvatar == 0 ? 'Equipped' : 'Choose',
                        onTap: _selectedAvatar == 0
                            ? null
                            : () => _selectAvatar(0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _UpgradeTile(
                        asset: _avatarAssets[1],
                        title: 'Female Ninja',
                        body: 'Bloom hero',
                        status: _selectedAvatar == 1 ? 'Equipped' : 'Choose',
                        onTap: _selectedAvatar == 1
                            ? null
                            : () => _selectAvatar(1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xEEF7E9BC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF4C7E26),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        _currentAvatar,
                        width: 96,
                        height: 118,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bloom Guard',
                              style: TextStyle(
                                color: Color(0xFF234B18),
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Level up tools, bank seeds, and push for bigger combos.',
                              style: TextStyle(
                                color: Color(0xFF365D27),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _PrimaryButton(
                  label: 'PLAY LEVEL $_level',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _startRun(restartLevel: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SliceHalfClipper extends CustomClipper<Path> {
  const SliceHalfClipper({
    required this.cutAngle,
    required this.keepPositiveSide,
  });

  final double cutAngle;
  final bool keepPositiveSide;

  @override
  Path getClip(Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Offset cutLine = Offset(cos(cutAngle), sin(cutAngle));
    final Offset normal = Offset(-cutLine.dy, cutLine.dx);
    final Offset sideNormal = keepPositiveSide ? normal : -normal;
    final double span = max(size.width, size.height) * 2.4;
    final Offset p1 = center - cutLine * span;
    final Offset p2 = center + cutLine * span;
    final Offset p3 = p2 + sideNormal * span;
    final Offset p4 = p1 + sideNormal * span;

    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
  }

  @override
  bool shouldReclip(covariant SliceHalfClipper oldClipper) {
    return oldClipper.cutAngle != cutAngle ||
        oldClipper.keepPositiveSide != keepPositiveSide;
  }
}

class SliceEdgePainter extends CustomPainter {
  const SliceEdgePainter({required this.cutAngle, required this.opacity});

  final double cutAngle;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Offset cutLine = Offset(cos(cutAngle), sin(cutAngle));
    final double span = max(size.width, size.height) * 0.54;
    final Offset start = center - cutLine * span;
    final Offset end = center + cutLine * span;
    final Paint glow = Paint()
      ..color = const Color(0xFF9AFF56).withValues(alpha: opacity * 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    final Paint core = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.95)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(start, end, glow);
    canvas.drawLine(start, end, core);
  }

  @override
  bool shouldRepaint(covariant SliceEdgePainter oldDelegate) {
    return oldDelegate.cutAngle != cutAngle || oldDelegate.opacity != opacity;
  }
}

class SlashPainter extends CustomPainter {
  SlashPainter({required this.trails, required this.worldSize});

  final List<SlashTrail> trails;
  final Size worldSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (final trail in trails) {
      final double opacity = trail.life.clamp(0.0, 1.0);
      final Offset start = Offset(
        trail.start.dx / worldSize.width * size.width,
        trail.start.dy / worldSize.height * size.height,
      );
      final Offset end = Offset(
        trail.end.dx / worldSize.width * size.width,
        trail.end.dy / worldSize.height * size.height,
      );
      final Offset control = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2 - 24,
      );
      final Path path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

      final Paint glow = Paint()
        ..color = const Color(0xFF9AFF56).withValues(alpha: opacity * 0.45)
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final Paint core = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, glow);
      canvas.drawPath(path, core);
    }
  }

  @override
  bool shouldRepaint(covariant SlashPainter oldDelegate) {
    return oldDelegate.trails != trails;
  }
}

class _DimmedPanel extends StatelessWidget {
  const _DimmedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xEE193D16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8FD44B), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('primary-$label'),
      width: double.infinity,
      height: label == 'PLAY' ? 82 : 58,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF7A4B0E),
                blurRadius: 0,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: Color(0x88000000),
                blurRadius: 16,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFD8FF63),
                  Color(0xFF7FE339),
                  Color(0xFF42A622),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD760), width: 3.5),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 10,
                  right: 10,
                  top: 7,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (label == 'PLAY') ...[
                  const Positioned(
                    left: 22,
                    top: 23,
                    child: Icon(
                      Icons.spa_rounded,
                      color: Color(0xBBE8FF9A),
                      size: 32,
                    ),
                  ),
                  const Positioned(
                    right: 22,
                    top: 23,
                    child: Icon(
                      Icons.eco_rounded,
                      color: Color(0xBBE8FF9A),
                      size: 32,
                    ),
                  ),
                ],
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 34),
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: label == 'PLAY' ? 38 : 25,
                            fontWeight: FontWeight.w900,
                            shadows: const [
                              Shadow(
                                color: Color(0xAA17310F),
                                blurRadius: 2,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFB8E675), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _OutlinedTitle extends StatelessWidget {
  const _OutlinedTitle({
    required this.text,
    required this.size,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final String text;
  final double size;
  final Color fill;
  final Color stroke;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 0.88,
      letterSpacing: 0,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = stroke,
            shadows: const [
              Shadow(
                offset: Offset(0, 5),
                color: Color(0xAA071808),
                blurRadius: 0,
              ),
              Shadow(color: Color(0xFF071808), blurRadius: 10),
            ],
          ),
        ),
        Text(text, style: baseStyle.copyWith(color: fill)),
      ],
    );
  }
}

class _HomeFeature extends StatelessWidget {
  const _HomeFeature({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 102,
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xF7FFFDF2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF88C83E), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x661C420F),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
          BoxShadow(
            color: Color(0x99FFFFFF),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF58A91F), size: 29),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF245D18),
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                color: Color(0xFF315C24),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedHomeFeature extends StatelessWidget {
  const _AnimatedHomeFeature({
    required this.icon,
    required this.label,
    required this.detail,
    required this.phase,
    required this.delay,
  });

  final IconData icon;
  final String label;
  final String detail;
  final double phase;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final double float = sin(phase * 1.7 + delay) * 3;
    return Transform.translate(
      offset: Offset(0, float),
      child: Transform.scale(
        scale: 1 + sin(phase * 1.35 + delay).abs() * 0.018,
        child: _HomeFeature(icon: icon, label: label, detail: detail),
      ),
    );
  }
}

class _GardenPatch extends StatelessWidget {
  const _GardenPatch({
    required this.index,
    required this.asset,
    required this.damaged,
    required this.active,
  });

  final int index;
  final String asset;
  final bool damaged;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey(damaged ? 'garden-damage-$index' : 'garden-safe-$index'),
      width: 58,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 24,
              decoration: BoxDecoration(
                color: damaged
                    ? const Color(0xDD5A3219)
                    : const Color(0xDD2F6F24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: damaged
                      ? const Color(0xFFFFB35F)
                      : const Color(0xFFB7E96F),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (damaged
                                ? const Color(0xFFAA3D25)
                                : const Color(0xFF78D041))
                            .withValues(alpha: active ? 0.75 : 0.28),
                    blurRadius: active ? 18 : 8,
                    spreadRadius: active ? 2 : 0,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 9,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: active ? 1.14 : 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ColorFiltered(
                    colorFilter: damaged
                        ? const ColorFilter.mode(
                            Color(0xFF6B4A2B),
                            BlendMode.modulate,
                          )
                        : const ColorFilter.mode(
                            Colors.white,
                            BlendMode.modulate,
                          ),
                    child: Opacity(
                      opacity: damaged ? 0.58 : 1,
                      child: Image.asset(
                        asset,
                        width: damaged ? 42 : 50,
                        height: damaged ? 50 : 58,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (damaged)
                    const SizedBox(
                      width: 54,
                      height: 58,
                      child: CustomPaint(painter: GardenCrackPainter()),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GardenCrackPainter extends CustomPainter {
  const GardenCrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint shadow = Paint()
      ..color = const Color(0xAA371C0F)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    final Paint crack = Paint()
      ..color = const Color(0xFFFFD176)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.44)
      ..lineTo(size.width * 0.44, size.height * 0.52)
      ..lineTo(size.width * 0.35, size.height * 0.66)
      ..moveTo(size.width * 0.46, size.height * 0.52)
      ..lineTo(size.width * 0.68, size.height * 0.42)
      ..moveTo(size.width * 0.49, size.height * 0.56)
      ..lineTo(size.width * 0.72, size.height * 0.68);

    canvas.drawPath(path, shadow);
    canvas.drawPath(path, crack);
  }

  @override
  bool shouldRepaint(covariant GardenCrackPainter oldDelegate) => false;
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB67A35), Color(0xFF6D421C)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF6D584), width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0xAA3A220C),
              blurRadius: 0,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 9,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFFF3C2), size: 27),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  shadows: [
                    Shadow(
                      color: Color(0xAA1E1005),
                      blurRadius: 3,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedHomeMenuTile extends StatelessWidget {
  const _AnimatedHomeMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.phase,
    required this.delay,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double phase;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, sin(phase * 1.45 + delay) * 2),
      child: _MenuTile(icon: icon, label: label, onTap: onTap),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC163A19),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x996DCC45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFD4F792),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xCC163A19),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x996DCC45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD35A), size: 20),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xCC163A19),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0x996DCC45)),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.asset,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String asset;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = count > 0;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 92,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEBCB48) : const Color(0xDD153916),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? const Color(0xFFD9F28C) : const Color(0xFF536548),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: Image.asset(asset, fit: BoxFit.contain)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$label x$count',
                style: TextStyle(
                  color: active ? const Color(0xFF3C2C08) : Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.asset,
    required this.value,
    this.showPlus = false,
  });

  final String asset;
  final String value;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6224517),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF99CF58)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(asset, width: 24, height: 24),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (showPlus) ...[
            const SizedBox(width: 5),
            const Icon(
              Icons.add_circle,
              color: Color(0xFF9FFF45),
              size: 21,
              shadows: [Shadow(color: Color(0xAA17330D), blurRadius: 3)],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD7F0B6),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.asset,
    required this.title,
    required this.body,
    required this.status,
    required this.onTap,
  });

  final String asset;
  final String title;
  final String body;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 190,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xEEF7E9BC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4C7E26), width: 2),
        ),
        child: Column(
          children: [
            Expanded(child: Image.asset(asset, fit: BoxFit.contain)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF244E18),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF315B22),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: onTap == null
                    ? const Color(0xFF51A334)
                    : const Color(0xFFE9B334),
                borderRadius: BorderRadius.circular(8),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
