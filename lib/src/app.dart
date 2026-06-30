import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

enum GamePhase { home, playing, paused, results, upgrades, garden }

enum TargetType { weed, flower, bonus, reward }

enum TutorialStep { slashWeed, avoidFlowers, toughWeed, useIce, frozenSlash }

enum GardenTool { plant, water, clear, sun }

class MusicTrack {
  const MusicTrack({
    required this.title,
    required this.mood,
    required this.asset,
  });

  final String title;
  final String mood;
  final String asset;
}

class GardenPlantOption {
  const GardenPlantOption({
    required this.name,
    required this.asset,
    required this.seedCost,
    required this.points,
    required this.seedReward,
    required this.growDuration,
    required this.role,
  });

  final String name;
  final String asset;
  final int seedCost;
  final int points;
  final int seedReward;
  final Duration growDuration;
  final String role;
}

class GardenPlantRenderSpec {
  const GardenPlantRenderSpec({
    required this.width,
    required this.height,
    required this.bottom,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1,
  });

  final double width;
  final double height;
  final double bottom;
  final double offsetX;
  final double offsetY;
  final double scale;
}

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

class PlayerGardenPlot {
  PlayerGardenPlot({
    required this.id,
    required this.position,
    required this.unlockLevel,
    this.asset,
    this.plantIndex,
    this.plantedAt,
    this.readyAt,
    this.lastWateredDay,
    this.growth = 0,
    this.weed = false,
    this.watered = false,
    this.sparkle = 0,
  });

  final int id;
  final Offset position;
  final int unlockLevel;
  String? asset;
  int? plantIndex;
  DateTime? plantedAt;
  DateTime? readyAt;
  String? lastWateredDay;
  double growth;
  bool weed;
  bool watered;
  double sparkle;

  bool get planted => asset != null;
  bool get ready => planted && growth >= 1;

  int get growthStage {
    if (!planted) {
      return 0;
    }
    if (growth >= 1) {
      return 3;
    }
    if (growth >= 0.62) {
      return 2;
    }
    return 1;
  }
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _worldWidth = 390;
  static const double _worldHeight = 844;
  static const double _playerGardenWidth = 760;
  static const double _playerGardenHeight = 1260;
  static const double _gardenDamageLineY = _worldHeight - 106;
  static const double _minSlashSegment = 7;
  static const int _maxSlashTrails = 22;
  static const int _maxSliceShards = 20;
  static const Duration _minSfxGap = Duration(milliseconds: 42);
  static const Duration _sameSfxGap = Duration(milliseconds: 82);
  static const String _gardenSaveKey = 'garden_ninja_garden_v2';
  static const int _dailyWaterGrant = 3;
  static const int _dailySunGrant = 1;
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
  static const List<GardenPlantOption> _gardenPlantOptions = [
    GardenPlantOption(
      name: 'Daisy',
      asset: 'assets/images/sprites/flower_daisy.png',
      seedCost: 40,
      points: 80,
      seedReward: 46,
      growDuration: Duration(hours: 4),
      role: 'Quick bloom',
    ),
    GardenPlantOption(
      name: 'Blue Bell',
      asset: 'assets/images/sprites/blue_bell_bloom.png',
      seedCost: 55,
      points: 110,
      seedReward: 62,
      growDuration: Duration(hours: 8),
      role: '+1 water',
    ),
    GardenPlantOption(
      name: 'Pink Bloom',
      asset: 'assets/images/sprites/pink_blossom_plant.png',
      seedCost: 75,
      points: 150,
      seedReward: 82,
      growDuration: Duration(hours: 12),
      role: 'Balanced',
    ),
    GardenPlantOption(
      name: 'Cherry',
      asset: 'assets/images/sprites/cherry_blossom_sapling.png',
      seedCost: 95,
      points: 200,
      seedReward: 110,
      growDuration: Duration(hours: 20),
      role: '+1 sun',
    ),
    GardenPlantOption(
      name: 'Blossom Bush',
      asset: 'assets/images/sprites/pink_blossom_bush.png',
      seedCost: 120,
      points: 260,
      seedReward: 135,
      growDuration: Duration(hours: 24),
      role: 'Big bloom',
    ),
    GardenPlantOption(
      name: 'Shield Flower',
      asset: 'assets/images/sprites/flower_shield.png',
      seedCost: 100,
      points: 230,
      seedReward: 120,
      growDuration: Duration(hours: 18),
      role: 'Blocks weeds',
    ),
  ];
  static const List<GardenPlantRenderSpec> _gardenPlantRenderSpecs = [
    GardenPlantRenderSpec(width: 68, height: 76, bottom: 40),
    GardenPlantRenderSpec(width: 58, height: 78, bottom: 39),
    GardenPlantRenderSpec(width: 58, height: 72, bottom: 39),
    GardenPlantRenderSpec(width: 62, height: 78, bottom: 38),
    GardenPlantRenderSpec(width: 84, height: 74, bottom: 38, scale: 0.94),
    GardenPlantRenderSpec(width: 68, height: 80, bottom: 39),
  ];
  static const List<String> _playerGardenWeedAssets = [
    'assets/images/sprites/weed_leaf.png',
    'assets/images/sprites/weed_seed_chomper.png',
    'assets/images/sprites/weed_thorn_sprout.png',
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
  static const List<MusicTrack> _musicTracks = [
    MusicTrack(
      title: 'Weed Invasion',
      mood: 'Action',
      asset: 'audio/music/weed_invasion.ogg',
    ),
    MusicTrack(
      title: 'Ninja Bloom',
      mood: 'Playful',
      asset: 'audio/music/ninja_bloom.ogg',
    ),
    MusicTrack(
      title: 'Garden Groove',
      mood: 'Sunny',
      asset: 'audio/music/garden_groove.ogg',
    ),
    MusicTrack(
      title: 'Blossom Rush',
      mood: 'Fast',
      asset: 'audio/music/blossom_rush.ogg',
    ),
    MusicTrack(
      title: 'Moonlit Greenhouse',
      mood: 'Calm',
      asset: 'audio/music/moonlit_greenhouse.ogg',
    ),
  ];
  static const String _sfxCrispLeaf = 'audio/sfx/crisp_leaf_cut.ogg';
  static const String _sfxBambooBlade = 'audio/sfx/bamboo_blade_slice.ogg';
  static const String _sfxWetVine = 'audio/sfx/wet_vine_chop.ogg';
  static const String _sfxComboSpark = 'audio/sfx/combo_spark_slash.ogg';
  static const String _sfxFrozenWeed = 'audio/sfx/frozen_weed_shatter.ogg';
  static const List<String> _sfxAssets = [
    _sfxCrispLeaf,
    _sfxBambooBlade,
    _sfxWetVine,
    _sfxComboSpark,
    _sfxFrozenWeed,
  ];

  final Random _random = Random();
  final List<GardenTarget> _targets = [];
  final List<SliceShard> _shards = [];
  final List<SlashTrail> _slashes = [];
  final List<FloatingBurst> _bursts = [];
  final List<PlayerGardenPlot> _playerGardenPlots = [
    PlayerGardenPlot(
      id: 0,
      position: const Offset(146, 230),
      unlockLevel: 1,
      asset: 'assets/images/sprites/flower_daisy.png',
      plantIndex: 0,
      growth: 1,
      sparkle: 0.7,
    ),
    PlayerGardenPlot(
      id: 1,
      position: const Offset(330, 265),
      unlockLevel: 1,
      asset: 'assets/images/sprites/blue_bell_bloom.png',
      plantIndex: 1,
      growth: 0.74,
      watered: true,
    ),
    PlayerGardenPlot(
      id: 2,
      position: const Offset(530, 250),
      unlockLevel: 1,
      weed: true,
    ),
    PlayerGardenPlot(
      id: 3,
      position: const Offset(210, 430),
      unlockLevel: 1,
      asset: 'assets/images/sprites/pink_blossom_plant.png',
      plantIndex: 2,
      growth: 0.42,
    ),
    PlayerGardenPlot(id: 4, position: const Offset(410, 455), unlockLevel: 1),
    PlayerGardenPlot(
      id: 5,
      position: const Offset(600, 470),
      unlockLevel: 1,
      asset: 'assets/images/sprites/cherry_blossom_sapling.png',
      plantIndex: 3,
      growth: 0.58,
    ),
    PlayerGardenPlot(id: 6, position: const Offset(135, 640), unlockLevel: 1),
    PlayerGardenPlot(
      id: 7,
      position: const Offset(350, 650),
      unlockLevel: 1,
      asset: 'assets/images/sprites/flower_shield.png',
      plantIndex: 5,
      growth: 0.2,
    ),
    PlayerGardenPlot(
      id: 8,
      position: const Offset(570, 675),
      unlockLevel: 1,
      weed: true,
    ),
    PlayerGardenPlot(id: 9, position: const Offset(198, 865), unlockLevel: 2),
    PlayerGardenPlot(id: 10, position: const Offset(388, 890), unlockLevel: 2),
    PlayerGardenPlot(id: 11, position: const Offset(590, 905), unlockLevel: 2),
    PlayerGardenPlot(id: 12, position: const Offset(160, 1085), unlockLevel: 3),
    PlayerGardenPlot(id: 13, position: const Offset(360, 1110), unlockLevel: 3),
    PlayerGardenPlot(id: 14, position: const Offset(585, 1082), unlockLevel: 3),
  ];

  late final Ticker _ticker;
  late final AudioPlayer _musicPlayer;
  late final TransformationController _gardenMapController;
  SharedPreferences? _prefs;
  final Map<String, AudioPool> _sfxPools = {};
  final AudioContext _musicAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.gain,
    respectSilence: false,
  ).build();
  final AudioContext _sfxAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: false,
  ).build();
  final Map<String, DateTime> _lastSfxPlayedAt = {};
  Duration _lastElapsed = Duration.zero;
  DateTime _lastSfxPlayed = DateTime.fromMillisecondsSinceEpoch(0);
  GamePhase _phase = GamePhase.home;
  GamePhase _phaseBeforePause = GamePhase.home;
  GardenTool _gardenTool = GardenTool.water;

  int _nextTargetId = 1;
  int _level = 1;
  int _gardenLevel = 1;
  int _gardenHarvests = 0;
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
  int _gardenPoints = 0;
  int _rewardSeeds = 0;
  int _selectedAvatar = 0;
  int _selectedMusicTrack = 0;
  int _selectedGardenPlant = 0;
  int? _gardenNurseryPlotId;
  int _gardenLoginStreak = 1;
  bool _lastRunWon = false;
  bool _musicEnabled = true;
  bool _sfxEnabled = true;
  bool _audioReady = false;
  bool _musicStartQueued = false;
  bool _tutorialMode = false;
  bool _tutorialMistake = false;
  bool _gardenSaveLoaded = false;
  TutorialStep _tutorialStep = TutorialStep.slashWeed;
  double _spawnTimer = 0;
  double _timeLeft = 60;
  double _iceTime = 0;
  double _sunTime = 0;
  double _flowerPenaltyCooldown = 0;
  double _gardenDamageFlash = 0;
  double _gardenDamageCooldown = 0;
  double _gardenWeedTimer = 18;
  double _gardenMessageLife = 0;
  double _motionTime = 0;
  Offset? _lastSlashPoint;
  String _gardenMessage = 'Tap empty plot to open nursery';
  String? _gardenLastLoginDay;

  int get _goalWeeds => 18 + (_level * 4);

  String get _currentBackground =>
      _backgrounds[(_level - 1) % _backgrounds.length];

  String get _currentAvatar => _avatarAssets[_selectedAvatar];

  MusicTrack get _currentMusicTrack => _musicTracks[_selectedMusicTrack];

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

  DateTime get _gardenNow => DateTime.now();

  String _dayKey(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _durationLabel(Duration duration) {
    if (duration.isNegative || duration.inSeconds <= 0) {
      return 'Ready';
    }
    if (duration.inDays >= 1) {
      final int hours = duration.inHours % 24;
      return hours == 0
          ? '${duration.inDays}d'
          : '${duration.inDays}d ${hours}h';
    }
    if (duration.inHours >= 1) {
      final int minutes = duration.inMinutes % 60;
      return minutes == 0
          ? '${duration.inHours}h'
          : '${duration.inHours}h ${minutes}m';
    }
    return '${max(1, duration.inMinutes)}m';
  }

  Future<void> _loadGardenSave() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_gardenSaveKey);
    if (!mounted) {
      return;
    }

    setState(() {
      _prefs = prefs;
      if (raw != null) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            _applyGardenSave(decoded);
          }
        } catch (_) {
          // Bad local save data should never block the Garden from opening.
        }
      }
      _gardenSaveLoaded = true;
      _refreshAllGardenPlots(_gardenNow);
      _syncDailyGarden(_gardenNow, announce: false);
    });
    _queueGardenSave();
  }

  void _applyGardenSave(Map<String, dynamic> data) {
    _seeds = (data['seeds'] as num?)?.toInt() ?? _seeds;
    _waterCharges = (data['waterCharges'] as num?)?.toInt() ?? _waterCharges;
    _sunDrops = (data['sunDrops'] as num?)?.toInt() ?? _sunDrops;
    _gardenPoints = (data['gardenPoints'] as num?)?.toInt() ?? _gardenPoints;
    _gardenLevel = (data['gardenLevel'] as num?)?.toInt() ?? _gardenLevel;
    _gardenHarvests =
        (data['gardenHarvests'] as num?)?.toInt() ?? _gardenHarvests;
    _selectedGardenPlant =
        (data['selectedGardenPlant'] as num?)?.toInt() ?? _selectedGardenPlant;
    _gardenLoginStreak =
        (data['gardenLoginStreak'] as num?)?.toInt() ?? _gardenLoginStreak;
    _gardenLastLoginDay = data['gardenLastLoginDay'] as String?;

    final Object? plots = data['plots'];
    if (plots is List) {
      for (final Object? rawPlot in plots) {
        if (rawPlot is! Map<String, dynamic>) {
          continue;
        }
        final int? id = (rawPlot['id'] as num?)?.toInt();
        if (id == null || id < 0 || id >= _playerGardenPlots.length) {
          continue;
        }
        final PlayerGardenPlot plot = _playerGardenPlots[id];
        final int? plantIndex = (rawPlot['plantIndex'] as num?)?.toInt();
        if (plantIndex == null) {
          plot.asset = null;
          plot.plantIndex = null;
          plot.plantedAt = null;
          plot.readyAt = null;
          plot.lastWateredDay = null;
          plot.growth = 0;
          plot.watered = false;
        } else {
          final GardenPlantOption option = _gardenPlantOptionAt(plantIndex);
          plot.asset = option.asset;
          plot.plantIndex = plantIndex;
          plot.plantedAt = _dateFromMs(rawPlot['plantedAt']);
          plot.readyAt = _dateFromMs(rawPlot['readyAt']);
          plot.lastWateredDay = rawPlot['lastWateredDay'] as String?;
          plot.growth = ((rawPlot['growth'] as num?)?.toDouble() ?? plot.growth)
              .clamp(0.0, 1.0);
          plot.watered = rawPlot['watered'] == true;
        }
        plot.weed = rawPlot['weed'] == true;
        plot.sparkle = 0;
      }
    }
  }

  DateTime? _dateFromMs(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  Map<String, dynamic> _gardenSavePayload() {
    return {
      'version': 2,
      'seeds': _seeds,
      'waterCharges': _waterCharges,
      'sunDrops': _sunDrops,
      'gardenPoints': _gardenPoints,
      'gardenLevel': _gardenLevel,
      'gardenHarvests': _gardenHarvests,
      'selectedGardenPlant': _selectedGardenPlant,
      'gardenLoginStreak': _gardenLoginStreak,
      'gardenLastLoginDay': _gardenLastLoginDay,
      'plots': [
        for (final plot in _playerGardenPlots)
          {
            'id': plot.id,
            'plantIndex': plot.plantIndex,
            'plantedAt': plot.plantedAt?.millisecondsSinceEpoch,
            'readyAt': plot.readyAt?.millisecondsSinceEpoch,
            'lastWateredDay': plot.lastWateredDay,
            'growth': plot.growth,
            'watered': plot.watered,
            'weed': plot.weed,
          },
      ],
    };
  }

  void _queueGardenSave() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null || !_gardenSaveLoaded) {
      return;
    }
    unawaited(
      prefs.setString(_gardenSaveKey, jsonEncode(_gardenSavePayload())),
    );
  }

  void _syncDailyGarden(DateTime now, {required bool announce}) {
    final String today = _dayKey(now);
    if (_gardenLastLoginDay == today) {
      return;
    }

    final String? previousDay = _gardenLastLoginDay;
    final bool continuedStreak =
        previousDay == _dayKey(now.subtract(const Duration(days: 1)));
    _gardenLoginStreak = previousDay == null || continuedStreak
        ? _gardenLoginStreak + (previousDay == null ? 0 : 1)
        : 1;
    _gardenLastLoginDay = today;
    _waterCharges = min(12, _waterCharges + _dailyWaterGrant);
    _sunDrops = min(12, _sunDrops + _dailySunGrant);

    for (final plot in _playerGardenPlots) {
      if (plot.planted) {
        plot.watered = plot.lastWateredDay == today;
      }
    }

    if (previousDay != null) {
      _spawnNeglectWeeds();
    }
    if (announce) {
      _gardenMessage =
          'Daily supplies: +$_dailyWaterGrant water, +$_dailySunGrant sun';
      _gardenMessageLife = 3.0;
    }
    _queueGardenSave();
  }

  void _spawnNeglectWeeds() {
    final int shieldCount = _playerGardenPlots
        .where(
          (plot) =>
              plot.planted &&
              plot.plantIndex != null &&
              _gardenPlantOptionAt(plot.plantIndex!).name == 'Shield Flower',
        )
        .length;
    final int targetWeeds = max(0, _maxGardenWeeds - (shieldCount > 0 ? 1 : 0));
    for (int i = 0; i < targetWeeds; i += 1) {
      if (_activeGardenWeeds >= targetWeeds || _random.nextDouble() >= 0.55) {
        break;
      }
      _spawnPlayerGardenWeed(showMessage: false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _musicPlayer = AudioPlayer(playerId: 'garden-ninja-music');
    _gardenMapController = TransformationController(
      Matrix4.translationValues(-120.0, -200.0, 0.0),
    );
    _ticker = createTicker(_tick)..start();
    _primeAudio();
    unawaited(_loadGardenSave());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _gardenMapController.dispose();
    unawaited(_musicPlayer.stop());
    unawaited(_musicPlayer.dispose());
    for (final pool in _sfxPools.values) {
      unawaited(pool.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_musicEnabled && _phase != GamePhase.paused) {
          unawaited(_musicPlayer.resume());
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_musicPlayer.pause());
        break;
      case AppLifecycleState.detached:
        unawaited(_musicPlayer.stop());
        break;
    }
  }

  Future<void> _primeAudio() async {
    try {
      await _musicPlayer.setAudioContext(_musicAudioContext);
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(0.42);
      _audioReady = true;
      await _playSelectedMusic();
    } catch (_) {
      _musicStartQueued = true;
    }

    for (final asset in _sfxAssets) {
      try {
        _sfxPools[asset] = await AudioPool.create(
          source: AssetSource(asset),
          minPlayers: 1,
          maxPlayers: 3,
          audioContext: _sfxAudioContext,
        );
      } catch (_) {}
    }
  }

  Future<void> _playSelectedMusic() async {
    if (!_musicEnabled) {
      await _musicPlayer.stop();
      return;
    }

    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.play(
        AssetSource(_currentMusicTrack.asset),
        volume: _phase == GamePhase.playing ? 0.46 : 0.34,
        ctx: _musicAudioContext,
      );
      _audioReady = true;
      _musicStartQueued = false;
    } catch (_) {
      _musicStartQueued = true;
    }
  }

  void _ensureMusicStarted() {
    if (!_musicEnabled) {
      return;
    }
    if (!_audioReady || _musicStartQueued) {
      unawaited(_playSelectedMusic());
      return;
    }
    unawaited(
      (() async {
        try {
          await _musicPlayer.setVolume(
            _phase == GamePhase.playing ? 0.46 : 0.34,
          );
          await _musicPlayer.resume();
        } catch (_) {
          _musicStartQueued = true;
        }
      })(),
    );
  }

  void _playSfx(String asset, {double volume = 0.78}) {
    if (!_sfxEnabled) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastAssetPlay = _lastSfxPlayedAt[asset];
    if (now.difference(_lastSfxPlayed) < _minSfxGap ||
        (lastAssetPlay != null &&
            now.difference(lastAssetPlay) < _sameSfxGap)) {
      return;
    }
    _lastSfxPlayed = now;
    _lastSfxPlayedAt[asset] = now;

    final AudioPool? pool = _sfxPools[asset];
    if (pool == null) {
      return;
    }

    unawaited(
      (() async {
        try {
          await pool.start(volume: volume);
        } catch (_) {}
      })(),
    );
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

    if (_phase == GamePhase.home || _phase == GamePhase.garden) {
      setState(() {
        _motionTime += dt;
        if (_phase == GamePhase.garden) {
          _stepPlayerGarden(dt);
        }
      });
    }
  }

  void _startRun({bool restartLevel = false}) {
    _ensureMusicStarted();
    setState(() {
      if (!restartLevel) {
        _level = max(1, _level);
      }
      _tutorialMode = false;
      _tutorialMistake = false;
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
    unawaited(_musicPlayer.setVolume(0.46));
  }

  void _step(double dt) {
    if (_tutorialMode) {
      _stepTutorial(dt);
      return;
    }

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

  void _stepTutorial(double dt) {
    _iceTime = max(0, _iceTime - dt);
    _sunTime = max(0, _sunTime - dt);
    _flowerPenaltyCooldown = max(0, _flowerPenaltyCooldown - dt);
    _gardenDamageFlash = max(0, _gardenDamageFlash - dt * 2.4);
    _gardenDamageCooldown = max(0, _gardenDamageCooldown - dt);

    final bool movingLesson =
        _tutorialStep == TutorialStep.useIce ||
        _tutorialStep == TutorialStep.frozenSlash;
    final bool iceActive = _iceTime > 0;
    final double speedScale = movingLesson ? (iceActive ? 0.08 : 0.7) : 0.0;
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
      }

      if (target.position.dy > _gardenDamageLineY) {
        _targets.remove(target);
        if (target.type == TargetType.weed) {
          _damageGardenFromWeed(target);
          _tutorialMistake = true;
          if (_lives <= 0) {
            _restartTutorialStep();
            return;
          }
        }
      }
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

  void _startTutorial() {
    _ensureMusicStarted();
    setState(() {
      _tutorialMode = true;
      _tutorialStep = TutorialStep.slashWeed;
      _tutorialMistake = false;
      _phase = GamePhase.playing;
      _score = 0;
      _combo = 0;
      _maxCombo = 0;
      _lives = 3;
      _gardenDamage = 0;
      _weedsSlashed = 0;
      _flowersSaved = 0;
      _timeLeft = 99;
      _iceTime = 0;
      _sunTime = 0;
      _iceCharges = max(_iceCharges, 1);
      _lastSlashPoint = null;
      _targets.clear();
      _shards.clear();
      _slashes.clear();
      _bursts.clear();
      _spawnTutorialTargets();
    });
    unawaited(_musicPlayer.setVolume(0.46));
  }

  void _spawnTutorialTargets() {
    _targets.clear();
    switch (_tutorialStep) {
      case TutorialStep.slashWeed:
        _targets.add(
          _tutorialTarget(
            type: TargetType.weed,
            asset: 'assets/images/sprites/weed_leaf.png',
            position: const Offset(196, 390),
            size: 88,
            cutsRequired: 1,
          ),
        );
      case TutorialStep.avoidFlowers:
        _targets
          ..add(
            _tutorialTarget(
              type: TargetType.flower,
              asset: 'assets/images/sprites/pink_blossom_plant.png',
              position: const Offset(132, 474),
              size: 86,
              cutsRequired: 1,
            ),
          )
          ..add(
            _tutorialTarget(
              type: TargetType.weed,
              asset: 'assets/images/sprites/weed_spike.png',
              position: const Offset(270, 474),
              size: 86,
              cutsRequired: 1,
            ),
          );
        _flowersSaved = max(_flowersSaved, 1);
      case TutorialStep.toughWeed:
        _targets.add(
          _tutorialTarget(
            type: TargetType.weed,
            asset: 'assets/images/sprites/weed_vine_gobbler.png',
            position: const Offset(196, 418),
            size: 104,
            cutsRequired: 3,
          ),
        );
      case TutorialStep.useIce:
      case TutorialStep.frozenSlash:
        _iceCharges = max(_iceCharges, 1);
        _targets
          ..add(
            _tutorialTarget(
              type: TargetType.weed,
              asset: 'assets/images/sprites/weed_seed_chomper.png',
              position: const Offset(116, 300),
              velocity: const Offset(8, 58),
              size: 82,
              cutsRequired: 1,
            ),
          )
          ..add(
            _tutorialTarget(
              type: TargetType.weed,
              asset: 'assets/images/sprites/weed_bramble_bulb.png',
              position: const Offset(196, 260),
              velocity: const Offset(-3, 54),
              size: 92,
              cutsRequired: 2,
            ),
          )
          ..add(
            _tutorialTarget(
              type: TargetType.weed,
              asset: 'assets/images/sprites/weed_thorn_sprout.png',
              position: const Offset(284, 312),
              velocity: const Offset(-8, 56),
              size: 82,
              cutsRequired: 1,
            ),
          );
    }
  }

  GardenTarget _tutorialTarget({
    required TargetType type,
    required String asset,
    required Offset position,
    required double size,
    required int cutsRequired,
    Offset velocity = Offset.zero,
  }) {
    return GardenTarget(
      id: _nextTargetId++,
      type: type,
      asset: asset,
      position: position,
      velocity: velocity,
      size: size,
      radius: size * 0.42,
      spin: 0,
      cutsRequired: cutsRequired,
    );
  }

  void _restartTutorialStep() {
    _lives = 3;
    _gardenDamage = 0;
    _iceTime = 0;
    _lastSlashPoint = null;
    _targets.clear();
    _shards.clear();
    _slashes.clear();
    _spawnTutorialTargets();
  }

  void _handleSlash(Offset localPosition, Size size) {
    if (_phase != GamePhase.playing || !mounted) {
      return;
    }
    setState(() {
      if (_phase != GamePhase.playing) {
        return;
      }
      _handleSlashInState(localPosition, size);
    });
  }

  void _handleSlashInState(Offset localPosition, Size size) {
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
    if (_lastSlashPoint == null || !mounted) {
      return;
    }
    setState(() {
      _lastSlashPoint = null;
    });
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
        if (_iceTime > 0) {
          _playSfx(_sfxFrozenWeed, volume: 0.86);
        } else if (_combo > 1 && _combo % 5 == 0) {
          _playSfx(_sfxComboSpark, volume: 0.82);
        } else if (target.maxCuts >= 3) {
          _playSfx(_sfxWetVine, volume: 0.78);
        } else if (defeated && target.maxCuts == 1) {
          _playSfx(_sfxCrispLeaf, volume: 0.75);
        } else {
          _playSfx(_sfxBambooBlade, volume: 0.78);
        }
        if (defeated) {
          _targets.remove(target);
          _weedsSlashed += 1;
          _addBurst(target.position, '+$earned Weed', const Color(0xFFEFFF94));
          if (_tutorialMode) {
            _handleTutorialWeedDefeated();
          } else if (_weedsSlashed >= _goalWeeds) {
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
        _playSfx(_sfxCrispLeaf, volume: 0.56);
        if (_tutorialMode) {
          _tutorialMistake = true;
          _addBurst(target.position, 'Avoid flowers!', const Color(0xFFFF9FCA));
          return;
        }
        _combo = 0;
        _score = max(0, _score - 150);
        _flowersSaved = max(0, _flowersSaved - 1);
        _flowerPenaltyCooldown = 0.45;
        _addBurst(target.position, '-150 Plant', const Color(0xFFFF9FCA));
      case TargetType.bonus:
        _targets.remove(target);
        _playSfx(_sfxComboSpark, volume: 0.78);
        _combo += 1;
        _maxCombo = max(_maxCombo, _combo);
        _score += 320 + (_combo * 10);
        _waterCharges = min(5, _waterCharges + 1);
        _addBurst(target.position, '+Nice +Water', const Color(0xFF86E7FF));
      case TargetType.reward:
        _targets.remove(target);
        _playSfx(_sfxComboSpark, volume: 0.7);
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

  void _handleTutorialWeedDefeated() {
    final bool anyWeedsLeft = _targets.any((t) => t.type == TargetType.weed);
    switch (_tutorialStep) {
      case TutorialStep.slashWeed:
        _advanceTutorial(TutorialStep.avoidFlowers);
      case TutorialStep.avoidFlowers:
        if (!anyWeedsLeft) {
          _advanceTutorial(TutorialStep.toughWeed);
        }
      case TutorialStep.toughWeed:
        _advanceTutorial(TutorialStep.useIce);
      case TutorialStep.useIce:
        if (!anyWeedsLeft) {
          _advanceTutorial(TutorialStep.frozenSlash);
        }
      case TutorialStep.frozenSlash:
        if (!anyWeedsLeft) {
          _completeTutorial();
        }
    }
  }

  void _advanceTutorial(TutorialStep step) {
    _tutorialStep = step;
    _tutorialMistake = false;
    _iceTime = step == TutorialStep.frozenSlash ? _iceTime : 0;
    _lastSlashPoint = null;
    _targets.clear();
    _shards.clear();
    _slashes.clear();
    _spawnTutorialTargets();
  }

  void _completeTutorial() {
    _tutorialMode = false;
    _tutorialMistake = false;
    _lastSlashPoint = null;
    _level = max(_level, 1);
    _startRun(restartLevel: true);
  }

  void _activateWater() {
    if (_phase != GamePhase.playing || _waterCharges <= 0) {
      return;
    }
    _playSfx(_sfxWetVine, volume: 0.86);
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
    _playSfx(_sfxComboSpark, volume: 0.8);
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
    _playSfx(_sfxFrozenWeed, volume: 0.82);
    setState(() {
      _iceCharges -= 1;
      _iceTime = max(_iceTime, 6.5);
      if (_tutorialMode && _tutorialStep == TutorialStep.useIce) {
        _tutorialStep = TutorialStep.frozenSlash;
        _tutorialMistake = false;
      }
      _addBurst(
        const Offset(_worldWidth / 2, 220),
        'Freeze!',
        const Color(0xFF8EF5FF),
      );
    });
  }

  void _finishRun({required bool won}) {
    if (_phase != GamePhase.playing) {
      return;
    }
    unawaited(_musicPlayer.setVolume(0.34));
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
    unawaited(_musicPlayer.setVolume(0.24));
  }

  void _resume() {
    if (_phase != GamePhase.paused) {
      return;
    }
    setState(() {
      _phase = _phaseBeforePause;
    });
    unawaited(_musicPlayer.setVolume(0.46));
  }

  void _openUpgrades() {
    _ensureMusicStarted();
    setState(() {
      _phase = GamePhase.upgrades;
    });
    unawaited(_musicPlayer.setVolume(0.32));
  }

  void _openGarden() {
    _ensureMusicStarted();
    setState(() {
      final DateTime now = _gardenNow;
      _syncDailyGarden(now, announce: true);
      _refreshAllGardenPlots(now);
      _phase = GamePhase.garden;
      _gardenTool = GardenTool.plant;
      if (_gardenMessageLife <= 0) {
        _gardenMessage = 'Tap empty plot to open nursery';
        _gardenMessageLife = 2.4;
      }
      _gardenWeedTimer = max(_gardenWeedTimer, 12);
    });
    _queueGardenSave();
    unawaited(_musicPlayer.setVolume(0.3));
  }

  void _goHome() {
    setState(() {
      _phase = GamePhase.home;
      _tutorialMode = false;
    });
    unawaited(_musicPlayer.setVolume(0.34));
  }

  bool _isGardenPlotUnlocked(PlayerGardenPlot plot) {
    return plot.unlockLevel <= _gardenLevel;
  }

  int get _gardenExpandCost => 260 + ((_gardenLevel - 1) * 180);

  int get _activeGardenWeeds => _playerGardenPlots
      .where((plot) => _isGardenPlotUnlocked(plot) && plot.weed)
      .length;

  int get _maxGardenWeeds => min(3, 1 + _gardenLevel);

  GardenPlantOption get _selectedGardenPlantOption =>
      _gardenPlantOptionAt(_selectedGardenPlant);

  PlayerGardenPlot? get _gardenNurseryPlot {
    final int? id = _gardenNurseryPlotId;
    if (id == null) {
      return null;
    }
    for (final plot in _playerGardenPlots) {
      if (plot.id == id) {
        return plot;
      }
    }
    return null;
  }

  GardenPlantOption _gardenPlantOptionAt(int index) {
    final int safeIndex = index
        .clamp(0, _gardenPlantOptions.length - 1)
        .toInt();
    return _gardenPlantOptions[safeIndex];
  }

  GardenPlantOption _plantOptionForPlot(PlayerGardenPlot plot) {
    if (plot.plantIndex != null) {
      return _gardenPlantOptionAt(plot.plantIndex!);
    }
    final int assetIndex = _gardenPlantOptions.indexWhere(
      (option) => option.asset == plot.asset,
    );
    return _gardenPlantOptionAt(assetIndex < 0 ? 0 : assetIndex);
  }

  GardenPlantRenderSpec _plantRenderSpecForPlot(PlayerGardenPlot plot) {
    final int index = (plot.plantIndex ?? 0)
        .clamp(0, _gardenPlantRenderSpecs.length - 1)
        .toInt();
    return _gardenPlantRenderSpecs[index];
  }

  int _gardenSeedRewardFor(GardenPlantOption option) {
    return option.seedReward;
  }

  bool _isWateredToday(PlayerGardenPlot plot, DateTime now) {
    return plot.lastWateredDay == _dayKey(now);
  }

  void _refreshAllGardenPlots(DateTime now) {
    for (final plot in _playerGardenPlots) {
      _refreshGardenPlot(plot, now);
    }
  }

  void _refreshGardenPlot(PlayerGardenPlot plot, DateTime now) {
    if (!plot.planted) {
      plot.growth = 0;
      plot.watered = false;
      plot.plantedAt = null;
      plot.readyAt = null;
      plot.lastWateredDay = null;
      return;
    }

    final GardenPlantOption option = _plantOptionForPlot(plot);
    plot.plantedAt ??= now.subtract(
      Duration(
        milliseconds: (option.growDuration.inMilliseconds * plot.growth)
            .round(),
      ),
    );
    plot.readyAt ??= plot.plantedAt!.add(option.growDuration);
    plot.watered = _isWateredToday(plot, now);

    final int totalMs = max(1, option.growDuration.inMilliseconds);
    final int remainingMs = plot.readyAt!.difference(now).inMilliseconds;
    final double progress = (1 - (remainingMs / totalMs)).clamp(0.08, 1.0);
    plot.growth = plot.watered || progress < 0.92
        ? progress
        : min(progress, 0.92);
  }

  Duration _remainingGardenTime(PlayerGardenPlot plot, DateTime now) {
    final DateTime? readyAt = plot.readyAt;
    if (readyAt == null) {
      return Duration.zero;
    }
    return readyAt.difference(now);
  }

  String _gardenPlotStatus(PlayerGardenPlot plot, DateTime now) {
    if (plot.weed) {
      return 'Weed!';
    }
    if (!plot.planted) {
      return _gardenTool == GardenTool.plant ? 'Plant here' : 'Empty plot';
    }
    if (plot.ready) {
      return 'Collect';
    }
    if (!_isWateredToday(plot, now)) {
      return 'Water me';
    }
    return _durationLabel(_remainingGardenTime(plot, now));
  }

  void _stepPlayerGarden(double dt) {
    final DateTime now = _gardenNow;
    _syncDailyGarden(now, announce: false);
    _refreshAllGardenPlots(now);
    _gardenMessageLife = max(0, _gardenMessageLife - dt);
    _gardenWeedTimer -= dt;

    for (final plot in _playerGardenPlots) {
      plot.sparkle = max(0, plot.sparkle - dt * 1.8);
    }

    if (_gardenWeedTimer <= 0) {
      if (_activeGardenWeeds < _maxGardenWeeds) {
        _spawnPlayerGardenWeed();
      }
      _gardenWeedTimer = 18.0 + _random.nextDouble() * 14.0;
    }
  }

  void _spawnPlayerGardenWeed({bool showMessage = true}) {
    if (_activeGardenWeeds >= _maxGardenWeeds) {
      return;
    }
    final emptyCandidates = _playerGardenPlots
        .where(
          (plot) => _isGardenPlotUnlocked(plot) && !plot.weed && !plot.planted,
        )
        .toList();
    final growingCandidates = _playerGardenPlots
        .where((plot) => _isGardenPlotUnlocked(plot) && !plot.weed)
        .toList();
    final candidates = emptyCandidates.isNotEmpty
        ? emptyCandidates
        : growingCandidates;
    if (candidates.isEmpty) {
      return;
    }
    final plot = candidates[_random.nextInt(candidates.length)];
    plot.weed = true;
    plot.sparkle = 1;
    if (showMessage) {
      _gardenMessage = 'Weed popped up!';
      _gardenMessageLife = 2.2;
    }
    _queueGardenSave();
  }

  void _selectGardenTool(GardenTool tool) {
    _playSfx(_sfxCrispLeaf, volume: 0.42);
    setState(() {
      _gardenTool = tool;
      _gardenMessage = switch (tool) {
        GardenTool.plant => 'Tap an empty plot to open nursery',
        GardenTool.water => 'Tap growing plants to water',
        GardenTool.clear => 'Tap weeds to clear',
        GardenTool.sun => 'Tap growing plants for sun boost',
      };
      _gardenMessageLife = 2.1;
    });
  }

  void _selectGardenPlant(int index) {
    _playSfx(_sfxComboSpark, volume: 0.44);
    setState(() {
      _selectedGardenPlant = index
          .clamp(0, _gardenPlantOptions.length - 1)
          .toInt();
      _gardenTool = GardenTool.plant;
      final GardenPlantOption option = _selectedGardenPlantOption;
      _gardenMessage = _gardenNurseryPlotId == null
          ? '${option.name}: tap an empty plot'
          : '${option.name}: ready in ${_durationLabel(option.growDuration)}';
      _gardenMessageLife = 2.2;
    });
    _queueGardenSave();
  }

  void _openGardenNursery(PlayerGardenPlot plot) {
    _gardenNurseryPlotId = plot.id;
    _gardenTool = GardenTool.plant;
    final GardenPlantOption option = _selectedGardenPlantOption;
    _gardenMessage = 'Choose a plant for this plot';
    _gardenMessageLife = 1.8;
    _playSfx(_sfxCrispLeaf, volume: 0.38);
    if (_seeds < option.seedCost) {
      _gardenMessage = 'Choose a plant you can afford';
    }
  }

  void _closeGardenNursery() {
    setState(() {
      _gardenNurseryPlotId = null;
      _gardenMessage = 'Tap an empty plot to plant';
      _gardenMessageLife = 1.8;
    });
  }

  void _confirmGardenNurseryPlant() {
    setState(() {
      final PlayerGardenPlot? plot = _gardenNurseryPlot;
      if (plot == null) {
        _gardenNurseryPlotId = null;
        return;
      }
      if (_plantGardenPlot(plot)) {
        _gardenNurseryPlotId = null;
      }
    });
    _queueGardenSave();
  }

  void _handleGardenPlotTap(PlayerGardenPlot plot) {
    setState(() {
      if (!_isGardenPlotUnlocked(plot)) {
        _tryExpandGarden();
        return;
      }

      if (plot.weed) {
        _clearGardenWeed(plot);
        return;
      }
      if (!plot.planted) {
        _openGardenNursery(plot);
        return;
      }
      if (plot.ready) {
        _collectGardenBlooms(plot);
        return;
      }
      if (_gardenTool == GardenTool.sun) {
        _sunGardenPlot(plot);
        return;
      }
      _waterGardenPlot(plot);
    });
    _queueGardenSave();
  }

  void _tryExpandGarden() {
    if (_gardenLevel >= 3) {
      _gardenMessage = 'Garden fully expanded';
      _gardenMessageLife = 2.0;
      return;
    }
    if (_seeds < _gardenExpandCost) {
      _gardenMessage = 'Need $_gardenExpandCost seeds to expand';
      _gardenMessageLife = 2.2;
      return;
    }

    _seeds -= _gardenExpandCost;
    _gardenLevel += 1;
    _gardenMessage = 'New garden land unlocked!';
    _gardenMessageLife = 2.6;
    _playSfx(_sfxComboSpark, volume: 0.62);
    _queueGardenSave();
  }

  bool _plantGardenPlot(PlayerGardenPlot plot) {
    if (plot.weed) {
      _gardenMessage = 'Clear the weed first';
      _gardenMessageLife = 2.0;
      return false;
    }
    if (plot.planted) {
      final GardenPlantOption option = _plantOptionForPlot(plot);
      _gardenMessage = plot.ready
          ? '${option.name} blooms ready'
          : '${option.name} is growing';
      _gardenMessageLife = 2.0;
      return false;
    }

    final GardenPlantOption option = _selectedGardenPlantOption;
    final int seedCost = option.seedCost;
    if (_seeds < seedCost) {
      _gardenMessage = 'Need $seedCost seeds for ${option.name}';
      _gardenMessageLife = 2.0;
      return false;
    }

    _seeds -= seedCost;
    final DateTime now = _gardenNow;
    plot.asset = option.asset;
    plot.plantIndex = _selectedGardenPlant;
    plot.plantedAt = now;
    plot.readyAt = now.add(option.growDuration);
    plot.lastWateredDay = null;
    plot.growth = 0.08;
    plot.watered = false;
    plot.sparkle = 1;
    _gardenMessage =
        '${option.name} planted: ready in ${_durationLabel(option.growDuration)}';
    _gardenMessageLife = 2.0;
    _playSfx(_sfxCrispLeaf, volume: 0.48);
    return true;
  }

  void _waterGardenPlot(PlayerGardenPlot plot) {
    final DateTime now = _gardenNow;
    _refreshGardenPlot(plot, now);
    if (plot.weed) {
      _gardenMessage = 'Clear the weed first';
      _gardenMessageLife = 2.0;
      return;
    }
    if (!plot.planted) {
      _gardenMessage = 'Plant seeds here';
      _gardenMessageLife = 2.0;
      return;
    }
    if (plot.ready) {
      final GardenPlantOption option = _plantOptionForPlot(plot);
      _gardenMessage = 'Tap to collect ${option.name} blooms';
      _gardenMessageLife = 2.0;
      return;
    }
    if (_isWateredToday(plot, now)) {
      _gardenMessage =
          'Already watered. Ready in ${_durationLabel(_remainingGardenTime(plot, now))}';
      _gardenMessageLife = 2.0;
      return;
    }

    if (_waterCharges > 0) {
      _waterCharges -= 1;
    } else if (_seeds >= 20) {
      _seeds -= 20;
    } else {
      _gardenMessage = 'Need water';
      _gardenMessageLife = 2.0;
      return;
    }

    final GardenPlantOption option = _plantOptionForPlot(plot);
    plot.lastWateredDay = _dayKey(now);
    plot.watered = true;
    plot.readyAt = plot.readyAt?.subtract(
      Duration(
        milliseconds: (option.growDuration.inMilliseconds * 0.12).round(),
      ),
    );
    _refreshGardenPlot(plot, now);
    plot.sparkle = 1;
    _gardenMessage = plot.ready
        ? '${option.name} blooms ready'
        : 'Watered ${option.name}. Ready in ${_durationLabel(_remainingGardenTime(plot, now))}';
    _gardenMessageLife = 2.1;
    _playSfx(_sfxComboSpark, volume: 0.5);
  }

  void _sunGardenPlot(PlayerGardenPlot plot) {
    final DateTime now = _gardenNow;
    _refreshGardenPlot(plot, now);
    if (plot.weed) {
      _gardenMessage = 'Clear the weed first';
      _gardenMessageLife = 2.0;
      return;
    }
    if (!plot.planted) {
      _gardenMessage = 'Plant seeds here first';
      _gardenMessageLife = 2.0;
      return;
    }
    if (plot.ready) {
      final GardenPlantOption option = _plantOptionForPlot(plot);
      _gardenMessage = 'Tap to collect ${option.name} blooms';
      _gardenMessageLife = 2.0;
      return;
    }
    if (!_isWateredToday(plot, now)) {
      _gardenMessage = 'Water before using sun';
      _gardenMessageLife = 2.0;
      return;
    }
    if (_sunDrops <= 0) {
      _gardenMessage = 'Need sun drops';
      _gardenMessageLife = 2.0;
      return;
    }

    final GardenPlantOption option = _plantOptionForPlot(plot);
    _sunDrops -= 1;
    plot.readyAt = plot.readyAt?.subtract(
      Duration(
        milliseconds: (option.growDuration.inMilliseconds * 0.22).round(),
      ),
    );
    _refreshGardenPlot(plot, now);
    plot.sparkle = 1;
    _gardenMessage = plot.ready
        ? '${option.name} blooms ready'
        : 'Sun boost: ready in ${_durationLabel(_remainingGardenTime(plot, now))}';
    _gardenMessageLife = 2.2;
    _playSfx(_sfxComboSpark, volume: 0.56);
  }

  void _clearGardenWeed(PlayerGardenPlot plot) {
    if (!plot.weed) {
      _gardenMessage = 'No weed here';
      _gardenMessageLife = 1.7;
      return;
    }

    plot.weed = false;
    plot.sparkle = 1;
    _seeds += 18;
    _gardenMessage = plot.planted
        ? '+18 seeds, weed cleared'
        : '+18 seeds, tap plot to plant';
    _gardenMessageLife = 2.2;
    _playSfx(_sfxBambooBlade, volume: 0.62);
  }

  void _collectGardenBlooms(PlayerGardenPlot plot) {
    if (plot.weed) {
      _gardenMessage = 'Clear the weed first';
      _gardenMessageLife = 2.0;
      return;
    }
    if (!plot.ready) {
      _gardenMessage = plot.planted ? 'Still growing' : 'Nothing planted';
      _gardenMessageLife = 2.0;
      return;
    }

    final GardenPlantOption option = _plantOptionForPlot(plot);
    final int pointReward = option.points + ((plot.unlockLevel - 1) * 35);
    final int seedReward =
        _gardenSeedRewardFor(option) + ((plot.unlockLevel - 1) * 10);
    _gardenPoints += pointReward;
    _score += pointReward;
    _seeds += seedReward;
    if (option.name == 'Blue Bell') {
      _waterCharges = min(12, _waterCharges + 1);
    } else if (option.name == 'Cherry') {
      _sunDrops = min(12, _sunDrops + 1);
    } else if (option.name == 'Shield Flower') {
      _gardenWeedTimer += 18;
    }
    _gardenHarvests += 1;
    if (_gardenHarvests % 2 == 0) {
      _sunDrops += 1;
    }
    final DateTime now = _gardenNow;
    plot.plantedAt = now;
    plot.readyAt = now.add(option.growDuration);
    plot.lastWateredDay = null;
    plot.growth = 0.22;
    plot.watered = false;
    plot.sparkle = 1;
    _gardenMessage = 'Collected blooms: +$pointReward pts, +$seedReward seeds';
    _gardenMessageLife = 2.3;
    _playSfx(_sfxComboSpark, volume: 0.68);
  }

  void _selectAvatar(int index) {
    _playSfx(_sfxComboSpark, volume: 0.48);
    setState(() {
      _selectedAvatar = index.clamp(0, _avatarAssets.length - 1).toInt();
    });
  }

  void _selectMusicTrack(int index) {
    _playSfx(_sfxComboSpark, volume: 0.42);
    setState(() {
      _selectedMusicTrack = index.clamp(0, _musicTracks.length - 1).toInt();
    });
    unawaited(_playSelectedMusic());
  }

  void _toggleMusic() {
    setState(() {
      _musicEnabled = !_musicEnabled;
    });
    if (_musicEnabled) {
      unawaited(_playSelectedMusic());
    } else {
      unawaited(_musicPlayer.stop());
    }
  }

  void _toggleSfx() {
    setState(() {
      _sfxEnabled = !_sfxEnabled;
    });
    if (_sfxEnabled) {
      _playSfx(_sfxCrispLeaf, volume: 0.44);
    }
  }

  void _buyCharge(String kind, int cost) {
    if (_seeds < cost) {
      return;
    }
    _playSfx(_sfxComboSpark, volume: 0.55);
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

  Future<void> _handleBackIntent() async {
    if (_phase == GamePhase.playing) {
      _pause();
      return;
    }
    if (_phase == GamePhase.paused ||
        _phase == GamePhase.results ||
        _phase == GamePhase.upgrades ||
        _phase == GamePhase.garden) {
      _goHome();
      return;
    }

    final bool shouldQuit =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF193D16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF9EDB5A), width: 2),
              ),
              title: const Text(
                'Quit Garden Ninja?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: const Text(
                'Your garden progress is safe for this session.',
                style: TextStyle(
                  color: Color(0xFFE7FFCC),
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE7FF9A),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF75B843),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Quit'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (shouldQuit) {
      await _musicPlayer.stop();
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_handleBackIntent());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF102716),
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final Size viewport = constraints.biggest;
            if (viewport.width <= 0 || viewport.height <= 0) {
              return const SizedBox.shrink();
            }

            final double scale = max(
              viewport.width / _worldWidth,
              viewport.height / _worldHeight,
            );
            final double width = _worldWidth * scale;
            final double height = _worldHeight * scale;

            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF143C1B), Color(0xFF061B12)],
                ),
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: width,
                  maxWidth: width,
                  minHeight: height,
                  maxHeight: height,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: _buildGameSurface(Size(width, height)),
                  ),
                ),
              ),
            );
          },
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
            if (_tutorialMode) _buildTutorialOverlay(size),
          ],
          if (_phase == GamePhase.home) _buildHomeLayer(),
          if (_phase == GamePhase.paused) _buildPausedLayer(),
          if (_phase == GamePhase.results) _buildResultsLayer(),
          if (_phase == GamePhase.upgrades) _buildUpgradesLayer(),
          if (_phase == GamePhase.garden) _buildPlayerGardenLayer(),
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

  Widget _buildTutorialOverlay(Size size) {
    GardenTarget? focus;
    for (final target in _targets) {
      final bool isFocusTarget = _tutorialStep == TutorialStep.useIce
          ? false
          : target.type == TargetType.weed;
      if (isFocusTarget) {
        focus = target;
        break;
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 18,
          right: 18,
          top: 74,
          child: IgnorePointer(
            child: _TutorialPrompt(
              title: _tutorialTitle,
              body: _tutorialBody,
              progress: '${_tutorialStep.index + 1}/5',
              warning: _tutorialMistake,
            ),
          ),
        ),
        if (focus != null) _buildTutorialFocus(focus, size),
        if (_tutorialStep == TutorialStep.avoidFlowers)
          for (final flower in _targets.where(
            (t) => t.type == TargetType.flower,
          ))
            _buildTutorialFlowerWarning(flower, size),
        if (_tutorialStep == TutorialStep.useIce) _buildIceTutorialCallout(),
        Positioned(
          right: 16,
          top: 18,
          child: _TutorialSkipButton(
            onTap: () {
              setState(() {
                _tutorialMode = false;
                _phase = GamePhase.home;
                _targets.clear();
                _shards.clear();
                _slashes.clear();
                _bursts.clear();
              });
              unawaited(_musicPlayer.setVolume(0.34));
            },
          ),
        ),
      ],
    );
  }

  String get _tutorialTitle {
    switch (_tutorialStep) {
      case TutorialStep.slashWeed:
        return 'Slash the weed';
      case TutorialStep.avoidFlowers:
        return _tutorialMistake ? 'Careful!' : 'Protect flowers';
      case TutorialStep.toughWeed:
        return 'Tough weeds split';
      case TutorialStep.useIce:
        return 'Use Ice';
      case TutorialStep.frozenSlash:
        return 'Shatter them';
    }
  }

  String get _tutorialBody {
    switch (_tutorialStep) {
      case TutorialStep.slashWeed:
        return 'Swipe through the weed to cut it.';
      case TutorialStep.avoidFlowers:
        return _tutorialMistake
            ? 'Flowers are friends. Swipe the weed only.'
            : 'Slash the weed beside the flower.';
      case TutorialStep.toughWeed:
        return 'Big weeds need more than one swipe.';
      case TutorialStep.useIce:
        return 'Tap Ice before the weeds reach your plants.';
      case TutorialStep.frozenSlash:
        return 'Now slash the frozen weeds.';
    }
  }

  Widget _buildTutorialFocus(GardenTarget target, Size size) {
    final double pixelSize = target.size / _worldWidth * size.width;
    final double left =
        target.position.dx / _worldWidth * size.width - pixelSize * 0.58;
    final double top =
        target.position.dy / _worldHeight * size.height - pixelSize * 0.58;
    final double pulse = 1 + sin(_motionTime * 5.2).abs() * 0.08;
    return Positioned(
      left: left,
      top: top,
      width: pixelSize * 1.16,
      height: pixelSize * 1.16,
      child: IgnorePointer(
        child: Transform.scale(
          scale: pulse,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFF17C), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFF17C).withValues(alpha: 0.42),
                      blurRadius: 20,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              if (_tutorialStep != TutorialStep.useIce)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Transform.rotate(
                    angle: -0.7 + sin(_motionTime * 5) * 0.08,
                    child: const Icon(
                      Icons.swipe_rounded,
                      color: Colors.white,
                      size: 36,
                      shadows: [
                        Shadow(color: Color(0xAA14350D), blurRadius: 7),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialFlowerWarning(GardenTarget flower, Size size) {
    final double pixelSize = flower.size / _worldWidth * size.width;
    final double left =
        flower.position.dx / _worldWidth * size.width - pixelSize * 0.58;
    final double top =
        flower.position.dy / _worldHeight * size.height - pixelSize * 0.58;
    return Positioned(
      left: left,
      top: top,
      width: pixelSize * 1.16,
      height: pixelSize * 1.16,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF8DB8), width: 3),
          ),
          child: const Align(
            alignment: Alignment.topCenter,
            child: Icon(
              Icons.favorite_rounded,
              color: Color(0xFFFF8DB8),
              size: 24,
              shadows: [Shadow(color: Color(0xAA4A1023), blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIceTutorialCallout() {
    return Positioned(
      right: 22,
      bottom: 78,
      child: IgnorePointer(
        child: Transform.translate(
          offset: Offset(0, sin(_motionTime * 5) * 4),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tap Ice',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Color(0xAA0A2B35), blurRadius: 5)],
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_downward_rounded,
                color: Color(0xFF9CF8FF),
                size: 30,
                shadows: [Shadow(color: Color(0xAA0A2B35), blurRadius: 5)],
              ),
            ],
          ),
        ),
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
          left: 106,
          right: 106,
          top: 558,
          child: _TutorialHomeButton(onTap: _startTutorial, phase: t),
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
                      onTap: _openGarden,
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

  Widget _buildPlayerGardenLayer() {
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: _worldWidth,
        height: _worldHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF214F23), Color(0xFF0E2818)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 122,
              bottom: 94,
              child: _buildScrollableGardenMap(),
            ),
            _buildGardenTopHud(),
            Positioned(right: 12, top: 112, child: _buildGardenExpandBadge()),
            if (_gardenMessageLife > 0)
              Positioned(
                left: 54,
                right: 54,
                top: 162,
                child: Opacity(
                  opacity: _gardenMessageLife.clamp(0.0, 1.0),
                  child: _GardenToast(message: _gardenMessage),
                ),
              ),
            if (_gardenNurseryPlot == null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 92,
                child: _buildGardenActionHint(),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _buildGardenToolbar(),
            ),
            if (_gardenNurseryPlot != null) _buildGardenNurseryOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableGardenMap() {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _gardenMapController,
        constrained: false,
        minScale: 0.58,
        maxScale: 1.08,
        boundaryMargin: const EdgeInsets.all(220),
        child: SizedBox(
          width: _playerGardenWidth,
          height: _playerGardenHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/backgrounds/player_garden_map.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                ),
              ),
              for (final plot in _playerGardenPlots) _buildGardenPlot(plot),
              Positioned(
                left: 528,
                top: 1012,
                child: _GardenMapLabel(
                  icon: Icons.open_in_full_rounded,
                  label: _gardenLevel >= 3
                      ? 'Full Garden'
                      : 'Expand $_gardenExpandCost',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGardenPlot(PlayerGardenPlot plot) {
    final DateTime now = _gardenNow;
    _refreshGardenPlot(plot, now);
    final bool unlocked = _isGardenPlotUnlocked(plot);
    final String weedAsset =
        _playerGardenWeedAssets[plot.id % _playerGardenWeedAssets.length];
    final String status = _gardenPlotStatus(plot, now);
    final double pulse = 1 + sin(_motionTime * 3.2 + plot.id).abs() * 0.035;
    final double sparkle = plot.sparkle.clamp(0.0, 1.0);
    final double plantScale = switch (plot.growthStage) {
      0 => 0.7,
      1 => 0.58,
      2 => 0.78,
      _ => 0.92,
    };
    final GardenPlantRenderSpec? plantSpec = plot.planted
        ? _plantRenderSpecForPlot(plot)
        : null;
    final bool plantTarget =
        unlocked &&
        !plot.weed &&
        !plot.planted &&
        _gardenTool == GardenTool.plant;

    return Positioned(
      left: plot.position.dx - 62,
      top: plot.position.dy - 70,
      width: 124,
      height: 142,
      child: GestureDetector(
        key: ValueKey('player-garden-plot-${plot.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleGardenPlotTap(plot),
        child: Opacity(
          opacity: unlocked ? 1 : 0.58,
          child: Transform.scale(
            scale: plot.ready ? pulse : 1,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (plantTarget)
                  Positioned(
                    bottom: 8,
                    child: Container(
                      width: 116,
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFFF176),
                          width: 2.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFFF176,
                            ).withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 15,
                  child: Container(
                    width: 110,
                    height: 42,
                    decoration: BoxDecoration(
                      color: unlocked
                          ? const Color(0xCC6A3A17)
                          : const Color(0xCC343824),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: unlocked
                            ? const Color(0xFFD9A45D)
                            : const Color(0xFF7C8465),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 78,
                        height: 12,
                        margin: const EdgeInsets.only(bottom: 5),
                        decoration: BoxDecoration(
                          color: const Color(0x99321A0A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!unlocked)
                  const Positioned(
                    top: 26,
                    child: Icon(
                      Icons.lock_rounded,
                      color: Color(0xFFFFE29B),
                      size: 34,
                    ),
                  )
                else if (!plot.planted)
                  Positioned(
                    top: 23,
                    child: Image.asset(
                      'assets/images/icons/nursery_sign.png',
                      width: 50,
                      height: 50,
                      filterQuality: FilterQuality.medium,
                    ),
                  )
                else
                  Positioned(
                    bottom: plantSpec!.bottom,
                    child: Transform.translate(
                      offset: Offset(plantSpec.offsetX, plantSpec.offsetY),
                      child: Transform.scale(
                        alignment: Alignment.bottomCenter,
                        scale: plantScale * plantSpec.scale,
                        child: Image.asset(
                          plot.asset!,
                          width: plantSpec.width,
                          height: plantSpec.height,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                if (plot.weed && unlocked)
                  Positioned(
                    top: -2 + sin(_motionTime * 5 + plot.id) * 2,
                    right: 8,
                    child: Image.asset(
                      weedAsset,
                      width: 48,
                      height: 52,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                if (plot.ready && unlocked)
                  Positioned(
                    top: -4,
                    right: 9,
                    child: Image.asset(
                      'assets/images/icons/bloom_collect.png',
                      width: 32,
                      height: 32,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                if (unlocked)
                  Positioned(
                    top: -10,
                    child: _GardenTinyBadge(
                      text: status,
                      color: plot.weed
                          ? const Color(0xEE67221D)
                          : plot.ready
                          ? const Color(0xEEF0A51A)
                          : !plot.planted
                          ? const Color(0xEE2C701F)
                          : !plot.watered
                          ? const Color(0xEE1D6C85)
                          : const Color(0xEE2E6D24),
                      borderColor: plot.watered && !plot.ready && !plot.weed
                          ? const Color(0xFFE4FFAA)
                          : const Color(0xFFFFD36A),
                    ),
                  ),
                if (plot.planted && unlocked)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 2,
                    child: _GardenProgressBar(progress: plot.growth),
                  ),
                if (sparkle > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: sparkle,
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFFFF17A),
                          size: 54,
                        ),
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

  Widget _buildGardenNurseryOverlay() {
    final GardenPlantOption selected = _selectedGardenPlantOption;
    final bool affordable = _seeds >= selected.seedCost;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeGardenNursery,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.46)),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: 116,
            bottom: 14,
            child: Container(
              key: const ValueKey('garden-nursery-sheet'),
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FFE9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2FF6A), width: 2.4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/icons/nursery_sign.png',
                        width: 46,
                        height: 46,
                        filterQuality: FilterQuality.medium,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Choose plant for this plot',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Color(0xFF397F1F),
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              'Tap a card, then press Plant.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFF5C952F),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RoundIconButton(
                        icon: Icons.close_rounded,
                        onPressed: _closeGardenNursery,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.35,
                          ),
                      itemCount: _gardenPlantOptions.length,
                      itemBuilder: (context, index) {
                        final GardenPlantOption option =
                            _gardenPlantOptions[index];
                        return _GardenNurseryPlantCard(
                          key: ValueKey('garden-plant-option-$index'),
                          option: option,
                          selected: _selectedGardenPlant == index,
                          affordable: _seeds >= option.seedCost,
                          onTap: () => _selectGardenPlant(index),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _PrimaryButton(
                      key: const ValueKey('garden-confirm-plant'),
                      label: affordable
                          ? 'PLANT ${selected.name.toUpperCase()} HERE'
                          : 'NEED ${selected.seedCost} SEEDS',
                      icon: Icons.spa_rounded,
                      onPressed: _confirmGardenNurseryPlant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardenTopHud() {
    final int unlockedPlots = _playerGardenPlots
        .where(_isGardenPlotUnlocked)
        .length;
    return Positioned(
      left: 10,
      right: 10,
      top: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _RoundIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: _goHome,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xDD143A18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF9FE866),
                      width: 1.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'MY GARDEN  ${_formatNumber(_gardenPoints)} pts',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xAA2C5F1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$unlockedPlots/${_playerGardenPlots.length}',
                          style: const TextStyle(
                            color: Color(0xFFDDF9A6),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _GardenStatChip(
                  asset: 'assets/images/icons/seed_coin.png',
                  value: _formatNumber(_seeds),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _GardenStatChip(
                  asset: 'assets/images/icons/water_drop.png',
                  value: '$_waterCharges',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _GardenStatChip(
                  asset: 'assets/images/icons/sun_boost.png',
                  value: '$_sunDrops',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _GardenStatChip(
                  icon: Icons.local_fire_department_rounded,
                  value: '${_gardenLoginStreak}d',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGardenExpandBadge() {
    final bool complete = _gardenLevel >= 3;
    return GestureDetector(
      key: const ValueKey('garden-expand'),
      onTap: () => setState(_tryExpandGarden),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: complete ? const Color(0xDD395934) : const Color(0xE6634316),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFD36A), width: 1.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.open_in_full_rounded,
              color: const Color(0xFFFFEAA5),
              size: 18,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                complete ? 'Full' : 'Expand',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGardenActionHint() {
    final (IconData icon, String text) = switch (_gardenTool) {
      GardenTool.plant => (
        Icons.touch_app_rounded,
        'Plant: tap a glowing empty plot',
      ),
      GardenTool.water => (
        Icons.water_drop_rounded,
        'Water: tap a plant marked Water me',
      ),
      GardenTool.clear => (Icons.cut_rounded, 'Clear: tap a Weed! badge'),
      GardenTool.sun => (
        Icons.wb_sunny_rounded,
        'Sun: boost a watered growing plant',
      ),
    };
    return Container(
      key: const ValueKey('garden-action-hint'),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xE51B3D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7FF9A), width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFED86), size: 21),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardenToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xE5143A18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBDF17A), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _GardenToolButton(
              key: const ValueKey('garden-tool-plant'),
              icon: Icons.spa_rounded,
              label: 'Plant',
              selected: _gardenTool == GardenTool.plant,
              onTap: () => _selectGardenTool(GardenTool.plant),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _GardenToolButton(
              key: const ValueKey('garden-tool-water'),
              icon: Icons.water_drop_rounded,
              label: 'Water',
              selected: _gardenTool == GardenTool.water,
              onTap: () => _selectGardenTool(GardenTool.water),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _GardenToolButton(
              key: const ValueKey('garden-tool-clear'),
              icon: Icons.cut_rounded,
              label: 'Clear',
              selected: _gardenTool == GardenTool.clear,
              onTap: () => _selectGardenTool(GardenTool.clear),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _GardenToolButton(
              key: const ValueKey('garden-tool-sun'),
              icon: Icons.wb_sunny_rounded,
              label: 'Sun',
              selected: _gardenTool == GardenTool.sun,
              onTap: () => _selectGardenTool(GardenTool.sun),
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
            onPressed: _goHome,
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
              setState(() {
                _level += 1;
              });
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
                onPressed: _goHome,
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
                const SizedBox(height: 10),
                _buildAudioPanel(),
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

  Widget _buildAudioPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEEF7E9BC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4C7E26), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Audio',
                  style: TextStyle(
                    color: Color(0xFF234B18),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _AudioToggle(
                icon: _musicEnabled
                    ? Icons.music_note_rounded
                    : Icons.music_off_rounded,
                active: _musicEnabled,
                onTap: _toggleMusic,
              ),
              const SizedBox(width: 8),
              _AudioToggle(
                icon: _sfxEnabled
                    ? Icons.graphic_eq_rounded
                    : Icons.volume_off_rounded,
                active: _sfxEnabled,
                onTap: _toggleSfx,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (int index = 0; index < _musicTracks.length; index += 1)
                _MusicTrackChip(
                  title: _musicTracks[index].title,
                  mood: _musicTracks[index].mood,
                  selected: index == _selectedMusicTrack,
                  onTap: () => _selectMusicTrack(index),
                ),
            ],
          ),
        ],
      ),
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
    super.key,
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

class _TutorialHomeButton extends StatelessWidget {
  const _TutorialHomeButton({required this.onTap, required this.phase});

  final VoidCallback onTap;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1 + sin(phase * 2.4).abs() * 0.025,
      child: SizedBox(
        height: 42,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xDD173B16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE7FF9A), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x77071506),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.school_rounded, color: Color(0xFFE7FF9A), size: 22),
                SizedBox(width: 7),
                Text(
                  'Tutorial',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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

class _TutorialPrompt extends StatelessWidget {
  const _TutorialPrompt({
    required this.title,
    required this.body,
    required this.progress,
    required this.warning,
  });

  final String title;
  final String body;
  final String progress;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? const Color(0xEE5E1D25) : const Color(0xEE173B16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? const Color(0xFFFF9FCA) : const Color(0xFFE7FF9A),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88071506),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: warning
                    ? const Color(0xFFFF7BA8)
                    : const Color(0xFF63B92A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                progress,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE7FFCC),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialSkipButton extends StatelessWidget {
  const _TutorialSkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Skip tutorial',
      child: SizedBox(
        width: 42,
        height: 42,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xDD173B16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE7FF9A), width: 2),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioToggle extends StatelessWidget {
  const _AudioToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'On' : 'Off',
      child: SizedBox(
        width: 42,
        height: 42,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active ? const Color(0xFF5DBA28) : const Color(0xFF6D784C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE9FFC6), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x662C421B),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
        ),
      ),
    );
  }
}

class _MusicTrackChip extends StatelessWidget {
  const _MusicTrackChip({
    required this.title,
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 109,
      height: 58,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4D9E22) : const Color(0xFFFFF9D8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE9FFC6)
                  : const Color(0xFF74A846),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44233A13),
                blurRadius: 7,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF234B18),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mood,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFE9FFC6)
                        : const Color(0xFF577A38),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
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

class _GardenStatChip extends StatelessWidget {
  const _GardenStatChip({required this.value, this.asset, this.icon});

  final String value;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xDD193D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF95D957), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (asset != null)
            Image.asset(asset!, width: 20, height: 20)
          else
            Icon(icon, color: const Color(0xFFFFD36A), size: 19),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GardenToolButton extends StatelessWidget {
  const _GardenToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF62BD2F) : const Color(0xCC214C1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFFFE477) : const Color(0xFF80B95A),
            width: selected ? 2.4 : 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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

class _GardenNurseryPlantCard extends StatelessWidget {
  const _GardenNurseryPlantCard({
    super.key,
    required this.option,
    required this.selected,
    required this.affordable,
    required this.onTap,
  });

  final GardenPlantOption option;
  final bool selected;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = affordable
        ? const Color(0xFF2F8322)
        : const Color(0xFF6C785E);
    final Color bodyColor = affordable
        ? const Color(0xFF557C24)
        : const Color(0xFF7D8472);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFF9D7)
              : affordable
              ? Colors.white
              : const Color(0xFFE9EBDD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFFFFD43A)
                : affordable
                ? const Color(0xFFB9E75A)
                : const Color(0xFFB8C6A2),
            width: selected ? 3 : 1.5,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 9,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  option.asset,
                  width: 46,
                  height: 62,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.name,
                          maxLines: 1,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/icons/seed_coin.png',
                            width: 13,
                            height: 13,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${option.seedCost} seeds',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bodyColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '+${option.points} pts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: affordable
                              ? const Color(0xFF18803B)
                              : const Color(0xFF7D8472),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Ready ${_staticDurationLabel(option.growDuration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.role,
                          maxLines: 1,
                          style: TextStyle(
                            color: bodyColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF68BD2F),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _staticDurationLabel(Duration duration) {
  if (duration.inDays >= 1) {
    return '${duration.inDays}d';
  }
  if (duration.inHours >= 1) {
    return '${duration.inHours}h';
  }
  return '${max(1, duration.inMinutes)}m';
}

class _GardenProgressBar extends StatelessWidget {
  const _GardenProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xAA17310F),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE4FFAA), width: 1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: progress >= 1
                ? const Color(0xFFFFD84D)
                : const Color(0xFF73E347),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _GardenTinyBadge extends StatelessWidget {
  const _GardenTinyBadge({
    required this.text,
    this.color = const Color(0xEE67221D),
    this.borderColor = const Color(0xFFFFD36A),
  });

  final String text;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GardenToast extends StatelessWidget {
  const _GardenToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xE51B3D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7FF9A), width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          message,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GardenMapLabel extends StatelessWidget {
  const _GardenMapLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xDD224817),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD36A), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFFE477), size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
      key: ValueKey('home-menu-$label'),
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
