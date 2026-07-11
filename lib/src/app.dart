import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

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

enum GardenAmbient { petals, bambooLeaves, fireflies, snow }

enum GardenEcosystemTask { plant, water, collect, tidy }

enum GardenZoneStyle {
  orchard,
  flowerBorder,
  herbSpiral,
  kitchenRows,
  meadow,
  trellis,
}

enum ForceUpdateState { idle, checking, updating, blocked }

@visibleForTesting
bool debugForcePlayUpdateChecks = false;

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

class GardenWorld {
  const GardenWorld({
    required this.name,
    required this.unlockPoints,
    required this.ambient,
    required this.accent,
    required this.darkAccent,
    required this.bonus,
  });

  final String name;
  final int unlockPoints;
  final GardenAmbient ambient;
  final Color accent;
  final Color darkAccent;
  final String bonus;
}

class GardenHouseTier {
  const GardenHouseTier({
    required this.name,
    required this.maxGardenLevel,
    required this.unlockPoints,
    required this.seedCost,
    required this.roofColor,
    required this.wallColor,
    required this.bonus,
  });

  final String name;
  final int maxGardenLevel;
  final int unlockPoints;
  final int seedCost;
  final Color roofColor;
  final Color wallColor;
  final String bonus;
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
    this.grassCut = false,
    this.upgradeLevel = 1,
    this.mature = false,
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
  bool grassCut;
  int upgradeLevel;
  bool mature;
  double sparkle;

  bool get planted => asset != null;
  bool get ready => planted && growth >= 1;

  int get growthStage {
    if (!planted) {
      return 0;
    }
    if (mature) {
      return 3;
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
  static const double _playerGardenWidth = 920;
  static const double _playerGardenHeight = 1680;
  static const double _gardenMinScale = 0.54;
  static const double _gardenMaxScale = 1.55;
  static const double _gardenInitialScale = 0.55;
  static const double _gardenInitialTranslateX = -58;
  static const double _gardenInitialTranslateY = 40;
  static const double _gardenDamageLineY = _worldHeight - 106;
  static const double _minSlashSegment = 7;
  static const int _maxSlashTrails = 22;
  static const int _maxSliceShards = 20;
  static const Duration _minSfxGap = Duration(milliseconds: 42);
  static const Duration _sameSfxGap = Duration(milliseconds: 82);
  static const String _gardenSaveKey = 'garden_ninja_garden_v4';
  static const int _dailyWaterGrant = 3;
  static const int _dailySunGrant = 1;
  static const int _gardenCalmMusicTrack = 4;
  static const int _gardenTendedReward = 25;
  static const Duration _gardenWelcomeAfter = Duration(hours: 6);
  static const int _notifIdNextBloom = 1;
  static const int _notifIdMorningGift = 2;
  static const int _notifIdComeback = 3;
  static const NotificationDetails _gardenNotificationDetails =
      NotificationDetails(
        android: AndroidNotificationDetails(
          'garden_reminders',
          'Garden reminders',
          channelDescription:
              'Gentle reminders when plants bloom and gifts arrive',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
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
    GardenPlantOption(
      name: 'Apple Tree',
      asset: 'assets/images/sprites/tree_apple.png',
      seedCost: 180,
      points: 420,
      seedReward: 190,
      growDuration: Duration(days: 2),
      role: 'Fruit + water',
    ),
    GardenPlantOption(
      name: 'Lemon Tree',
      asset: 'assets/images/sprites/tree_lemon.png',
      seedCost: 210,
      points: 520,
      seedReward: 215,
      growDuration: Duration(days: 3),
      role: 'Fruit + sun',
    ),
    GardenPlantOption(
      name: 'Orange Tree',
      asset: 'assets/images/sprites/tree_orange.png',
      seedCost: 240,
      points: 640,
      seedReward: 245,
      growDuration: Duration(days: 4),
      role: 'Water + sun',
    ),
    GardenPlantOption(
      name: 'Maple Tree',
      asset: 'assets/images/sprites/tree_maple.png',
      seedCost: 260,
      points: 760,
      seedReward: 280,
      growDuration: Duration(days: 5),
      role: 'Slows weeds',
    ),
  ];
  static const List<GardenPlantRenderSpec> _gardenPlantRenderSpecs = [
    GardenPlantRenderSpec(width: 88, height: 96, bottom: 42),
    GardenPlantRenderSpec(width: 78, height: 102, bottom: 42),
    GardenPlantRenderSpec(width: 76, height: 94, bottom: 42),
    GardenPlantRenderSpec(width: 82, height: 102, bottom: 42),
    GardenPlantRenderSpec(width: 136, height: 118, bottom: 38, scale: 0.98),
    GardenPlantRenderSpec(width: 88, height: 102, bottom: 42),
    GardenPlantRenderSpec(width: 236, height: 264, bottom: 10, scale: 0.94),
    GardenPlantRenderSpec(width: 236, height: 264, bottom: 10, scale: 0.94),
    GardenPlantRenderSpec(width: 236, height: 264, bottom: 10, scale: 0.94),
    GardenPlantRenderSpec(width: 226, height: 254, bottom: 10, scale: 0.94),
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
  static const List<GardenWorld> _gardenWorlds = [
    GardenWorld(
      name: 'Orchard Grove',
      unlockPoints: 0,
      ambient: GardenAmbient.petals,
      accent: Color(0xFF91C957),
      darkAccent: Color(0xFF315F1D),
      bonus: 'Starter garden',
    ),
    GardenWorld(
      name: 'Bamboo Zen',
      unlockPoints: 1200,
      ambient: GardenAmbient.bambooLeaves,
      accent: Color(0xFF75D06A),
      darkAccent: Color(0xFF1E5D32),
      bonus: '+calm growth',
    ),
    GardenWorld(
      name: 'Moon Lotus',
      unlockPoints: 3200,
      ambient: GardenAmbient.fireflies,
      accent: Color(0xFF84D7FF),
      darkAccent: Color(0xFF183B6A),
      bonus: '+night blooms',
    ),
    GardenWorld(
      name: 'Winter Conservatory',
      unlockPoints: 6200,
      ambient: GardenAmbient.snow,
      accent: Color(0xFFBDEBFF),
      darkAccent: Color(0xFF294E73),
      bonus: '+frost calm',
    ),
  ];
  static const List<GardenHouseTier> _gardenHouseTiers = [
    GardenHouseTier(
      name: 'Cottage Townhouse',
      maxGardenLevel: 3,
      unlockPoints: 0,
      seedCost: 0,
      roofColor: Color(0xFF6E8B35),
      wallColor: Color(0xFFFFE5B1),
      bonus: 'starter yard and Lv 2 plants',
    ),
    GardenHouseTier(
      name: 'Family Townhouse',
      maxGardenLevel: 5,
      unlockPoints: 1800,
      seedCost: 350,
      roofColor: Color(0xFF8E5A31),
      wallColor: Color(0xFFFFD6A1),
      bonus: 'larger yard and Lv 3 plants',
    ),
    GardenHouseTier(
      name: 'Garden Villa',
      maxGardenLevel: 7,
      unlockPoints: 5200,
      seedCost: 1200,
      roofColor: Color(0xFF4F6F86),
      wallColor: Color(0xFFE8F3FF),
      bonus: 'villa land and Lv 4 plants',
    ),
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
      position: const Offset(674, 556),
      unlockLevel: 1,
      asset: 'assets/images/sprites/tree_apple.png',
      plantIndex: 6,
      growth: 0.7,
      watered: true,
      grassCut: true,
    ),
    PlayerGardenPlot(
      id: 1,
      position: const Offset(218, 654),
      unlockLevel: 1,
      asset: 'assets/images/sprites/pink_blossom_bush.png',
      plantIndex: 4,
      growth: 1,
      mature: true,
      grassCut: true,
      sparkle: 0.7,
    ),
    PlayerGardenPlot(
      id: 2,
      position: const Offset(692, 836),
      unlockLevel: 1,
      asset: 'assets/images/sprites/blue_bell_bloom.png',
      plantIndex: 1,
      growth: 0.74,
      grassCut: true,
    ),
    PlayerGardenPlot(
      id: 3,
      position: const Offset(214, 904),
      unlockLevel: 1,
      grassCut: true,
    ),
    PlayerGardenPlot(id: 4, position: const Offset(682, 1072), unlockLevel: 2),
    PlayerGardenPlot(id: 5, position: const Offset(214, 1196), unlockLevel: 3),
    PlayerGardenPlot(id: 6, position: const Offset(688, 1324), unlockLevel: 4),
    PlayerGardenPlot(id: 7, position: const Offset(214, 1450), unlockLevel: 5),
    PlayerGardenPlot(id: 8, position: const Offset(706, 1518), unlockLevel: 6),
    PlayerGardenPlot(id: 9, position: const Offset(174, 1580), unlockLevel: 7),
  ];

  late final Ticker _ticker;
  late final AudioPlayer _musicPlayer;
  late final TransformationController _gardenMapController;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  bool _notificationPermissionAsked = false;
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
  ForceUpdateState _forceUpdateState = ForceUpdateState.idle;

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
  int _sunDrops = 3;
  int _waterCharges = 3;
  int _iceCharges = 2;
  int _gardenPoints = 2350;
  int _rewardSeeds = 0;
  int _selectedAvatar = 0;
  int _selectedMusicTrack = 0;
  int _selectedGardenPlant = 0;
  int _selectedGardenWorld = 0;
  int _gardenHouseTier = 0;
  int? _gardenNurseryPlotId;
  int _gardenLoginStreak = 1;
  int _gardenBestStreak = 1;
  int _gardenMood = 62;
  int _gardenCompost = 0;
  int? _gardenGiftPlotId;
  int? _gardenLastVisitMs;
  int? _musicTrackBeforeGarden;
  int _gardenSessionWeedSpawns = 0;
  bool _lastRunWon = false;
  bool _musicEnabled = true;
  bool _sfxEnabled = true;
  bool _audioReady = false;
  bool _musicStartQueued = false;
  bool _forceUpdateCheckInFlight = false;
  bool _tutorialMode = false;
  bool _tutorialMistake = false;
  bool _gardenSaveLoaded = false;
  bool _showGardenWelcome = false;
  bool _showGardenHousePanel = false;
  bool _correctingGardenTransform = false;
  List<String> _gardenWelcomeLines = const [];
  List<String> _dailySummaryLines = [];
  TutorialStep _tutorialStep = TutorialStep.slashWeed;
  double _spawnTimer = 0;
  double _timeLeft = 60;
  double _iceTime = 0;
  double _sunTime = 0;
  double _flowerPenaltyCooldown = 0;
  double _gardenDamageFlash = 0;
  double _gardenDamageCooldown = 0;
  double _gardenWeedTimer = 90;
  double _gardenMessageLife = 0;
  double _motionTime = 0;
  Offset? _lastSlashPoint;
  Offset _gardenCaretakerPosition = const Offset(460, 560);
  Offset _gardenCaretakerTarget = const Offset(460, 560);
  bool _gardenCaretakerMoving = false;
  String _gardenMessage = 'Tap empty plot to open nursery';
  String? _gardenLastLoginDay;
  String? _gardenStreakGraceDay;
  String? _gardenLastTendedDay;
  String? _gardenGiftDay;
  String? _gardenDailyTaskDay;
  String? _gardenWaterBarrelDay;
  String? _gardenHabitatDay;
  bool _gardenDailyPlantDone = false;
  bool _gardenDailyWaterDone = false;
  bool _gardenDailyCollectDone = false;
  bool _gardenDailyTidyDone = false;
  bool _gardenDailyRewardClaimed = false;
  String _forceUpdateMessage = 'Checking for the latest update...';

  int get _goalWeeds => 18 + (_level * 4);

  String get _currentBackground =>
      _backgrounds[(_level - 1) % _backgrounds.length];

  String get _currentAvatar => _avatarAssets[_selectedAvatar];

  MusicTrack get _currentMusicTrack => _musicTracks[_selectedMusicTrack];

  bool get _supportsPlayInAppUpdates =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      (kReleaseMode || debugForcePlayUpdateChecks);

  bool get _forceUpdateVisible => _forceUpdateState != ForceUpdateState.idle;

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

  DateTime? _dateFromDayKey(String? value) {
    if (value == null) {
      return null;
    }
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  int _daysBetween(DateTime from, DateTime to) {
    final DateTime fromDate = DateTime(from.year, from.month, from.day);
    final DateTime toDate = DateTime(to.year, to.month, to.day);
    return (toDate.difference(fromDate).inHours / 24).round();
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
      _syncDailyGarden(_gardenNow);
    });
    _queueGardenSave();
  }

  void _applyGardenSave(Map<String, dynamic> data) {
    _seeds = (data['seeds'] as num?)?.toInt() ?? _seeds;
    _waterCharges = (data['waterCharges'] as num?)?.toInt() ?? _waterCharges;
    _sunDrops = (data['sunDrops'] as num?)?.toInt() ?? _sunDrops;
    _gardenPoints = (data['gardenPoints'] as num?)?.toInt() ?? _gardenPoints;
    _gardenLevel = (data['gardenLevel'] as num?)?.toInt() ?? _gardenLevel;
    _gardenHouseTier =
        (data['gardenHouseTier'] as num?)?.toInt() ?? _gardenHouseTier;
    _gardenHouseTier = _gardenHouseTier
        .clamp(0, _gardenHouseTiers.length - 1)
        .toInt();
    while (_gardenHouseTier < _gardenHouseTiers.length - 1 &&
        _gardenLevel > _gardenHouseTiers[_gardenHouseTier].maxGardenLevel) {
      _gardenHouseTier += 1;
    }
    _gardenLevel = _gardenLevel
        .clamp(1, _gardenHouseTiers[_gardenHouseTier].maxGardenLevel)
        .toInt();
    _gardenHarvests =
        (data['gardenHarvests'] as num?)?.toInt() ?? _gardenHarvests;
    _gardenMood = ((data['gardenMood'] as num?)?.toInt() ?? _gardenMood)
        .clamp(0, 100)
        .toInt();
    _gardenCompost = max(
      0,
      (data['gardenCompost'] as num?)?.toInt() ?? _gardenCompost,
    );
    _selectedGardenPlant =
        (data['selectedGardenPlant'] as num?)?.toInt() ?? _selectedGardenPlant;
    _selectedGardenWorld =
        (data['selectedGardenWorld'] as num?)?.toInt() ?? _selectedGardenWorld;
    _selectedGardenWorld = _selectedGardenWorld
        .clamp(0, _gardenWorlds.length - 1)
        .toInt();
    _gardenLoginStreak =
        (data['gardenLoginStreak'] as num?)?.toInt() ?? _gardenLoginStreak;
    _gardenLastLoginDay = data['gardenLastLoginDay'] as String?;
    _gardenBestStreak = max(
      _gardenLoginStreak,
      (data['gardenBestStreak'] as num?)?.toInt() ?? _gardenBestStreak,
    );
    _gardenStreakGraceDay = data['gardenStreakGraceDay'] as String?;
    _gardenLastTendedDay = data['gardenLastTendedDay'] as String?;
    _gardenGiftDay = data['gardenGiftDay'] as String?;
    _gardenGiftPlotId = (data['gardenGiftPlotId'] as num?)?.toInt();
    _gardenLastVisitMs = (data['gardenLastVisitMs'] as num?)?.toInt();
    _gardenDailyTaskDay = data['gardenDailyTaskDay'] as String?;
    _gardenWaterBarrelDay = data['gardenWaterBarrelDay'] as String?;
    _gardenHabitatDay = data['gardenHabitatDay'] as String?;
    _gardenDailyPlantDone = data['gardenDailyPlantDone'] == true;
    _gardenDailyWaterDone = data['gardenDailyWaterDone'] == true;
    _gardenDailyCollectDone = data['gardenDailyCollectDone'] == true;
    _gardenDailyTidyDone = data['gardenDailyTidyDone'] == true;
    _gardenDailyRewardClaimed = data['gardenDailyRewardClaimed'] == true;
    _notificationPermissionAsked =
        data['notifAsked'] == true || _notificationPermissionAsked;

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
          plot.upgradeLevel = 1;
          plot.mature = false;
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
          plot.upgradeLevel =
              ((rawPlot['upgradeLevel'] as num?)?.toInt() ?? plot.upgradeLevel)
                  .clamp(1, _maxPlantUpgradeLevel)
                  .toInt();
          plot.mature = rawPlot['mature'] == true || plot.growth >= 1;
        }
        plot.weed = rawPlot['weed'] == true;
        plot.grassCut =
            rawPlot['grassCut'] == true || plot.unlockLevel <= _gardenLevel;
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
      'version': 3,
      'seeds': _seeds,
      'waterCharges': _waterCharges,
      'sunDrops': _sunDrops,
      'gardenPoints': _gardenPoints,
      'gardenLevel': _gardenLevel,
      'gardenHouseTier': _gardenHouseTier,
      'gardenHarvests': _gardenHarvests,
      'gardenMood': _gardenMood,
      'gardenCompost': _gardenCompost,
      'selectedGardenPlant': _selectedGardenPlant,
      'selectedGardenWorld': _selectedGardenWorld,
      'gardenLoginStreak': _gardenLoginStreak,
      'gardenLastLoginDay': _gardenLastLoginDay,
      'gardenBestStreak': _gardenBestStreak,
      'gardenStreakGraceDay': _gardenStreakGraceDay,
      'gardenLastTendedDay': _gardenLastTendedDay,
      'gardenGiftDay': _gardenGiftDay,
      'gardenGiftPlotId': _gardenGiftPlotId,
      'gardenLastVisitMs': _gardenLastVisitMs,
      'gardenDailyTaskDay': _gardenDailyTaskDay,
      'gardenWaterBarrelDay': _gardenWaterBarrelDay,
      'gardenHabitatDay': _gardenHabitatDay,
      'gardenDailyPlantDone': _gardenDailyPlantDone,
      'gardenDailyWaterDone': _gardenDailyWaterDone,
      'gardenDailyCollectDone': _gardenDailyCollectDone,
      'gardenDailyTidyDone': _gardenDailyTidyDone,
      'gardenDailyRewardClaimed': _gardenDailyRewardClaimed,
      'notifAsked': _notificationPermissionAsked,
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
            'grassCut': plot.grassCut,
            'upgradeLevel': plot.upgradeLevel,
            'mature': plot.mature,
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

  void _bumpGardenMood(int amount) {
    if (amount == 0) {
      return;
    }
    _gardenMood = (_gardenMood + amount).clamp(0, 100).toInt();
  }

  bool get _dailyGardenTasksComplete =>
      _gardenDailyPlantDone &&
      _gardenDailyWaterDone &&
      _gardenDailyCollectDone &&
      _gardenDailyTidyDone;

  int get _dailyGardenTaskCount => [
    _gardenDailyPlantDone,
    _gardenDailyWaterDone,
    _gardenDailyCollectDone,
    _gardenDailyTidyDone,
  ].where((done) => done).length;

  String get _gardenMoodLabel {
    if (_gardenMood >= 82) {
      return 'Thriving';
    }
    if (_gardenMood >= 62) {
      return 'Happy';
    }
    if (_gardenMood >= 38) {
      return 'Quiet';
    }
    return 'Neglected';
  }

  bool get _hasDailyPlantTarget => _playerGardenPlots.any(
    (plot) => _isGardenPlotUnlocked(plot) && !plot.weed && !plot.planted,
  );

  bool get _hasDailyCollectTarget => _playerGardenPlots.any(
    (plot) => _isGardenPlotUnlocked(plot) && plot.planted && plot.ready,
  );

  bool get _hasDailyTidyTarget {
    if (_gardenCompost > 0) {
      return true;
    }
    return _playerGardenPlots.any(
      (plot) =>
          (_isGardenPlotUnlocked(plot) && plot.weed) ||
          (!_isGardenPlotUnlocked(plot) &&
              plot.unlockLevel == _gardenLevel + 1 &&
              plot.unlockLevel <= _currentGardenHouse.maxGardenLevel &&
              !plot.grassCut),
    );
  }

  void _normalizeDailyEcosystemGoals() {
    if (!_hasDailyPlantTarget) {
      _gardenDailyPlantDone = true;
    }
    if (!_hasDailyCollectTarget) {
      _gardenDailyCollectDone = true;
    }
    if (!_hasDailyTidyTarget) {
      _gardenDailyTidyDone = true;
    }
  }

  void _resetDailyEcosystemGoals(String today) {
    _gardenDailyTaskDay = today;
    _gardenDailyPlantDone = false;
    _gardenDailyWaterDone = false;
    _gardenDailyCollectDone = false;
    _gardenDailyTidyDone = false;
    _gardenDailyRewardClaimed = false;
    _normalizeDailyEcosystemGoals();
  }

  void _ensureDailyEcosystemGoals(DateTime now) {
    final String today = _dayKey(now);
    if (_gardenDailyTaskDay != today) {
      _resetDailyEcosystemGoals(today);
    }
  }

  bool _completeDailyEcosystemTask(
    GardenEcosystemTask task, {
    int moodBoost = 4,
  }) {
    _ensureDailyEcosystemGoals(_gardenNow);
    bool alreadyDone;
    switch (task) {
      case GardenEcosystemTask.plant:
        alreadyDone = _gardenDailyPlantDone;
        _gardenDailyPlantDone = true;
      case GardenEcosystemTask.water:
        alreadyDone = _gardenDailyWaterDone;
        _gardenDailyWaterDone = true;
      case GardenEcosystemTask.collect:
        alreadyDone = _gardenDailyCollectDone;
        _gardenDailyCollectDone = true;
      case GardenEcosystemTask.tidy:
        alreadyDone = _gardenDailyTidyDone;
        _gardenDailyTidyDone = true;
    }
    if (alreadyDone) {
      return false;
    }
    _bumpGardenMood(moodBoost);
    if (_dailyGardenTasksComplete && !_gardenDailyRewardClaimed) {
      _gardenMessage = 'Daily ecosystem complete - claim the basket';
      _gardenMessageLife = 2.4;
    }
    return true;
  }

  String? _gardenNextDailyAction() {
    if (!_gardenDailyPlantDone) {
      return 'Daily goal: plant one open bed';
    }
    if (!_gardenDailyWaterDone) {
      return 'Daily goal: water a plant or tap the rain barrel';
    }
    if (!_gardenDailyCollectDone) {
      return 'Daily goal: gather one ready bloom';
    }
    if (!_gardenDailyTidyDone) {
      return 'Daily goal: clear weeds or mow a new meadow';
    }
    if (!_gardenDailyRewardClaimed) {
      return 'Daily care complete - claim your reward basket';
    }
    return null;
  }

  void _claimDailyEcosystemReward() {
    setState(() {
      _ensureDailyEcosystemGoals(_gardenNow);
      if (!_dailyGardenTasksComplete) {
        _gardenMessage = _gardenNextDailyAction() ?? 'Keep tending the garden';
        _gardenMessageLife = 2.2;
        return;
      }
      if (_gardenDailyRewardClaimed) {
        _gardenMessage = 'Daily basket already collected';
        _gardenMessageLife = 1.9;
        return;
      }
      final int seedReward = 80 + _gardenLoginStreak * 10 + _gardenLevel * 15;
      final int pointReward = 35 + _gardenMood ~/ 2;
      _gardenDailyRewardClaimed = true;
      _seeds += seedReward;
      _gardenPoints += pointReward;
      _score += pointReward;
      _waterCharges = min(12, _waterCharges + 1);
      _bumpGardenMood(6);
      _gardenMessage =
          'Daily basket: +$seedReward seeds, +$pointReward pts, +1 water';
      _gardenMessageLife = 3.0;
      _playSfx(_sfxComboSpark, volume: 0.6);
    });
    _queueGardenSave();
  }

  void _collectGardenWaterBarrel() {
    setState(() {
      final String today = _dayKey(_gardenNow);
      if (_gardenWaterBarrelDay == today) {
        _gardenMessage = 'Rain barrel refills tomorrow';
        _gardenMessageLife = 1.9;
        return;
      }
      _gardenWaterBarrelDay = today;
      _waterCharges = min(12, _waterCharges + 1);
      _completeDailyEcosystemTask(GardenEcosystemTask.water, moodBoost: 4);
      _gardenMessage = _dailyGardenTasksComplete
          ? 'Rain barrel: +1 water - reward basket ready'
          : 'Rain barrel: +1 water';
      _gardenMessageLife = 2.4;
      _playSfx(_sfxComboSpark, volume: 0.45);
    });
    _queueGardenSave();
  }

  void _collectGardenCompost() {
    setState(() {
      if (_gardenCompost <= 0) {
        _gardenMessage = 'Clear a weed or cut grass to make compost';
        _gardenMessageLife = 2.2;
        return;
      }
      final int compostUsed = _gardenCompost;
      final int seedReward = compostUsed * 24 + _gardenMood ~/ 3;
      final int pointReward = compostUsed * 12;
      _gardenCompost = 0;
      _seeds += seedReward;
      _gardenPoints += pointReward;
      _score += pointReward;
      _completeDailyEcosystemTask(GardenEcosystemTask.tidy, moodBoost: 5);
      _gardenMessage = 'Compost mixed: +$seedReward seeds, +$pointReward pts';
      _gardenMessageLife = 2.6;
      _playSfx(_sfxCrispLeaf, volume: 0.48);
    });
    _queueGardenSave();
  }

  void _visitGardenJournal() {
    setState(() {
      final String today = _dayKey(_gardenNow);
      if (_gardenHabitatDay == today) {
        _gardenMessage = 'Garden journal is complete for today';
        _gardenMessageLife = 1.9;
        return;
      }
      final int pointReward = 25 + _gardenLevel * 10 + _gardenMood ~/ 4;
      _gardenHabitatDay = today;
      _gardenPoints += pointReward;
      _score += pointReward;
      if (_gardenMood >= 82) {
        _sunDrops = min(12, _sunDrops + 1);
      }
      _bumpGardenMood(3);
      _gardenMessage = _gardenMood >= 82
          ? 'Journal bonus: +$pointReward pts, +1 sun'
          : 'Journal bonus: +$pointReward pts';
      _gardenMessageLife = 2.4;
      _playSfx(_sfxComboSpark, volume: 0.4);
    });
    _queueGardenSave();
  }

  void _syncDailyGarden(DateTime now) {
    final String today = _dayKey(now);
    _ensureDailyEcosystemGoals(now);
    if (_gardenLastLoginDay == today) {
      return;
    }

    final String? previousDay = _gardenLastLoginDay;
    final DateTime? previousDate = _dateFromDayKey(previousDay);
    final int gapDays = previousDate == null
        ? 0
        : _daysBetween(previousDate, now);
    _dailySummaryLines = [];

    bool streakIncreased = false;
    if (previousDate == null) {
      // First visit: keep the starting streak.
    } else if (gapDays <= 1) {
      _gardenLoginStreak += 1;
      streakIncreased = true;
    } else if (gapDays == 2 && _streakGraceAvailable(now)) {
      _gardenStreakGraceDay = today;
      _dailySummaryLines.add(
        'Your streak rested a day - still day $_gardenLoginStreak',
      );
    } else {
      _gardenLoginStreak = 1;
    }
    _gardenBestStreak = max(_gardenBestStreak, _gardenLoginStreak);
    _gardenLastLoginDay = today;

    if (previousDay != null) {
      final bool tendedYesterday = _gardenLastTendedDay == previousDay;
      if (gapDays <= 1 && tendedYesterday) {
        _bumpGardenMood(5);
      } else if (gapDays > 0) {
        _bumpGardenMood(-min(28, 7 * gapDays));
      }
    }
    _dailySummaryLines.add('Daily ecosystem goals refreshed');

    if (streakIncreased) {
      switch (_gardenLoginStreak) {
        case 3:
          _sunDrops = min(12, _sunDrops + 2);
          _dailySummaryLines.add('Day 3 streak: +2 sun drops');
        case 7:
          _seeds += 120;
          _dailySummaryLines.add('Day 7 streak: +120 seeds');
        case 14:
          _seeds += 250;
          _dailySummaryLines.add('Day 14 streak: +250 seeds');
        case 30:
          _seeds += 500;
          _dailySummaryLines.add('Day 30 streak: +500 seeds');
      }
    }

    final int waterGrant = _dailyWaterGrant + min(2, _gardenLoginStreak ~/ 7);
    final int sunGrant = _dailySunGrant + (_gardenLoginStreak >= 14 ? 1 : 0);
    _waterCharges = min(12, _waterCharges + waterGrant);
    _sunDrops = min(12, _sunDrops + sunGrant);
    _dailySummaryLines.add(
      'Morning supplies: +$waterGrant water, +$sunGrant sun',
    );

    for (final plot in _playerGardenPlots) {
      if (plot.planted) {
        plot.watered = plot.lastWateredDay == today;
      }
    }

    final DateTime? tendedDate = _dateFromDayKey(_gardenLastTendedDay);
    if (tendedDate != null &&
        _daysBetween(tendedDate, now) == 1 &&
        _gardenGiftPlotId == null) {
      final List<PlayerGardenPlot> unlocked = _playerGardenPlots
          .where(_isGardenPlotUnlocked)
          .toList();
      if (unlocked.isNotEmpty) {
        _gardenGiftPlotId = unlocked[_random.nextInt(unlocked.length)].id;
        _gardenGiftDay = today;
        _dailySummaryLines.add('The ninja left a gift by a plot');
      }
    }

    if (gapDays >= 3) {
      _waterCharges = min(12, _waterCharges + 2);
      _sunDrops = min(12, _sunDrops + 1);
      _dailySummaryLines.insert(
        0,
        'The ninja kept your garden safe while you were away',
      );
    }

    if (previousDay != null) {
      _spawnNeglectWeeds(maxWeeds: gapDays >= 3 ? 1 : 2);
    }
    _queueGardenSave();
  }

  bool _streakGraceAvailable(DateTime now) {
    final DateTime? lastGrace = _dateFromDayKey(_gardenStreakGraceDay);
    return lastGrace == null || _daysBetween(lastGrace, now) >= 7;
  }

  void _spawnNeglectWeeds({int maxWeeds = 2}) {
    final int shieldCount = _playerGardenPlots
        .where(
          (plot) =>
              plot.planted &&
              plot.plantIndex != null &&
              _gardenPlantOptionAt(plot.plantIndex!).name == 'Shield Flower',
        )
        .length;
    final int targetWeeds = max(
      0,
      min(maxWeeds, _maxGardenWeeds) - (shieldCount > 0 ? 1 : 0),
    );
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
      _gardenMatrix(
        scale: _gardenInitialScale,
        translateX: _gardenInitialTranslateX,
        translateY: _gardenInitialTranslateY,
      ),
    );
    _gardenMapController.addListener(_clampGardenTransform);
    _ticker = createTicker(_tick)..start();
    _primeAudio();
    unawaited(_initNotifications());
    unawaited(_loadGardenSave());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForcedPlayUpdate());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _gardenMapController.removeListener(_clampGardenTransform);
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
        unawaited(_checkForcedPlayUpdate());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_phase == GamePhase.garden) {
          _gardenLastVisitMs = _gardenNow.millisecondsSinceEpoch;
          _queueGardenSave();
        }
        if (state == AppLifecycleState.paused) {
          unawaited(_syncGardenNotifications());
        }
        unawaited(_musicPlayer.pause());
        break;
      case AppLifecycleState.detached:
        unawaited(_syncGardenNotifications());
        unawaited(_musicPlayer.stop());
        break;
    }
  }

  Future<void> _checkForcedPlayUpdate() async {
    if (!_supportsPlayInAppUpdates ||
        _forceUpdateCheckInFlight ||
        _forceUpdateState == ForceUpdateState.updating) {
      return;
    }

    _forceUpdateCheckInFlight = true;
    final bool retryingFromBlock =
        _forceUpdateState == ForceUpdateState.blocked;
    if (retryingFromBlock && mounted) {
      setState(() {
        _forceUpdateState = ForceUpdateState.checking;
        _forceUpdateMessage = 'Checking for the latest update...';
      });
    }

    try {
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();
      if (!mounted) {
        return;
      }

      final bool updateRequired =
          updateInfo.updateAvailability == UpdateAvailability.updateAvailable ||
          updateInfo.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;

      if (!updateRequired) {
        setState(() {
          _forceUpdateState = ForceUpdateState.idle;
        });
        return;
      }

      final bool canStartImmediate =
          updateInfo.immediateUpdateAllowed ||
          updateInfo.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;

      if (!canStartImmediate) {
        setState(() {
          _forceUpdateState = ForceUpdateState.blocked;
          _forceUpdateMessage =
              'A new Garden Ninja version is required. Update from Google Play to continue.';
        });
        return;
      }

      setState(() {
        _forceUpdateState = ForceUpdateState.updating;
        _forceUpdateMessage =
            'Installing the latest Garden Ninja update from Google Play...';
      });
      unawaited(_musicPlayer.pause());

      final AppUpdateResult result = await InAppUpdate.performImmediateUpdate();
      if (!mounted) {
        return;
      }

      if (result == AppUpdateResult.success) {
        setState(() {
          _forceUpdateState = ForceUpdateState.idle;
        });
        return;
      }

      setState(() {
        _forceUpdateState = ForceUpdateState.blocked;
        _forceUpdateMessage = result == AppUpdateResult.userDeniedUpdate
            ? 'Update required. Install the latest version to keep playing.'
            : 'The required update could not start. Please try again.';
      });
    } on MissingPluginException {
      _clearForcedUpdateForNonPlayBuild();
    } on PlatformException catch (error) {
      _handleForcedUpdateCheckFailure(error.message);
    } catch (error) {
      _handleForcedUpdateCheckFailure(error.toString());
    } finally {
      _forceUpdateCheckInFlight = false;
    }
  }

  void _handleForcedUpdateCheckFailure(String? reason) {
    if (!mounted) {
      return;
    }
    if (!_supportsPlayInAppUpdates) {
      _clearForcedUpdateForNonPlayBuild();
      return;
    }
    setState(() {
      _forceUpdateState = ForceUpdateState.blocked;
      _forceUpdateMessage = reason == null || reason.trim().isEmpty
          ? 'Could not verify the latest Play Store version. Update from Google Play to continue.'
          : 'Could not verify the latest Play Store version. Open Google Play, update Garden Ninja, then try again.';
    });
  }

  void _clearForcedUpdateForNonPlayBuild() {
    if (!mounted) {
      return;
    }
    setState(() {
      _forceUpdateState = ForceUpdateState.idle;
    });
  }

  Future<void> _initNotifications() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _notificationsReady = true;
    } catch (_) {
      // Notifications are a bonus; the garden works fine without them.
      _notificationsReady = false;
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (!_notificationsReady || _notificationPermissionAsked) {
      return;
    }
    _notificationPermissionAsked = true;
    _queueGardenSave();
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    } catch (_) {}
  }

  Future<void> _syncGardenNotifications() async {
    if (!_notificationsReady || !_notificationPermissionAsked) {
      return;
    }
    try {
      await _notifications.cancelAll();
      final DateTime now = _gardenNow;

      PlayerGardenPlot? soonestPlot;
      DateTime? soonestAt;
      for (final plot in _playerGardenPlots) {
        if (!_isGardenPlotUnlocked(plot) || !plot.planted || plot.ready) {
          continue;
        }
        final DateTime? readyAt = plot.readyAt;
        if (readyAt == null ||
            readyAt.isBefore(now.add(const Duration(minutes: 5)))) {
          continue;
        }
        if (soonestAt == null || readyAt.isBefore(soonestAt)) {
          soonestAt = readyAt;
          soonestPlot = plot;
        }
      }
      if (soonestPlot != null && soonestAt != null) {
        await _notifications.zonedSchedule(
          id: _notifIdNextBloom,
          title: 'Garden Ninja',
          body:
              '${_plantOptionForPlot(soonestPlot).name} is ready to gather '
              'in your garden',
          scheduledDate: tz.TZDateTime.from(soonestAt, tz.UTC),
          notificationDetails: _gardenNotificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }

      if (_gardenLastTendedDay == _dayKey(now)) {
        final DateTime giftMorning = DateTime(
          now.year,
          now.month,
          now.day,
          9,
          30,
        ).add(const Duration(days: 1));
        await _notifications.zonedSchedule(
          id: _notifIdMorningGift,
          title: 'Garden Ninja',
          body: 'The ninja left a gift in your garden',
          scheduledDate: tz.TZDateTime.from(giftMorning, tz.UTC),
          notificationDetails: _gardenNotificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }

      final DateTime awhileAway = now.add(const Duration(days: 3));
      final DateTime comebackEvening = DateTime(
        awhileAway.year,
        awhileAway.month,
        awhileAway.day,
        18,
        30,
      );
      await _notifications.zonedSchedule(
        id: _notifIdComeback,
        title: 'Garden Ninja',
        body: 'Your garden misses you - the flowers could use some water',
        scheduledDate: tz.TZDateTime.from(comebackEvening, tz.UTC),
        notificationDetails: _gardenNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Scheduling problems must never disturb gameplay.
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
    final bool leavingGarden = _phase == GamePhase.garden;
    setState(() {
      if (leavingGarden) {
        _gardenLastVisitMs = _gardenNow.millisecondsSinceEpoch;
        _showGardenWelcome = false;
        _showGardenHousePanel = false;
      }
      _phase = GamePhase.upgrades;
    });
    if (leavingGarden) {
      _restoreMusicAfterGarden();
      _queueGardenSave();
      unawaited(_syncGardenNotifications());
    }
    unawaited(_musicPlayer.setVolume(0.32));
  }

  void _openGarden() {
    _ensureMusicStarted();
    setState(() {
      final DateTime now = _gardenNow;
      final int? lastVisitMs = _gardenLastVisitMs;
      _syncDailyGarden(now);
      _refreshAllGardenPlots(now);
      _phase = GamePhase.garden;
      _gardenTool = GardenTool.plant;
      _gardenMessageLife = 0;
      _gardenSessionWeedSpawns = 0;
      _showGardenHousePanel = false;
      _gardenWeedTimer = max(_gardenWeedTimer, 60);

      final bool longAway =
          lastVisitMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastVisitMs)) >=
              _gardenWelcomeAfter;
      if (longAway) {
        _gardenWelcomeLines = [
          for (final plot in _playerGardenPlots.where(
            (plot) => plot.planted && _isGardenPlotUnlocked(plot),
          ))
            plot.ready
                ? '${_plantOptionForPlot(plot).name} is ready to gather'
                : '${_plantOptionForPlot(plot).name} is '
                      '${(plot.growth * 100).round()}% grown',
          ..._dailySummaryLines,
        ].take(6).toList();
        _showGardenWelcome = _gardenWelcomeLines.isNotEmpty;
        _dailySummaryLines = [];
      }
      _gardenLastVisitMs = now.millisecondsSinceEpoch;

      if (_musicEnabled && _selectedMusicTrack != _gardenCalmMusicTrack) {
        _musicTrackBeforeGarden = _selectedMusicTrack;
        _selectedMusicTrack = _gardenCalmMusicTrack;
        unawaited(_playSelectedMusic());
      }
    });
    _queueGardenSave();
    unawaited(_musicPlayer.setVolume(0.3));
  }

  void _closeGardenWelcome() {
    setState(() {
      _showGardenWelcome = false;
      _gardenWelcomeLines = const [];
    });
  }

  void _openGardenHousePanel() {
    setState(() {
      _gardenNurseryPlotId = null;
      _showGardenHousePanel = true;
      _guideGardenCaretaker(const Offset(460, 452));
      _gardenMessageLife = 0;
    });
    _playSfx(_sfxCrispLeaf, volume: 0.4);
  }

  void _closeGardenHousePanel() {
    setState(() {
      _showGardenHousePanel = false;
      _gardenMessage = 'Tap the house whenever you are ready to upgrade';
      _gardenMessageLife = 1.9;
    });
  }

  void _restoreMusicAfterGarden() {
    final int? previous = _musicTrackBeforeGarden;
    if (previous == null) {
      return;
    }
    _musicTrackBeforeGarden = null;
    _selectedMusicTrack = previous;
    unawaited(_playSelectedMusic());
  }

  void _goHome() {
    final bool leavingGarden = _phase == GamePhase.garden;
    setState(() {
      if (leavingGarden) {
        _gardenLastVisitMs = _gardenNow.millisecondsSinceEpoch;
        _showGardenWelcome = false;
        _showGardenHousePanel = false;
      }
      _phase = GamePhase.home;
      _tutorialMode = false;
    });
    if (leavingGarden) {
      _restoreMusicAfterGarden();
      _queueGardenSave();
      unawaited(_syncGardenNotifications());
    }
    unawaited(_musicPlayer.setVolume(0.34));
  }

  bool _isGardenPlotUnlocked(PlayerGardenPlot plot) {
    return plot.unlockLevel <= _gardenLevel &&
        plot.unlockLevel <= _currentGardenHouse.maxGardenLevel;
  }

  bool _isGardenPlotVisible(PlayerGardenPlot plot) {
    return plot.unlockLevel <= _currentGardenHouse.maxGardenLevel + 1;
  }

  int get _gardenExpandCost => 260 + ((_gardenLevel - 1) * 180);

  GardenHouseTier get _currentGardenHouse =>
      _gardenHouseTiers[_gardenHouseTier.clamp(
        0,
        _gardenHouseTiers.length - 1,
      )];

  GardenHouseTier? get _nextGardenHouse =>
      _gardenHouseTier < _gardenHouseTiers.length - 1
      ? _gardenHouseTiers[_gardenHouseTier + 1]
      : null;

  int get _maxGardenLevel => _currentGardenHouse.maxGardenLevel;

  int get _maxPlantUpgradeLevel => min(4, _gardenHouseTier + 2);

  int get _currentHousePlantCap => min(4, _gardenHouseTier + 2);

  Iterable<PlayerGardenPlot> get _currentHouseGardenPlots => _playerGardenPlots
      .where((plot) => plot.unlockLevel <= _currentGardenHouse.maxGardenLevel);

  String? _gardenHouseUpgradeBlocker(
    GardenHouseTier current,
    GardenHouseTier next, {
    bool checkCost = true,
  }) {
    if (_gardenLevel < current.maxGardenLevel) {
      return 'Expand every ${current.name} bed first';
    }

    final PlayerGardenPlot? grassyPlot = _currentHouseGardenPlots
        .where((plot) => !plot.grassCut)
        .firstOrNull;
    if (grassyPlot != null) {
      return 'Cut all grass before upgrading the townhouse';
    }

    final PlayerGardenPlot? weedPlot = _currentHouseGardenPlots
        .where((plot) => plot.weed)
        .firstOrNull;
    if (weedPlot != null) {
      return 'Clear every weed before upgrading the townhouse';
    }

    final PlayerGardenPlot? emptyPlot = _currentHouseGardenPlots
        .where((plot) => !plot.planted)
        .firstOrNull;
    if (emptyPlot != null) {
      return 'Plant every ${current.name} bed first';
    }

    final int targetLevel = _currentHousePlantCap;
    final PlayerGardenPlot? lowPlant = _currentHouseGardenPlots
        .where((plot) => plot.upgradeLevel < targetLevel)
        .firstOrNull;
    if (lowPlant != null) {
      return 'Upgrade all ${current.name} plants to Lv $targetLevel';
    }

    if (checkCost &&
        (_gardenPoints < next.unlockPoints || _seeds < next.seedCost)) {
      return '${next.name}: need ${_formatNumber(next.unlockPoints)} pts and ${_formatNumber(next.seedCost)} seeds';
    }

    return null;
  }

  int _plantUpgradeCost(PlayerGardenPlot plot) {
    final GardenPlantOption option = _plantOptionForPlot(plot);
    return 90 + option.seedCost ~/ 2 + plot.upgradeLevel * 85;
  }

  int get _activeGardenWeeds => _playerGardenPlots
      .where((plot) => _isGardenPlotUnlocked(plot) && plot.weed)
      .length;

  int get _maxGardenWeeds =>
      min(4, 1 + _gardenLevel + (_gardenMood < 35 ? 1 : 0));

  GardenWorld get _currentGardenWorld => _gardenWorldAt(_selectedGardenWorld);

  GardenWorld _gardenWorldAt(int index) {
    final int safeIndex = index.clamp(0, _gardenWorlds.length - 1).toInt();
    return _gardenWorlds[safeIndex];
  }

  bool _isGardenWorldUnlocked(int index) {
    if (index <= 0) {
      return true;
    }
    return _gardenPoints >= _gardenWorldAt(index).unlockPoints;
  }

  int get _unlockedGardenWorldCount {
    int count = 0;
    for (int i = 0; i < _gardenWorlds.length; i += 1) {
      if (_isGardenWorldUnlocked(i)) {
        count += 1;
      }
    }
    return count;
  }

  void _selectGardenWorld(int direction) {
    final int nextIndex =
        (_selectedGardenWorld + direction) % _gardenWorlds.length;
    final int wrappedIndex = nextIndex < 0
        ? nextIndex + _gardenWorlds.length
        : nextIndex;
    final GardenWorld world = _gardenWorldAt(wrappedIndex);

    setState(() {
      if (_isGardenWorldUnlocked(wrappedIndex)) {
        _selectedGardenWorld = wrappedIndex;
        _gardenMessage = '${world.name}: ${world.bonus}';
        _gardenMessageLife = 2.2;
        _playSfx(_sfxComboSpark, volume: 0.42);
      } else {
        _gardenMessage =
            '${world.name} unlocks at ${_formatNumber(world.unlockPoints)} pts';
        _gardenMessageLife = 2.4;
        _playSfx(_sfxCrispLeaf, volume: 0.28);
      }
    });
    _queueGardenSave();
  }

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

  bool _gardenOptionIsTree(GardenPlantOption option) {
    return option.name.endsWith('Tree');
  }

  String _gardenHarvestLabel(GardenPlantOption option) {
    return _gardenOptionIsTree(option) ? 'fruit' : 'blooms';
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
      plot.mature = false;
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
    if (remainingMs <= 0) {
      plot.mature = true;
      plot.growth = 1;
      return;
    }
    final double waterGate = _gardenOptionIsTree(option) ? 0.84 : 0.92;
    final double timedGrowth = plot.watered || progress < waterGate
        ? progress
        : min(progress, waterGate);
    final double matureFloor = _gardenOptionIsTree(option) ? 0.78 : 0.72;
    plot.growth = plot.mature ? max(timedGrowth, matureFloor) : timedGrowth;
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
      return 'Snip me';
    }
    if (!plot.planted) {
      return _gardenTool == GardenTool.plant ? 'Plant here' : 'Empty plot';
    }
    if (_gardenTool == GardenTool.clear &&
        plot.upgradeLevel < _maxPlantUpgradeLevel) {
      return 'Upgrade Lv ${plot.upgradeLevel + 1}';
    }
    if (plot.ready) {
      return 'Ready';
    }
    if (!_isWateredToday(plot, now)) {
      return 'Water me';
    }
    return _durationLabel(_remainingGardenTime(plot, now));
  }

  void _guideGardenCaretaker(Offset target) {
    _gardenCaretakerTarget = Offset(
      target.dx.clamp(74, _playerGardenWidth - 74).toDouble(),
      target.dy.clamp(450, _playerGardenHeight - 82).toDouble(),
    );
  }

  void _guideGardenCaretakerToPlot(PlayerGardenPlot plot) {
    final double side = plot.id.isEven ? -1 : 1;
    _guideGardenCaretaker(
      Offset(plot.position.dx + side * 92, plot.position.dy + 74),
    );
  }

  void _stepGardenCaretaker(double dt) {
    final Offset delta = _gardenCaretakerTarget - _gardenCaretakerPosition;
    final double distance = delta.distance;
    if (distance <= 1.5) {
      _gardenCaretakerPosition = _gardenCaretakerTarget;
      _gardenCaretakerMoving = false;
      return;
    }
    _gardenCaretakerMoving = true;
    final double step = min(distance, 176 * dt);
    _gardenCaretakerPosition += delta / distance * step;
  }

  void _stepPlayerGarden(double dt) {
    final DateTime now = _gardenNow;
    _syncDailyGarden(now);
    if (_dailySummaryLines.isNotEmpty && !_showGardenWelcome) {
      _gardenMessage = _dailySummaryLines.first;
      _gardenMessageLife = 3.0;
      _dailySummaryLines = [];
    }
    _refreshAllGardenPlots(now);
    _stepGardenCaretaker(dt);
    _gardenMessageLife = max(0, _gardenMessageLife - dt);
    _gardenWeedTimer -= dt;

    for (final plot in _playerGardenPlots) {
      plot.sparkle = max(0, plot.sparkle - dt * 1.8);
    }

    final String today = _dayKey(now);
    if (_gardenLastTendedDay != today && _isGardenTendedNow(now)) {
      _gardenLastTendedDay = today;
      _seeds += _gardenTendedReward;
      _bumpGardenMood(8);
      _gardenMessage = 'Garden tended! +$_gardenTendedReward seeds';
      _gardenMessageLife = 2.8;
      _playSfx(_sfxComboSpark, volume: 0.5);
      _queueGardenSave();
    }

    if (_gardenWeedTimer <= 0) {
      if (_activeGardenWeeds < 1 && _gardenSessionWeedSpawns < 1) {
        _spawnPlayerGardenWeed(showMessage: false);
        _gardenSessionWeedSpawns += 1;
      }
      final double moodDelay = _gardenMood >= 80
          ? 32
          : _gardenMood < 35
          ? -22
          : 0;
      _gardenWeedTimer = max(
        45,
        90.0 + _random.nextDouble() * 60.0 + moodDelay,
      );
    }
  }

  bool _isGardenTendedNow(DateTime now) {
    bool anyPlanted = false;
    for (final plot in _playerGardenPlots) {
      if (!_isGardenPlotUnlocked(plot)) {
        continue;
      }
      if (plot.weed) {
        return false;
      }
      if (plot.planted) {
        anyPlanted = true;
        if (!plot.ready && !_isWateredToday(plot, now)) {
          return false;
        }
      }
    }
    return anyPlanted;
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
      _gardenMessage = 'A wild dandelion drifted in';
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
        GardenTool.clear => 'Mow meadow, clear weeds, or upgrade plants',
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
    _showGardenHousePanel = false;
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
      _guideGardenCaretakerToPlot(plot);
      if (!_isGardenPlotUnlocked(plot)) {
        _tryExpandGarden(plot);
        return;
      }

      if (plot.weed) {
        _clearGardenWeed(plot);
        return;
      }
      if (plot.planted && _gardenTool == GardenTool.clear) {
        _upgradeGardenPlant(plot);
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

  void _tryExpandGarden(PlayerGardenPlot plot) {
    if (plot.unlockLevel > _currentGardenHouse.maxGardenLevel) {
      final GardenHouseTier? nextHouse = _nextGardenHouse;
      _gardenMessage = nextHouse == null
          ? 'Backyard fully expanded'
          : 'Upgrade your home to reach this land';
      _gardenMessageLife = 2.2;
      return;
    }
    if (_gardenLevel >= _maxGardenLevel) {
      _gardenMessage = 'Backyard fully expanded';
      _gardenMessageLife = 2.0;
      return;
    }
    if (plot.unlockLevel > _gardenLevel + 1) {
      _gardenMessage = 'Shape the nearer garden zone first';
      _gardenMessageLife = 2.2;
      return;
    }
    if (!plot.grassCut) {
      if (_gardenTool != GardenTool.clear) {
        _gardenMessage = 'Use Clear to mow this meadow first';
        _gardenMessageLife = 2.2;
        return;
      }
      plot.grassCut = true;
      plot.sparkle = 1;
      _seeds += 14;
      _gardenCompost = min(24, _gardenCompost + 1);
      _completeDailyEcosystemTask(GardenEcosystemTask.tidy, moodBoost: 5);
      _gardenMessage =
          'Meadow mowed! +14 seeds, +1 compost. Tap again to shape the zone';
      _gardenMessageLife = 2.5;
      _playSfx(_sfxBambooBlade, volume: 0.58);
      _queueGardenSave();
      return;
    }
    if (_seeds < _gardenExpandCost) {
      _gardenMessage = 'Need $_gardenExpandCost seeds to expand';
      _gardenMessageLife = 2.2;
      return;
    }

    _seeds -= _gardenExpandCost;
    _gardenLevel += 1;
    _bumpGardenMood(4);
    for (final unlockedPlot in _playerGardenPlots) {
      if (unlockedPlot.unlockLevel == _gardenLevel) {
        unlockedPlot.sparkle = 1;
      }
    }
    _gardenMessage = 'New garden zone unlocked! Tap it to plant';
    _gardenMessageLife = 2.6;
    _playSfx(_sfxComboSpark, volume: 0.62);
    _queueGardenSave();
  }

  void _tryUpgradeGardenHouse() {
    final GardenHouseTier current = _currentGardenHouse;
    final GardenHouseTier? next = _nextGardenHouse;
    if (next == null) {
      _gardenMessage = 'Garden Villa is the final townhouse';
      _gardenMessageLife = 2.2;
      _playSfx(_sfxCrispLeaf, volume: 0.34);
      return;
    }
    final String? blocker = _gardenHouseUpgradeBlocker(current, next);
    if (blocker != null) {
      _gardenMessage = blocker;
      _gardenMessageLife = 2.7;
      _playSfx(_sfxCrispLeaf, volume: 0.34);
      return;
    }

    _seeds -= next.seedCost;
    _gardenHouseTier += 1;
    _bumpGardenMood(12);
    for (final plot in _playerGardenPlots) {
      if (plot.unlockLevel == _gardenLevel + 1) {
        plot.sparkle = 1;
      }
    }
    _gardenMessage = '${next.name} upgraded: ${next.bonus}';
    _gardenMessageLife = 2.8;
    _playSfx(_sfxComboSpark, volume: 0.64);
    _queueGardenSave();
  }

  Matrix4 _gardenMatrix({
    required double scale,
    required double translateX,
    required double translateY,
  }) {
    return Matrix4.identity()
      ..storage[0] = scale
      ..storage[5] = scale
      ..storage[12] = translateX
      ..storage[13] = translateY;
  }

  void _clampGardenTransform() {
    if (_correctingGardenTransform) {
      return;
    }
    final Matrix4 current = _gardenMapController.value;
    final double scale = current.storage[0]
        .abs()
        .clamp(_gardenMinScale, _gardenMaxScale)
        .toDouble();
    final double scaledWidth = _playerGardenWidth * scale;
    final double scaledHeight = _playerGardenHeight * scale;
    final double minX = min(0, _worldWidth - scaledWidth).toDouble();
    const double maxX = 0;
    final double minY = min(0, _worldHeight - scaledHeight).toDouble();
    const double maxY = _gardenInitialTranslateY;
    final double translateX = current.storage[12].clamp(minX, maxX).toDouble();
    final double translateY = current.storage[13].clamp(minY, maxY).toDouble();

    if ((current.storage[0] - scale).abs() < 0.001 &&
        (current.storage[5] - scale).abs() < 0.001 &&
        (current.storage[12] - translateX).abs() < 0.1 &&
        (current.storage[13] - translateY).abs() < 0.1) {
      return;
    }

    final Matrix4 corrected = Matrix4.copy(current)
      ..storage[0] = scale
      ..storage[5] = scale
      ..storage[12] = translateX
      ..storage[13] = translateY;
    _correctingGardenTransform = true;
    _gardenMapController.value = corrected;
    _correctingGardenTransform = false;
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
          ? '${option.name} ${_gardenHarvestLabel(option)} ready'
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
    plot.grassCut = true;
    plot.upgradeLevel = 1;
    plot.mature = false;
    plot.sparkle = 1;
    _gardenMessage =
        '${option.name} planted: ready in ${_durationLabel(option.growDuration)}';
    _gardenMessageLife = 2.0;
    _completeDailyEcosystemTask(GardenEcosystemTask.plant, moodBoost: 5);
    _playSfx(_sfxCrispLeaf, volume: 0.48);
    unawaited(_ensureNotificationPermission());
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
      _gardenMessage =
          'Tap to collect ${option.name} ${_gardenHarvestLabel(option)}';
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
    _completeDailyEcosystemTask(GardenEcosystemTask.water, moodBoost: 4);
    _playSfx(_sfxComboSpark, volume: 0.5);
    unawaited(_ensureNotificationPermission());
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
      _gardenMessage =
          'Tap to collect ${option.name} ${_gardenHarvestLabel(option)}';
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
    _bumpGardenMood(2);
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
    _gardenCompost = min(24, _gardenCompost + 1);
    _completeDailyEcosystemTask(GardenEcosystemTask.tidy, moodBoost: 6);
    _gardenMessage = plot.planted
        ? '+18 seeds, +1 compost - all tidy'
        : '+18 seeds, +1 compost - tap plot to plant';
    _gardenMessageLife = 2.2;
    _playSfx(_sfxBambooBlade, volume: 0.62);
  }

  void _upgradeGardenPlant(PlayerGardenPlot plot) {
    if (!plot.planted) {
      _gardenMessage = 'Plant something before pruning';
      _gardenMessageLife = 1.9;
      return;
    }
    final GardenPlantOption option = _plantOptionForPlot(plot);
    if (plot.upgradeLevel >= _maxPlantUpgradeLevel) {
      final GardenHouseTier? nextHouse = _nextGardenHouse;
      _gardenMessage = nextHouse == null
          ? '${option.name} is max level'
          : 'Upgrade house for Lv ${plot.upgradeLevel + 1} plants';
      _gardenMessageLife = 2.2;
      return;
    }
    final int cost = _plantUpgradeCost(plot);
    if (_seeds < cost) {
      _gardenMessage = 'Need ${_formatNumber(cost)} seeds to upgrade plant';
      _gardenMessageLife = 2.2;
      return;
    }

    _seeds -= cost;
    plot.upgradeLevel += 1;
    plot.sparkle = 1;
    final DateTime now = _gardenNow;
    if (!plot.ready) {
      plot.readyAt = plot.readyAt?.subtract(
        Duration(
          milliseconds: (option.growDuration.inMilliseconds * 0.08).round(),
        ),
      );
      _refreshGardenPlot(plot, now);
    }
    _gardenMessage =
        '${option.name} upgraded to Lv ${plot.upgradeLevel}: better rewards';
    _gardenMessageLife = 2.5;
    _bumpGardenMood(3);
    _playSfx(_sfxComboSpark, volume: 0.58);
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
    final int upgradeBonus = plot.upgradeLevel - 1;
    final int pointReward =
        option.points + ((plot.unlockLevel - 1) * 35) + (upgradeBonus * 60);
    final int seedReward =
        _gardenSeedRewardFor(option) +
        ((plot.unlockLevel - 1) * 10) +
        (upgradeBonus * 24);
    _gardenPoints += pointReward;
    _score += pointReward;
    _seeds += seedReward;
    if (option.name == 'Blue Bell') {
      _waterCharges = min(12, _waterCharges + 1);
    } else if (option.name == 'Cherry') {
      _sunDrops = min(12, _sunDrops + 1);
    } else if (option.name == 'Shield Flower') {
      _gardenWeedTimer += 18;
    } else if (option.name == 'Apple Tree') {
      _waterCharges = min(12, _waterCharges + 2);
    } else if (option.name == 'Lemon Tree') {
      _sunDrops = min(12, _sunDrops + 2);
    } else if (option.name == 'Orange Tree') {
      _waterCharges = min(12, _waterCharges + 1);
      _sunDrops = min(12, _sunDrops + 1);
    } else if (option.name == 'Maple Tree') {
      _gardenWeedTimer += 36;
    }
    _gardenHarvests += 1;
    if (_gardenHarvests % 2 == 0) {
      _sunDrops += 1;
    }
    if (_gardenHarvests % 3 == 0) {
      _gardenCompost = min(24, _gardenCompost + 1);
    }
    final DateTime now = _gardenNow;
    plot.plantedAt = now;
    plot.readyAt = now.add(option.growDuration);
    plot.lastWateredDay = null;
    plot.mature = true;
    plot.growth = _gardenOptionIsTree(option) ? 0.82 : 0.76;
    plot.watered = false;
    plot.sparkle = 1;
    final String harvestLabel = _gardenHarvestLabel(option);
    if (_gardenOptionIsTree(option)) {
      _gardenMessage =
          'Collected $harvestLabel: +$pointReward pts, +$seedReward seeds';
    } else {
      _gardenMessage =
          'Collected blooms: +$pointReward pts, +$seedReward seeds';
    }
    _gardenMessageLife = 2.3;
    _completeDailyEcosystemTask(GardenEcosystemTask.collect, moodBoost: 5);
    _playSfx(_sfxComboSpark, volume: 0.55);
  }

  PlayerGardenPlot? get _gardenGiftPlot {
    final int? id = _gardenGiftPlotId;
    if (id == null) {
      return null;
    }
    for (final plot in _playerGardenPlots) {
      if (plot.id == id && _isGardenPlotUnlocked(plot)) {
        return plot;
      }
    }
    return _playerGardenPlots.where(_isGardenPlotUnlocked).firstOrNull;
  }

  void _openGardenGift(PlayerGardenPlot plot) {
    final double roll = _random.nextDouble();
    String message;
    if (roll < 0.6) {
      final int amount = 30 + _random.nextInt(31);
      _seeds += amount;
      message = 'Gift: +$amount seeds';
    } else if (roll < 0.9) {
      _waterCharges = min(12, _waterCharges + 2);
      message = 'Gift: +2 water';
    } else if (roll < 0.99) {
      _sunDrops = min(12, _sunDrops + 2);
      message = 'Gift: +2 sun drops';
    } else {
      _seeds += 150;
      message = 'Gift: +150 seeds, a rare one!';
    }
    _gardenGiftDay = null;
    _gardenGiftPlotId = null;
    plot.sparkle = 1;
    _bumpGardenMood(4);
    _gardenMessage = '$message - thanks, ninja';
    _gardenMessageLife = 2.6;
    _playSfx(_sfxComboSpark, volume: 0.6);
    _queueGardenSave();
  }

  String _gardenForecastText(DateTime now) {
    if (_gardenGiftPlotId != null) {
      return 'The ninja left a gift - find the seed bag';
    }

    final String? dailyAction = _gardenNextDailyAction();
    if (dailyAction != null) {
      return dailyAction;
    }

    final PlayerGardenPlot? nextPlot = _playerGardenPlots
        .where(
          (plot) =>
              plot.unlockLevel == _gardenLevel + 1 &&
              plot.unlockLevel <= _currentGardenHouse.maxGardenLevel,
        )
        .firstOrNull;
    if (nextPlot != null && !nextPlot.grassCut) {
      return 'Mow the next meadow to shape a new garden zone';
    }
    if (nextPlot != null && _seeds >= _gardenExpandCost) {
      return 'Expand the yard for another planting bed';
    }
    final GardenHouseTier? nextHouse = _nextGardenHouse;
    if (nextHouse != null &&
        _gardenLevel >= _currentGardenHouse.maxGardenLevel) {
      final String? blocker = _gardenHouseUpgradeBlocker(
        _currentGardenHouse,
        nextHouse,
      );
      if (blocker != null) {
        return blocker;
      }
      return 'Upgrade the townhouse to open the next yard';
    }

    PlayerGardenPlot? readyPlot;
    PlayerGardenPlot? thirstyPlot;
    PlayerGardenPlot? soonestPlot;
    Duration? soonestWait;
    bool anyPlanted = false;
    bool anyUnwatered = false;
    for (final plot in _playerGardenPlots) {
      if (!_isGardenPlotUnlocked(plot) || !plot.planted) {
        continue;
      }
      anyPlanted = true;
      if (plot.ready) {
        readyPlot ??= plot;
        continue;
      }
      if (!_isWateredToday(plot, now)) {
        anyUnwatered = true;
      }
      final Duration wait = _remainingGardenTime(plot, now);
      if (wait <= Duration.zero) {
        // Past due but held at the watering gate.
        thirstyPlot ??= plot;
        continue;
      }
      if (soonestWait == null || wait < soonestWait) {
        soonestWait = wait;
        soonestPlot = plot;
      }
    }

    if (readyPlot != null) {
      return '${_plantOptionForPlot(readyPlot).name} is ready to gather';
    }
    if (thirstyPlot != null) {
      return 'Water ${_plantOptionForPlot(thirstyPlot).name} to finish '
          'blooming';
    }
    final bool tendedToday = _gardenLastTendedDay == _dayKey(now);
    if (tendedToday &&
        (soonestWait == null || soonestWait > const Duration(hours: 8))) {
      return 'All tended - a gift may arrive tomorrow';
    }
    if (soonestPlot != null && soonestWait != null) {
      return '${_plantOptionForPlot(soonestPlot).name} ready in '
          '${_durationLabel(soonestWait)}';
    }
    if (anyPlanted && anyUnwatered) {
      return 'Water the plants to earn tomorrow\'s gift';
    }
    return 'Plant something new in the nursery';
  }

  Color _gardenTimeTint(DateTime now) {
    final double hour = now.hour + now.minute / 60.0;
    const Color night = Color(0x3A17224A);
    const Color dawn = Color(0x2EFFB27A);
    const Color dusk = Color(0x30FF8E5E);
    const Color day = Color(0x00000000);
    Color blend(Color from, Color to, double t) =>
        Color.lerp(from, to, t.clamp(0.0, 1.0))!;
    if (hour < 5) {
      return night;
    }
    if (hour < 6.5) {
      return blend(night, dawn, (hour - 5) / 1.5);
    }
    if (hour < 8) {
      return blend(dawn, day, (hour - 6.5) / 1.5);
    }
    if (hour < 16.5) {
      return day;
    }
    if (hour < 18) {
      return blend(day, dusk, (hour - 16.5) / 1.5);
    }
    if (hour < 20) {
      return blend(dusk, night, (hour - 18) / 2);
    }
    return night;
  }

  void _selectAvatar(int index) {
    _playSfx(_sfxComboSpark, volume: 0.48);
    setState(() {
      _selectedAvatar = index.clamp(0, _avatarAssets.length - 1).toInt();
    });
  }

  void _selectMusicTrack(int index) {
    _playSfx(_sfxComboSpark, volume: 0.42);
    _musicTrackBeforeGarden = null;
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
    final bool acceptsSlashInput =
        _phase == GamePhase.playing && !_forceUpdateVisible;
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
          if (_forceUpdateVisible) _buildForcedUpdateLayer(),
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
            Positioned.fill(child: _buildScrollableGardenMap()),
            _buildGardenTopHud(),
            Positioned(
              left: 14,
              right: 14,
              top: 136,
              child: _buildGardenEcosystemPanel(),
            ),
            if (_gardenMessageLife > 0)
              Positioned(
                left: 54,
                right: 54,
                top: 218,
                child: Opacity(
                  opacity: _gardenMessageLife.clamp(0.0, 1.0),
                  child: _GardenToast(message: _gardenMessage),
                ),
              ),
            Positioned(
              left: 42,
              right: 42,
              bottom: 124,
              child: IgnorePointer(
                child: _GardenForecastPill(
                  key: const ValueKey('garden-forecast'),
                  text: _gardenForecastText(_gardenNow),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildGardenToolbar(),
            ),
            if (_gardenNurseryPlot != null) _buildGardenNurseryOverlay(),
            if (_showGardenHousePanel) _buildGardenHouseOverlay(),
            if (_showGardenWelcome)
              _GardenWelcomeCard(
                key: const ValueKey('garden-welcome-card'),
                streak: _gardenLoginStreak,
                lines: _gardenWelcomeLines,
                onClose: _closeGardenWelcome,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableGardenMap() {
    final GardenWorld world = _currentGardenWorld;
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _gardenMapController,
        constrained: false,
        minScale: _gardenMinScale,
        maxScale: _gardenMaxScale,
        boundaryMargin: EdgeInsets.zero,
        child: SizedBox(
          width: _playerGardenWidth,
          height: _playerGardenHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                key: ValueKey('backyard-${world.name}'),
                painter: _BackyardGardenPainter(
                  world: world,
                  house: _currentGardenHouse,
                  plots: _playerGardenPlots,
                  gardenLevel: _gardenLevel,
                  mood: _gardenMood,
                  dailyComplete: _dailyGardenTasksComplete,
                  houseActive: _showGardenHousePanel,
                  time: _motionTime,
                ),
                willChange: true,
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
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: _gardenTimeTint(_gardenNow)),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GardenAmbientPainter(
                      world: world,
                      time: _motionTime,
                    ),
                    willChange: true,
                  ),
                ),
              ),
              _buildGardenHouseTarget(),
              _buildGardenStation(
                key: const ValueKey('garden-station-journal'),
                position: const Offset(214, 516),
                icon: Icons.menu_book_rounded,
                title: 'Garden journal',
                status: _gardenHabitatDay == _dayKey(_gardenNow)
                    ? 'Checked in'
                    : 'Daily bonus',
                color: const Color(0xFF78A544),
                ready: _gardenHabitatDay != _dayKey(_gardenNow),
                onTap: () {
                  _guideGardenCaretaker(const Offset(276, 548));
                  _visitGardenJournal();
                },
              ),
              _buildGardenStation(
                key: const ValueKey('garden-station-water'),
                position: const Offset(734, 704),
                icon: Icons.water_drop_rounded,
                title: 'Rain barrel',
                status: _gardenWaterBarrelDay == _dayKey(_gardenNow)
                    ? 'Refills tomorrow'
                    : '+1 water',
                color: const Color(0xFF328EC1),
                ready: _gardenWaterBarrelDay != _dayKey(_gardenNow),
                onTap: () {
                  _guideGardenCaretaker(const Offset(668, 748));
                  _collectGardenWaterBarrel();
                },
              ),
              _buildGardenStation(
                key: const ValueKey('garden-station-compost'),
                position: const Offset(224, 1048),
                icon: Icons.recycling_rounded,
                title: 'Compost mixer',
                status: _gardenCompost > 0
                    ? 'Mix x$_gardenCompost'
                    : 'Clear to fill',
                color: const Color(0xFF9A6B35),
                ready: _gardenCompost > 0,
                onTap: () {
                  _guideGardenCaretaker(const Offset(296, 1088));
                  _collectGardenCompost();
                },
              ),
              for (final plot in _playerGardenPlots.where(_isGardenPlotVisible))
                _buildGardenPlot(plot),
              if (_gardenGiftPlot != null) _buildGardenGift(_gardenGiftPlot!),
              _buildGardenCaretaker(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGardenHouseTarget() {
    final double pulse = (sin(_motionTime * 2.2) + 1) / 2;
    return Positioned(
      left: 138,
      top: 176,
      width: 644,
      height: 292,
      child: GestureDetector(
        key: const ValueKey('garden-house-scene'),
        behavior: HitTestBehavior.translucent,
        onTap: _openGardenHousePanel,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Transform.scale(
            scale: 1 + pulse * 0.025,
            child: _GardenTinyBadge(
              text: 'Home hub',
              color: const Color(0xEE315A28),
              borderColor: Color.lerp(
                const Color(0xFFC8E98D),
                const Color(0xFFFFE978),
                pulse,
              )!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGardenCaretaker() {
    final Offset delta = _gardenCaretakerTarget - _gardenCaretakerPosition;
    final bool faceLeft = delta.dx < -2;
    final double bob = _gardenCaretakerMoving
        ? sin(_motionTime * 11) * 4
        : sin(_motionTime * 1.8) * 1.5;
    final double lean = _gardenCaretakerMoving
        ? sin(_motionTime * 5.5) * 0.045
        : 0;
    return Positioned(
      left: _gardenCaretakerPosition.dx - 45,
      top: _gardenCaretakerPosition.dy - 104 + bob,
      width: 90,
      height: 112,
      child: IgnorePointer(
        child: Stack(
          key: const ValueKey('garden-caretaker'),
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 0,
              child: Container(
                width: 54,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Positioned(
              bottom: 5,
              child: Transform.rotate(
                angle: lean,
                alignment: Alignment.bottomCenter,
                child: Transform.flip(
                  flipX: faceLeft,
                  child: Image.asset(
                    _currentAvatar,
                    width: 78,
                    height: 102,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGardenStation({
    required Key key,
    required Offset position,
    required IconData icon,
    required String title,
    required String status,
    required Color color,
    required bool ready,
    required VoidCallback onTap,
  }) {
    final double pulse = (sin(_motionTime * 2.4 + position.dx) + 1) / 2;
    return Positioned(
      left: position.dx - 58,
      top: position.dy - 56 + sin(_motionTime * 1.6 + position.dy) * 2,
      width: 116,
      height: 112,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Transform.scale(
          scale: ready ? 1 + pulse * 0.025 : 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (ready)
                Container(
                  width: 88 + pulse * 10,
                  height: 88 + pulse * 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(
                        0xFFFFEE8A,
                      ).withValues(alpha: 0.28 + pulse * 0.38),
                      width: 4,
                    ),
                  ),
                ),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Color.lerp(color, const Color(0xFF18391C), 0.28),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ready
                        ? const Color(0xFFFFE77A)
                        : Colors.white.withValues(alpha: 0.55),
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 38),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xEE244920),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFD8F58B)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ready
                              ? const Color(0xFFFFEB7A)
                              : const Color(0xFFCDE6BC),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
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
    );
  }

  Widget _buildGardenGift(PlayerGardenPlot plot) {
    final double bob = sin(_motionTime * 2.1) * 4;
    final double glow = (sin(_motionTime * 2.6) + 1) / 2;
    return Positioned(
      left: plot.position.dx - 86,
      top: plot.position.dy - 46 + bob,
      child: GestureDetector(
        key: const ValueKey('garden-gift'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _guideGardenCaretakerToPlot(plot);
          _openGardenGift(plot);
        }),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFFFFE79A,
                ).withValues(alpha: 0.25 + glow * 0.3),
                blurRadius: 22 + glow * 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/sprites/seed_bag.png',
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
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
    final double targetPulse = (sin(_motionTime * 4.4 + plot.id * 0.7) + 1) / 2;
    final double sparkle = plot.sparkle.clamp(0.0, 1.0);
    final bool tree =
        plot.planted && _gardenOptionIsTree(_plantOptionForPlot(plot));
    final double plantScale = tree
        ? switch (plot.growthStage) {
            0 => 0.86,
            1 => 0.98,
            _ => 1.16,
          }
        : switch (plot.growthStage) {
            0 => 0.9,
            1 => 0.78,
            2 => 1.0,
            _ => 1.14,
          };
    final GardenPlantRenderSpec? plantSpec = plot.planted
        ? _plantRenderSpecForPlot(plot)
        : null;
    final double plantBob = plot.planted
        ? sin(_motionTime * 1.7 + plot.id * 0.9) * 1.4
        : 0;
    final double plantSway = plot.planted
        ? sin(_motionTime * 1.35 + plot.id * 0.55) * 0.028
        : 0;
    final double plantBreath = plot.planted
        ? 1 + sin(_motionTime * 1.2 + plot.id) * 0.018
        : 1;
    final bool plantTarget =
        unlocked &&
        !plot.weed &&
        !plot.planted &&
        _gardenTool == GardenTool.plant;
    final bool showStatusBadge =
        unlocked && !plantTarget && (plot.weed || plot.planted);
    final bool nextLand =
        plot.unlockLevel == _gardenLevel + 1 &&
        plot.unlockLevel <= _currentGardenHouse.maxGardenLevel;
    final String lockedLabel =
        plot.unlockLevel > _currentGardenHouse.maxGardenLevel
        ? 'Upgrade home'
        : nextLand
        ? plot.grassCut
              ? 'Shape for ${_formatNumber(_gardenExpandCost)}'
              : 'Mow meadow'
        : 'Future yard';

    return Positioned(
      left: plot.position.dx - 78,
      top: plot.position.dy - 130,
      width: 156,
      height: 210,
      child: GestureDetector(
        key: ValueKey('player-garden-plot-${plot.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleGardenPlotTap(plot),
        child: Opacity(
          opacity: unlocked
              ? 1
              : nextLand
              ? 0.92
              : 0.62,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (plantTarget)
                Positioned(
                  bottom: 10,
                  child: _GardenPlantTargetGlow(
                    key: ValueKey('garden-plant-target-glow-${plot.id}'),
                    pulse: targetPulse,
                  ),
                ),
              if (!unlocked) ...[
                Positioned(
                  bottom: 44,
                  child: Icon(
                    plot.unlockLevel > _currentGardenHouse.maxGardenLevel
                        ? Icons.home_work_rounded
                        : plot.grassCut
                        ? Icons.construction_rounded
                        : Icons.content_cut_rounded,
                    color: Color(0xFFFFE29B),
                    size: 34,
                  ),
                ),
                Positioned(
                  bottom: 16,
                  child: _GardenTinyBadge(
                    text: lockedLabel,
                    color: const Color(0xEE2C4B22),
                    borderColor: const Color(0xFFFFD36A),
                  ),
                ),
              ] else if (plantTarget)
                Positioned(
                  right: 42,
                  bottom: 35,
                  child: Transform.scale(
                    scale: 1 + targetPulse * 0.08,
                    child: const _GardenPlantTargetMarker(),
                  ),
                )
              else if (plot.planted && plantSpec != null)
                Positioned(
                  bottom: plantSpec.bottom,
                  child: Transform.translate(
                    offset: Offset(
                      plantSpec.offsetX,
                      plantSpec.offsetY + plantBob,
                    ),
                    child: Transform.rotate(
                      alignment: Alignment.bottomCenter,
                      angle: plantSway,
                      child: Transform.scale(
                        alignment: Alignment.bottomCenter,
                        scale: plantScale * plantSpec.scale * plantBreath,
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
                ),
              if (plot.weed && unlocked)
                Positioned(
                  bottom: 44 + sin(_motionTime * 5 + plot.id) * 2,
                  right: 42,
                  child: Image.asset(
                    weedAsset,
                    width: 64,
                    height: 70,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              if (plot.ready && unlocked)
                Positioned(
                  top: 42,
                  right: 34,
                  child: Image.asset(
                    'assets/images/icons/bloom_collect.png',
                    width: 26,
                    height: 26,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              if (showStatusBadge)
                Positioned(
                  top: plot.ready ? 36 : 58,
                  child: _GardenTinyBadge(
                    text: status,
                    color: plot.weed
                        ? const Color(0xEE4A5D2A)
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
              if (unlocked && plot.planted && plot.upgradeLevel > 1)
                Positioned(
                  left: 28,
                  top: 52,
                  child: _GardenTinyBadge(
                    text: 'Lv ${plot.upgradeLevel}',
                    color: const Color(0xEE244B1F),
                    borderColor: const Color(0xFFD8FF84),
                  ),
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
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.18,
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

  Widget _buildGardenHouseOverlay() {
    final GardenHouseTier current = _currentGardenHouse;
    final GardenHouseTier? next = _nextGardenHouse;
    final List<PlayerGardenPlot> housePlots = _currentHouseGardenPlots.toList();
    final int unlockedBeds = housePlots.where(_isGardenPlotUnlocked).length;
    final int plantedBeds = housePlots.where((plot) => plot.planted).length;
    final int upgradedPlants = housePlots
        .where(
          (plot) => plot.planted && plot.upgradeLevel >= _currentHousePlantCap,
        )
        .length;
    final String? blocker = next == null
        ? null
        : _gardenHouseUpgradeBlocker(current, next);

    Widget progressRow({
      required IconData icon,
      required String label,
      required String value,
      required double progress,
      required Color color,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.7)),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF2A5724),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Color(0xFF4D762F),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: progress.clamp(0, 1),
                      backgroundColor: const Color(0xFFD9E8C7),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeGardenHousePanel,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 126,
            bottom: 96,
            child: Container(
              key: const ValueKey('garden-house-panel'),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FFE9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD6F06E), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: current.roofColor,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFF4E6E2A),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.home_work_rounded,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              current.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF285320),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Home ${_gardenHouseTier + 1}/${_gardenHouseTiers.length} - ${current.bonus}',
                              maxLines: 2,
                              style: const TextStyle(
                                color: Color(0xFF5B7E3A),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RoundIconButton(
                        icon: Icons.close_rounded,
                        onPressed: _closeGardenHousePanel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: blocker == null
                          ? const Color(0xFFE7F7BC)
                          : const Color(0xFFFFF0C5),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: blocker == null
                            ? const Color(0xFF83B94B)
                            : const Color(0xFFD6A43D),
                      ),
                    ),
                    child: Text(
                      next == null
                          ? 'This is the largest home. Keep improving the living garden.'
                          : blocker ?? 'Everything is ready for ${next.name}.',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3E5D27),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          progressRow(
                            icon: Icons.landscape_rounded,
                            label: 'Backyard zones',
                            value: '$unlockedBeds/${housePlots.length}',
                            progress: housePlots.isEmpty
                                ? 1
                                : unlockedBeds / housePlots.length,
                            color: const Color(0xFF72A83C),
                          ),
                          progressRow(
                            icon: Icons.local_florist_rounded,
                            label: 'Zones planted',
                            value: '$plantedBeds/${housePlots.length}',
                            progress: housePlots.isEmpty
                                ? 1
                                : plantedBeds / housePlots.length,
                            color: const Color(0xFFE283A8),
                          ),
                          progressRow(
                            icon: Icons.upgrade_rounded,
                            label: 'Plants at Lv $_currentHousePlantCap',
                            value: '$upgradedPlants/${housePlots.length}',
                            progress: housePlots.isEmpty
                                ? 1
                                : upgradedPlants / housePlots.length,
                            color: const Color(0xFF4C9CC4),
                          ),
                          if (next != null) ...[
                            progressRow(
                              icon: Icons.eco_rounded,
                              label: 'Garden reputation',
                              value:
                                  '${_formatNumber(_gardenPoints)}/${_formatNumber(next.unlockPoints)}',
                              progress: _gardenPoints / next.unlockPoints,
                              color: const Color(0xFF4F9B4B),
                            ),
                            progressRow(
                              icon: Icons.savings_rounded,
                              label: 'Upgrade seeds',
                              value:
                                  '${_formatNumber(_seeds)}/${_formatNumber(next.seedCost)}',
                              progress: next.seedCost <= 0
                                  ? 1
                                  : _seeds / next.seedCost,
                              color: const Color(0xFFE7A62E),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    next.roofColor.withValues(alpha: 0.2),
                                    next.wallColor.withValues(alpha: 0.5),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: next.roofColor.withValues(alpha: 0.65),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.holiday_village_rounded,
                                    color: next.roofColor,
                                    size: 34,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Next: ${next.name}',
                                          style: const TextStyle(
                                            color: Color(0xFF2C5326),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          next.bonus,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF58753D),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _PrimaryButton(
                      key: const ValueKey('garden-house-upgrade-action'),
                      label: next == null
                          ? 'HOME MAXED'
                          : blocker == null
                          ? 'UPGRADE TO ${next.name.toUpperCase()}'
                          : 'CHECK UPGRADE REQUIREMENTS',
                      icon: next == null
                          ? Icons.verified_rounded
                          : Icons.home_work_rounded,
                      onPressed: next == null
                          ? _closeGardenHousePanel
                          : () => setState(_tryUpgradeGardenHouse),
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

  Widget _buildForcedUpdateLayer() {
    final bool canRetry = _forceUpdateState == ForceUpdateState.blocked;
    final String title = switch (_forceUpdateState) {
      ForceUpdateState.checking => 'Checking Update',
      ForceUpdateState.updating => 'Updating Garden Ninja',
      ForceUpdateState.blocked => 'Update Required',
      ForceUpdateState.idle => 'Garden Ninja',
    };
    final IconData icon = switch (_forceUpdateState) {
      ForceUpdateState.checking => Icons.manage_search_rounded,
      ForceUpdateState.updating => Icons.system_update_rounded,
      ForceUpdateState.blocked => Icons.lock_rounded,
      ForceUpdateState.idle => Icons.eco_rounded,
    };

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.68),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xF21A4017),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFBDF17A),
                    width: 2.4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x99000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF65B92F),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFFED86),
                          width: 2.5,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _forceUpdateMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE9FFD0),
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!canRetry)
                      const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Color(0xFFFFED86),
                        ),
                      )
                    else
                      _PrimaryButton(
                        label: 'UPDATE NOW',
                        icon: Icons.system_update_alt_rounded,
                        onPressed: _checkForcedPlayUpdate,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardenEcosystemPanel() {
    Widget taskIcon({
      required IconData icon,
      required bool done,
      required String label,
    }) {
      return Tooltip(
        message: label,
        child: Container(
          width: 27,
          height: 27,
          decoration: BoxDecoration(
            color: done ? const Color(0xFF73BD39) : const Color(0xFF244D2A),
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? const Color(0xFFFFED82) : const Color(0xFF7EA86B),
              width: 1.6,
            ),
          ),
          child: Icon(
            done ? Icons.check_rounded : icon,
            color: Colors.white,
            size: 17,
          ),
        ),
      );
    }

    final bool basketReady =
        _dailyGardenTasksComplete && !_gardenDailyRewardClaimed;
    return Container(
      key: const ValueKey('garden-ecosystem-panel'),
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEE173E20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBEEB7C), width: 2),
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
          SizedBox(
            width: 102,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_gardenMoodLabel garden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 9,
                    child: LinearProgressIndicator(
                      value: _gardenMood / 100,
                      backgroundColor: const Color(0xFF0D2814),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _gardenMood >= 62
                            ? const Color(0xFF9BE94F)
                            : _gardenMood >= 38
                            ? const Color(0xFFFFCF45)
                            : const Color(0xFFE36B4B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mood $_gardenMood%',
                  style: const TextStyle(
                    color: Color(0xFFD7F1C3),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    taskIcon(
                      icon: Icons.spa_rounded,
                      done: _gardenDailyPlantDone,
                      label: 'Plant',
                    ),
                    taskIcon(
                      icon: Icons.water_drop_rounded,
                      done: _gardenDailyWaterDone,
                      label: 'Water',
                    ),
                    taskIcon(
                      icon: Icons.local_florist_rounded,
                      done: _gardenDailyCollectDone,
                      label: 'Gather',
                    ),
                    taskIcon(
                      icon: Icons.content_cut_rounded,
                      done: _gardenDailyTidyDone,
                      label: 'Tidy',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Daily care $_dailyGardenTaskCount/4',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5F5D2),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const ValueKey('garden-daily-claim'),
            behavior: HitTestBehavior.opaque,
            onTap: basketReady ? _claimDailyEcosystemReward : null,
            child: Container(
              width: 66,
              height: 50,
              decoration: BoxDecoration(
                color: basketReady
                    ? const Color(0xFFF1A928)
                    : const Color(0xFF315B35),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: basketReady
                      ? const Color(0xFFFFEE8B)
                      : const Color(0xFF76926E),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _gardenDailyRewardClaimed
                        ? Icons.check_circle_rounded
                        : Icons.redeem_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                  Text(
                    _gardenDailyRewardClaimed
                        ? 'Done'
                        : basketReady
                        ? 'CLAIM'
                        : 'Basket',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
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
    return Positioned(
      left: 14,
      right: 14,
      top: 12,
      child: SizedBox(
        height: 118,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                key: const ValueKey('garden-house-upgrade'),
                behavior: HitTestBehavior.opaque,
                onTap: _openGardenHousePanel,
                child: _GardenTitleBoard(
                  title: _currentGardenHouse.name,
                  subtitle:
                      'Townhouse ${_gardenHouseTier + 1}/${_gardenHouseTiers.length}',
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: _GardenStreakChip(
                key: const ValueKey('garden-streak-chip'),
                streak: _gardenLoginStreak,
                tendedToday: _gardenLastTendedDay == _dayKey(_gardenNow),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openUpgrades,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xDD263B31),
                    border: Border.all(
                      color: const Color(0xCCBEEB86),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 9,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 48,
              child: Row(
                children: [
                  Expanded(
                    child: _GardenStatChip(
                      asset: 'assets/images/icons/seed_coin.png',
                      value: _formatNumber(_seeds),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _GardenStatChip(
                      asset: 'assets/images/icons/water_drop.png',
                      value: '$_waterCharges',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _GardenStatChip(
                      asset: 'assets/images/icons/sun_boost.png',
                      value: '$_sunDrops',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _GardenStatChip(
                      icon: Icons.eco_rounded,
                      value: _formatNumber(_gardenPoints),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 52,
              right: 52,
              bottom: 0,
              child: _GardenWorldSelector(
                world: _currentGardenWorld,
                index: _selectedGardenWorld,
                total: _gardenWorlds.length,
                unlockedCount: _unlockedGardenWorldCount,
                onPrevious: () => _selectGardenWorld(-1),
                onNext: () => _selectGardenWorld(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGardenToolbar() {
    return Row(
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
        const SizedBox(width: 10),
        Expanded(
          child: _GardenToolButton(
            key: const ValueKey('garden-tool-water'),
            icon: Icons.water_drop_rounded,
            label: 'Water',
            selected: _gardenTool == GardenTool.water,
            onTap: () => _selectGardenTool(GardenTool.water),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GardenToolButton(
            key: const ValueKey('garden-tool-clear'),
            icon: Icons.content_cut_rounded,
            label: 'Clear',
            selected: _gardenTool == GardenTool.clear,
            onTap: () => _selectGardenTool(GardenTool.clear),
          ),
        ),
        const SizedBox(width: 10),
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

class _GardenTitleBoard extends StatelessWidget {
  const _GardenTitleBoard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -18,
            child: Transform.rotate(
              angle: -0.42,
              child: const Icon(
                Icons.eco_rounded,
                color: Color(0xFF6EBB35),
                size: 32,
              ),
            ),
          ),
          Positioned(
            right: -18,
            child: Transform.rotate(
              angle: 0.42,
              child: const Icon(
                Icons.eco_rounded,
                color: Color(0xFF6EBB35),
                size: 32,
              ),
            ),
          ),
          Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6DAA35), Color(0xFF315F1D)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFB9E972), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
                BoxShadow(
                  color: Color(0x559EF15E),
                  blurRadius: 8,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: Color(0xAA143010),
                          blurRadius: 2,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFDFFFA9),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GardenWorldSelector extends StatelessWidget {
  const _GardenWorldSelector({
    required this.world,
    required this.index,
    required this.total,
    required this.unlockedCount,
    required this.onPrevious,
    required this.onNext,
  });

  final GardenWorld world;
  final int index;
  final int total;
  final int unlockedCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('garden-world-selector'),
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            world.darkAccent.withValues(alpha: 0.92),
            const Color(0xEE142515),
          ],
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: world.accent, width: 1.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _GardenWorldArrow(
            key: const ValueKey('garden-world-prev'),
            icon: Icons.chevron_left_rounded,
            onTap: onPrevious,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    world.name,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                Text(
                  'Garden ${index + 1}/$total  •  $unlockedCount open',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: world.accent,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          _GardenWorldArrow(
            key: const ValueKey('garden-world-next'),
            icon: Icons.chevron_right_rounded,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _GardenWorldArrow extends StatelessWidget {
  const _GardenWorldArrow({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, color: Colors.white, size: 25),
      ),
    );
  }
}

class _BackyardGardenPainter extends CustomPainter {
  const _BackyardGardenPainter({
    required this.world,
    required this.house,
    required this.plots,
    required this.gardenLevel,
    required this.mood,
    required this.dailyComplete,
    required this.houseActive,
    required this.time,
  });

  final GardenWorld world;
  final GardenHouseTier house;
  final List<PlayerGardenPlot> plots;
  final int gardenLevel;
  final int mood;
  final bool dailyComplete;
  final bool houseActive;
  final double time;

  bool get _night => world.ambient == GardenAmbient.fireflies;
  bool get _winter => world.ambient == GardenAmbient.snow;
  bool get _bamboo => world.ambient == GardenAmbient.bambooLeaves;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGround(canvas, size);
    _drawHouseEdge(canvas, size);
    _drawPath(canvas, size);
    _drawPond(canvas, size);
    _drawFenceAndBorders(canvas, size);
    _drawBackyardDetails(canvas, size);
    _drawLivingYard(canvas, size);
    _drawPlotBeds(canvas);
    _drawMoodOverlay(canvas, size);
  }

  void _drawGround(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final List<Color> baseColors = _winter
        ? const [Color(0xFFEAF7E6), Color(0xFFBDD9B8), Color(0xFFA7C59F)]
        : _night
        ? const [Color(0xFF314B38), Color(0xFF426B43), Color(0xFF284A38)]
        : _bamboo
        ? const [Color(0xFF8BCB68), Color(0xFF5FA447), Color(0xFF3F7D3A)]
        : const [Color(0xFF9BD568), Color(0xFF6BAB42), Color(0xFF4E8D38)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: baseColors,
        ).createShader(rect),
    );

    _drawMowedGrassBands(canvas, size);
    _drawTurfPatches(canvas, size);
    _drawGrassBlades(canvas, size);

    if (_bamboo) {
      _drawBambooStand(canvas, Offset(36, 190), 1.08);
      _drawBambooStand(canvas, Offset(size.width - 82, 280), 0.9);
    }
  }

  void _drawMowedGrassBands(Canvas canvas, Size size) {
    final Paint lightBand = Paint()
      ..style = PaintingStyle.fill
      ..color = (_winter ? Colors.white : const Color(0xFFD8F69B)).withValues(
        alpha: _winter ? 0.1 : 0.11,
      );
    final Paint darkBand = Paint()
      ..style = PaintingStyle.fill
      ..color = (_night ? const Color(0xFF183826) : const Color(0xFF2E7432))
          .withValues(alpha: _night ? 0.1 : 0.09);

    for (double y = 300; y < size.height + 220; y += 132) {
      final Path light = Path()
        ..moveTo(-160, y)
        ..lineTo(size.width + 90, y - 230)
        ..lineTo(size.width + 150, y - 168)
        ..lineTo(-110, y + 68)
        ..close();
      canvas.drawPath(light, lightBand);

      final Path dark = Path()
        ..moveTo(-120, y + 74)
        ..lineTo(size.width + 120, y - 142)
        ..lineTo(size.width + 170, y - 96)
        ..lineTo(-80, y + 126)
        ..close();
      canvas.drawPath(dark, darkBand);
    }
  }

  void _drawTurfPatches(Canvas canvas, Size size) {
    final Paint softPatch = Paint()
      ..color = (_night ? const Color(0xFF203F2D) : const Color(0xFF6CB348))
          .withValues(alpha: _winter ? 0.16 : 0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    for (int i = 0; i < 20; i += 1) {
      final double x = 42 + ((i * 181) % 1000) / 1000 * (size.width - 84);
      final double y = 420 + ((i * 263) % 1000) / 1000 * (size.height - 470);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: 128 + (i % 4) * 34,
          height: 52 + (i % 3) * 20,
        ),
        softPatch,
      );
    }
  }

  void _drawGrassBlades(Canvas canvas, Size size) {
    final Paint blade = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = (_night ? const Color(0xFF8DD269) : const Color(0xFFE2F58F))
          .withValues(alpha: _winter ? 0.2 : 0.32);
    final Paint bloom = Paint()
      ..color = (_night ? const Color(0xFFB8EFFF) : const Color(0xFFFFE49A))
          .withValues(alpha: _winter ? 0.15 : 0.55);
    final Paint clover = Paint()
      ..color = (_night ? const Color(0xFF66B675) : const Color(0xFF2E8A39))
          .withValues(alpha: _winter ? 0.18 : 0.42);

    for (int i = 0; i < 260; i += 1) {
      final double x = ((i * 73) % 1000) / 1000 * size.width;
      final double y = 360 + ((i * 137) % 1000) / 1000 * (size.height - 380);
      final double lean = sin(time * 1.8 + i * 1.7) * 4;
      canvas.drawLine(Offset(x, y), Offset(x + lean, y - 8), blade);
      if (i % 9 == 0) {
        canvas.drawCircle(Offset(x + 3, y - 10), 2.1, bloom);
      }
      if (i % 17 == 0) {
        final Offset c = Offset(x - 4, y - 6);
        canvas.drawCircle(c + const Offset(-4, 0), 3, clover);
        canvas.drawCircle(c + const Offset(4, 0), 3, clover);
        canvas.drawCircle(c + const Offset(0, -4), 3, clover);
      }
    }
  }

  void _drawLivingYard(Canvas canvas, Size size) {
    final int driftingCount = 10 + mood ~/ 7;
    final Paint leafPaint = Paint()
      ..color = (_night ? const Color(0xFFB9F6D0) : const Color(0xFFFFE98A))
          .withValues(alpha: 0.24 + mood / 360);
    for (int i = 0; i < driftingCount; i += 1) {
      final double speed = 0.18 + (i % 5) * 0.035;
      final double progress = (time * speed + i * 0.117) % 1;
      final double x =
          35 +
          ((i * 151) % 1000) / 1000 * (size.width - 70) +
          sin(time * 1.3 + i) * 18;
      final double y = 400 + progress * (size.height - 430);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(sin(time * 1.7 + i * 0.8) * 0.7);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 8 + (i % 3) * 2,
          height: 4 + (i % 2) * 2,
        ),
        leafPaint,
      );
      canvas.restore();
    }

    if (mood >= 62 || dailyComplete) {
      final int sparkleCount = dailyComplete ? 24 : 12;
      final Paint sparkle = Paint()
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(
          0xFFFFF4A8,
        ).withValues(alpha: dailyComplete ? 0.72 : 0.38);
      for (int i = 0; i < sparkleCount; i += 1) {
        final double pulse = (sin(time * 3.1 + i * 1.31) + 1) * 0.5;
        final Offset center = Offset(
          40 + ((i * 233) % 1000) / 1000 * (size.width - 80),
          420 + ((i * 347) % 1000) / 1000 * (size.height - 470),
        );
        final double radius = 2 + pulse * 4;
        canvas.drawLine(
          center - Offset(radius, 0),
          center + Offset(radius, 0),
          sparkle,
        );
        canvas.drawLine(
          center - Offset(0, radius),
          center + Offset(0, radius),
          sparkle,
        );
      }
    }
  }

  void _drawHouseEdge(Canvas canvas, Size size) {
    final Rect skyRect = Rect.fromLTWH(0, 0, size.width, 430);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _night
              ? const [Color(0xFF162D55), Color(0xFF2E5B5B)]
              : _winter
              ? const [Color(0xFFD7F3FF), Color(0xFFE9F8E8)]
              : const [Color(0xFFAEEAFF), Color(0xFFE9FFD6)],
        ).createShader(skyRect),
    );

    final Paint cloud = Paint()
      ..color = Colors.white.withValues(alpha: _night ? 0.12 : 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final double cloudDrift = (time * 7) % (size.width + 260);
    canvas.drawOval(Rect.fromLTWH(cloudDrift - 190, 54, 180, 54), cloud);
    canvas.drawOval(
      Rect.fromLTWH(size.width - cloudDrift + 80, 88, 250, 64),
      cloud,
    );

    final int tier = house.maxGardenLevel <= 3
        ? 0
        : house.maxGardenLevel <= 5
        ? 1
        : 2;
    final Rect houseRect = Rect.fromLTWH(
      112 - tier * 34,
      214,
      696 + tier * 68,
      214 + tier * 12,
    );
    final Rect chimney = Rect.fromLTWH(
      houseRect.right - 142,
      houseRect.top - 100,
      48,
      96,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chimney, const Radius.circular(7)),
      Paint()..color = const Color(0xFF8A5539),
    );
    for (int i = 0; i < 4; i += 1) {
      final double smokeLife = (time * 0.18 + i * 0.24) % 1;
      canvas.drawCircle(
        Offset(
          chimney.center.dx + sin(time + i) * 14,
          chimney.top - smokeLife * 84,
        ),
        12 + smokeLife * 14,
        Paint()
          ..color = Colors.white.withValues(
            alpha: (_night ? 0.12 : 0.2) * (1 - smokeLife),
          ),
      );
    }

    final RRect wall = RRect.fromRectAndRadius(
      houseRect,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _winter
              ? const [Color(0xFFFFFFFF), Color(0xFFDDE9DD)]
              : [
                  Color.lerp(house.wallColor, Colors.white, 0.18)!,
                  Color.lerp(house.wallColor, const Color(0xFF9D7042), 0.13)!,
                ],
        ).createShader(houseRect),
    );
    for (double y = houseRect.top + 18; y < houseRect.bottom; y += 24) {
      canvas.drawLine(
        Offset(houseRect.left + 8, y),
        Offset(houseRect.right - 8, y),
        Paint()
          ..color = const Color(0x22604428)
          ..strokeWidth = 2,
      );
    }

    final Path roof = Path()
      ..moveTo(houseRect.left - 42, houseRect.top + 34)
      ..lineTo(houseRect.center.dx, houseRect.top - 104)
      ..lineTo(houseRect.right + 42, houseRect.top + 34)
      ..lineTo(houseRect.right + 14, houseRect.top + 69)
      ..lineTo(houseRect.center.dx, houseRect.top - 34)
      ..lineTo(houseRect.left - 14, houseRect.top + 69)
      ..close();
    canvas.drawPath(
      roof,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(house.roofColor, Colors.white, 0.16)!,
            _night
                ? const Color(0xFF30442E)
                : Color.lerp(house.roofColor, Colors.black, 0.18)!,
          ],
        ).createShader(roof.getBounds()),
    );
    for (int i = 0; i < 9; i += 1) {
      final double y = houseRect.top - 50 + i * 12;
      canvas.drawLine(
        Offset(houseRect.left + 38 + i * 16, y),
        Offset(houseRect.right - 38 - i * 16, y),
        Paint()
          ..color = const Color(0x22402F1E)
          ..strokeWidth = 3,
      );
    }
    canvas.drawPath(
      roof,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = houseActive ? 8 : 5
        ..color = houseActive
            ? const Color(
                0xFFFFE76D,
              ).withValues(alpha: 0.62 + sin(time * 3) * 0.16)
            : const Color(0x77432D1B),
    );

    final Rect door = Rect.fromCenter(
      center: Offset(houseRect.center.dx, houseRect.bottom - 66),
      width: 66,
      height: 132,
    );
    if (houseActive) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(door.inflate(18), const Radius.circular(28)),
        Paint()
          ..color = const Color(0xFFFFE889).withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(door, const Radius.circular(22)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA86C38), Color(0xFF68401F)],
        ).createShader(door),
    );
    canvas.drawCircle(
      Offset(door.right - 17, door.center.dy + 4),
      4.5,
      Paint()..color = const Color(0xFFFFD36A),
    );
    if (dailyComplete) {
      canvas.drawCircle(
        door.topCenter + const Offset(0, 36),
        17,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = const Color(0xFF5AA347),
      );
    }

    final int sideWindows = 2 + tier;
    for (int side = 0; side < 2; side += 1) {
      for (int i = 0; i < sideWindows; i += 1) {
        final double x = side == 0
            ? houseRect.left + 62 + i * 78
            : houseRect.right - 108 - i * 78;
        final Rect window = Rect.fromLTWH(x, houseRect.top + 74, 48, 58);
        final double shimmer = (sin(time * 1.4 + i + side * 2.4) + 1) * 0.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(window, const Radius.circular(8)),
          Paint()
            ..color =
                (_night ? const Color(0xFFFFD878) : const Color(0xFF78CEE7))
                    .withValues(alpha: 0.72 + shimmer * 0.18),
        );
        canvas.drawLine(
          window.topCenter,
          window.bottomCenter,
          Paint()
            ..color = const Color(0xAA64401F)
            ..strokeWidth = 3,
        );
        canvas.drawLine(
          window.centerLeft,
          window.centerRight,
          Paint()
            ..color = const Color(0xAA64401F)
            ..strokeWidth = 3,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(window, const Radius.circular(8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = const Color(0xAA5A3A1B),
        );
        if (tier > 0) {
          final Rect flowerBox = Rect.fromLTWH(
            window.left - 4,
            window.bottom + 5,
            window.width + 8,
            12,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(flowerBox, const Radius.circular(4)),
            Paint()..color = const Color(0xFF7A4B28),
          );
          for (int bloom = 0; bloom < 4; bloom += 1) {
            canvas.drawCircle(
              Offset(flowerBox.left + 10 + bloom * 12, flowerBox.top),
              5,
              Paint()
                ..color = bloom.isEven
                    ? const Color(0xFFF087B2)
                    : const Color(0xFFFFD45D),
            );
          }
        }
      }
    }

    final Rect porch = Rect.fromCenter(
      center: Offset(houseRect.center.dx, houseRect.bottom + 8),
      width: 340 + tier * 58,
      height: 42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(porch, const Radius.circular(12)),
      Paint()..color = const Color(0xFFB78A4B),
    );
    for (double x = porch.left + 16; x < porch.right; x += 34) {
      canvas.drawLine(
        Offset(x, porch.top + 4),
        Offset(x + 12, porch.bottom - 4),
        Paint()
          ..color = const Color(0x33633918)
          ..strokeWidth = 2,
      );
    }
    for (int step = 0; step < 3; step += 1) {
      final Rect stair = Rect.fromCenter(
        center: Offset(houseRect.center.dx, porch.bottom + 10 + step * 13),
        width: 150 - step * 18,
        height: 16,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(stair, const Radius.circular(7)),
        Paint()
          ..color = Color.lerp(
            const Color(0xFFC69A5A),
            const Color(0xFF7F5A31),
            step / 4,
          )!,
      );
    }
  }

  void _drawPath(Canvas canvas, Size size) {
    final Path route = Path()
      ..moveTo(size.width * 0.48, 450)
      ..cubicTo(size.width * 0.58, 568, 318, 638, 432, 792)
      ..cubicTo(572, 988, 288, 1098, 418, 1306)
      ..cubicTo(512, 1462, 438, 1550, 548, size.height + 80);

    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 166
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xAA6B5A36),
    );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 132
        ..strokeCap = StrokeCap.round
        ..color = _winter ? const Color(0xFFE3DCC5) : const Color(0xFFD2BA78),
    );

    for (int i = 0; i < 20; i += 1) {
      final double y = 482 + i * 60;
      final double x = 430 + sin(i * 0.88) * 68 + cos(i * 0.33) * 22;
      final Rect stone = Rect.fromCenter(
        center: Offset(x, y),
        width: 92 + (i % 3) * 13,
        height: 44 + (i % 2) * 9,
      );
      canvas.save();
      canvas.translate(stone.center.dx, stone.center.dy);
      canvas.rotate(sin(i) * 0.12);
      final Rect local = Rect.fromCenter(
        center: Offset.zero,
        width: stone.width,
        height: stone.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(local, const Radius.circular(22)),
        Paint()
          ..color = _winter ? const Color(0xFFF6F3DF) : const Color(0xFFEAD89B),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(local, const Radius.circular(22)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = const Color(0x55775B31),
      );
      canvas.restore();
    }
  }

  void _drawPond(Canvas canvas, Size size) {
    final Path pond = Path()
      ..moveTo(-86, 1128)
      ..cubicTo(46, 1056, 208, 1072, 262, 1192)
      ..cubicTo(330, 1346, 204, 1488, 16, 1470)
      ..cubicTo(-132, 1454, -160, 1262, -86, 1128)
      ..close();
    canvas.drawPath(
      pond,
      Paint()
        ..color = const Color(0x55293521)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      pond,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF55C6D8), Color(0xFF23789E), Color(0xFF185A73)],
        ).createShader(Rect.fromLTWH(-100, 1060, 390, 440)),
    );
    canvas.drawPath(
      pond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = const Color(0xCC7B8D5C),
    );

    final Paint ripple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.24);
    for (int i = 0; i < 8; i += 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(58 + i * 24, 1194 + sin(time + i) * 18 + i * 24),
          width: 42 + i * 4,
          height: 12 + i.toDouble(),
        ),
        ripple,
      );
    }
    final Paint lily = Paint()..color = const Color(0xFF7CC452);
    for (int i = 0; i < 10; i += 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(18 + (i * 53) % 210, 1152 + (i * 47) % 250),
          width: 34,
          height: 18,
        ),
        lily,
      );
    }
  }

  void _drawFenceAndBorders(Canvas canvas, Size size) {
    final Paint post = Paint()..color = const Color(0xFF8A6130);
    final Paint rail = Paint()..color = const Color(0xFFB98542);
    for (double x = -20; x < size.width + 40; x += 72) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 392, 18, 92),
          const Radius.circular(6),
        ),
        post,
      );
    }
    for (int row = 0; row < 2; row += 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-20, 414 + row * 38, size.width + 40, 16),
          const Radius.circular(8),
        ),
        rail,
      );
    }

    final Paint hedge = Paint()
      ..color = (_night ? const Color(0xFF274F38) : const Color(0xFF3F8B3D));
    for (double y = 438; y < size.height; y += 74) {
      canvas.drawCircle(Offset(18 + sin(y) * 8, y), 42, hedge);
      canvas.drawCircle(
        Offset(size.width - 22 + cos(y) * 7, y + 28),
        46,
        hedge,
      );
    }
  }

  void _drawBackyardDetails(Canvas canvas, Size size) {
    final int tier = house.maxGardenLevel <= 3
        ? 0
        : house.maxGardenLevel <= 5
        ? 1
        : 2;
    final Paint flowerPink = Paint()..color = const Color(0xFFE97AAD);
    final Paint flowerBlue = Paint()..color = const Color(0xFF73BFF0);
    final Paint flowerCore = Paint()..color = const Color(0xFFFFE06A);

    for (int i = 0; i < 58 + tier * 14; i += 1) {
      final bool leftSide = i.isEven;
      final double x = leftSide
          ? 44 + ((i * 29) % 132)
          : 740 + ((i * 31) % 126);
      final double y = 474 + ((i * 67) % 1030);
      final Paint petal = i % 3 == 0 ? flowerBlue : flowerPink;
      for (int p = 0; p < 5; p += 1) {
        final double a = p * pi * 2 / 5;
        canvas.drawCircle(Offset(x + cos(a) * 5, y + sin(a) * 5), 3.2, petal);
      }
      canvas.drawCircle(Offset(x, y), 2.2, flowerCore);
    }

    _drawSmallTree(canvas, const Offset(54, 612), 0.62, fruit: false);
    _drawSmallTree(canvas, const Offset(866, 622), 0.6, fruit: true);
    if (tier >= 1) {
      _drawSmallTree(canvas, const Offset(858, 1372), 0.66, fruit: true);
    }
    if (tier >= 2) {
      _drawGreenhousePad(canvas, Rect.fromLTWH(352, 1460, 224, 132));
    }
  }

  void _drawGreenhousePad(Canvas canvas, Rect rect) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()..color = const Color(0x55294A38),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(10), const Radius.circular(20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xCCBFE0B7),
    );
    for (double x = rect.left + 28; x < rect.right - 20; x += 42) {
      canvas.drawLine(
        Offset(x, rect.top + 22),
        Offset(x + 22, rect.bottom - 20),
        Paint()
          ..strokeWidth = 3
          ..color = const Color(0x99E9FFF1),
      );
    }
    _drawMapLabel(canvas, rect.center, 'GREENHOUSE');
  }

  void _drawMapLabel(Canvas canvas, Offset center, String text) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Color(0xAA173410),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect bubble = Rect.fromCenter(
      center: center,
      width: painter.width + 24,
      height: painter.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubble, const Radius.circular(10)),
      Paint()..color = const Color(0xBB315E24),
    );
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _drawPlotBeds(Canvas canvas) {
    for (final plot in plots) {
      if (plot.unlockLevel > house.maxGardenLevel + 1) {
        continue;
      }
      final bool unlocked = plot.unlockLevel <= gardenLevel;
      final bool nextUnlock =
          plot.unlockLevel == gardenLevel + 1 &&
          plot.unlockLevel <= house.maxGardenLevel;
      final GardenZoneStyle style = _zoneStyleFor(plot.id);
      final Size zoneSize = _zoneSizeFor(style);
      final Rect zone = Rect.fromCenter(
        center: plot.position,
        width: zoneSize.width,
        height: zoneSize.height,
      );
      _drawGardenZone(
        canvas,
        zone,
        style: style,
        seed: plot.id + 11,
        unlocked: unlocked,
        nextUnlock: nextUnlock,
        grassCut: plot.grassCut,
      );
    }
  }

  GardenZoneStyle _zoneStyleFor(int id) {
    return GardenZoneStyle.values[id % GardenZoneStyle.values.length];
  }

  Size _zoneSizeFor(GardenZoneStyle style) {
    return switch (style) {
      GardenZoneStyle.orchard => const Size(252, 172),
      GardenZoneStyle.flowerBorder => const Size(232, 126),
      GardenZoneStyle.herbSpiral => const Size(186, 120),
      GardenZoneStyle.kitchenRows => const Size(220, 130),
      GardenZoneStyle.meadow => const Size(234, 144),
      GardenZoneStyle.trellis => const Size(214, 136),
    };
  }

  Path _organicZonePath(Rect rect, int seed, {double wobble = 0.08}) {
    const int pointCount = 14;
    final List<Offset> points = [];
    for (int i = 0; i < pointCount; i += 1) {
      final double angle = -pi / 2 + i * pi * 2 / pointCount;
      final double variation =
          1 +
          sin(seed * 1.73 + i * 2.17) * wobble +
          cos(seed * 0.61 + i * 1.31) * wobble * 0.45;
      points.add(
        Offset(
          rect.center.dx + cos(angle) * rect.width * 0.5 * variation,
          rect.center.dy + sin(angle) * rect.height * 0.5 * variation,
        ),
      );
    }
    final Path path = Path();
    final Offset firstMidpoint = (points.last + points.first) / 2;
    path.moveTo(firstMidpoint.dx, firstMidpoint.dy);
    for (int i = 0; i < points.length; i += 1) {
      final Offset point = points[i];
      final Offset next = points[(i + 1) % points.length];
      final Offset midpoint = (point + next) / 2;
      path.quadraticBezierTo(point.dx, point.dy, midpoint.dx, midpoint.dy);
    }
    return path..close();
  }

  void _drawGardenZone(
    Canvas canvas,
    Rect zone, {
    required GardenZoneStyle style,
    required int seed,
    required bool unlocked,
    required bool nextUnlock,
    required bool grassCut,
  }) {
    final Path boundary = _organicZonePath(zone, seed);
    canvas.drawPath(
      boundary.shift(const Offset(0, 15)),
      Paint()
        ..color = const Color(0x44301F10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    if (!unlocked) {
      if (grassCut) {
        _drawPreparedClearing(canvas, zone, boundary, seed, nextUnlock);
      } else {
        _drawOvergrownMeadow(canvas, zone, boundary, seed, nextUnlock);
      }
      return;
    }

    canvas.drawPath(
      boundary,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.4),
          radius: 1.15,
          colors: _winter
              ? const [Color(0xFF6A5A43), Color(0xFF3D3328)]
              : const [Color(0xFF8C5B31), Color(0xFF4A2E1B)],
        ).createShader(zone),
    );
    canvas.drawPath(
      boundary,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = (_winter ? const Color(0xFFDCE8D5) : const Color(0xFF3F7D36))
            .withValues(alpha: 0.9),
    );
    canvas.drawPath(
      boundary,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFB89A64).withValues(alpha: 0.76),
    );
    _drawSoilTexture(canvas, zone, boundary, seed);
    _drawZoneDetails(canvas, zone.deflate(12), style, seed);

    if (_winter) {
      canvas.drawPath(
        boundary,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.white.withValues(alpha: 0.34),
      );
    }
  }

  void _drawPreparedClearing(
    Canvas canvas,
    Rect zone,
    Path boundary,
    int seed,
    bool active,
  ) {
    canvas.drawPath(
      boundary,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF91B963), Color(0xFF6E964C)],
        ).createShader(zone),
    );
    for (int i = 0; i < 7; i += 1) {
      final double y = zone.top + 18 + i * (zone.height - 36) / 6;
      canvas.drawLine(
        Offset(zone.left + 18, y),
        Offset(zone.right - 18, y - 9),
        Paint()
          ..color = const Color(0xFFCEE99A).withValues(alpha: 0.34)
          ..strokeWidth = 6,
      );
    }
    final Paint stakePaint = Paint()
      ..color = const Color(0xFF8A5D2D)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final Offset corner in [
      zone.topLeft + const Offset(18, 18),
      zone.topRight + const Offset(-18, 18),
      zone.bottomLeft + const Offset(18, -18),
      zone.bottomRight + const Offset(-18, -18),
    ]) {
      canvas.drawLine(corner, corner + const Offset(0, -24), stakePaint);
    }
    if (active) {
      _drawDashedBoundary(canvas, boundary);
    }
  }

  void _drawOvergrownMeadow(
    Canvas canvas,
    Rect zone,
    Path boundary,
    int seed,
    bool active,
  ) {
    canvas.drawPath(
      boundary,
      Paint()
        ..color = (_night ? const Color(0xFF315A38) : const Color(0xFF4F913B))
            .withValues(alpha: active ? 0.88 : 0.62),
    );
    final Paint blade = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = active ? 4 : 3
      ..color = const Color(0xFF2D7231).withValues(alpha: 0.92);
    for (int i = 0; i < 52; i += 1) {
      final double x =
          zone.left +
          14 +
          ((i * 47 + seed * 23) % 1000) / 1000 * (zone.width - 28);
      final double y =
          zone.top +
          18 +
          ((i * 79 + seed * 31) % 1000) / 1000 * (zone.height - 30);
      final double sway = sin(time * 2.4 + i * 0.8) * 8;
      canvas.drawLine(
        Offset(x, y + 13),
        Offset(x + sway, y - 14 - (i % 3) * 4),
        blade,
      );
    }
    if (active) {
      _drawDashedBoundary(canvas, boundary);
    }
  }

  void _drawDashedBoundary(Canvas canvas, Path boundary) {
    final Paint guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(
        0xFFFFEA72,
      ).withValues(alpha: 0.62 + sin(time * 3) * 0.16);
    for (final metric in boundary.computeMetrics()) {
      for (double start = 0; start < metric.length; start += 24) {
        canvas.drawPath(
          metric.extractPath(start, min(metric.length, start + 12)),
          guide,
        );
      }
    }
  }

  void _drawSoilTexture(Canvas canvas, Rect zone, Path boundary, int seed) {
    canvas.save();
    canvas.clipPath(boundary);
    for (int i = 0; i < 34; i += 1) {
      final Offset point = Offset(
        zone.left + ((i * 83 + seed * 19) % 1000) / 1000 * zone.width,
        zone.top + ((i * 137 + seed * 29) % 1000) / 1000 * zone.height,
      );
      canvas.drawCircle(
        point,
        1.8 + (i % 4) * 0.7,
        Paint()
          ..color =
              (i.isEven ? const Color(0xFFCC9B61) : const Color(0xFF2D1B12))
                  .withValues(alpha: 0.22),
      );
    }
    canvas.restore();
  }

  void _drawZoneDetails(
    Canvas canvas,
    Rect zone,
    GardenZoneStyle style,
    int seed,
  ) {
    switch (style) {
      case GardenZoneStyle.orchard:
        final Paint root = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFB9824C).withValues(alpha: 0.38);
        for (int i = 0; i < 9; i += 1) {
          final double angle = i * pi * 2 / 9;
          final Offset end = Offset(
            zone.center.dx + cos(angle) * zone.width * 0.42,
            zone.center.dy + sin(angle) * zone.height * 0.38,
          );
          canvas.drawLine(zone.center, end, root);
        }
      case GardenZoneStyle.flowerBorder:
        final Paint timber = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF9B6B36);
        canvas.drawArc(zone.inflate(4), pi * 1.08, pi * 0.84, false, timber);
      case GardenZoneStyle.herbSpiral:
        final Path spiral = Path();
        for (int i = 0; i < 46; i += 1) {
          final double angle = i * 0.42;
          final double radius = i / 46 * min(zone.width, zone.height) * 0.38;
          final Offset point = Offset(
            zone.center.dx + cos(angle) * radius,
            zone.center.dy + sin(angle) * radius * 0.66,
          );
          if (i == 0) {
            spiral.moveTo(point.dx, point.dy);
          } else {
            spiral.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          spiral,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFB88955).withValues(alpha: 0.7),
        );
      case GardenZoneStyle.kitchenRows:
        for (int i = 0; i < 4; i += 1) {
          final double y = zone.top + 20 + i * (zone.height - 40) / 3;
          canvas.drawLine(
            Offset(zone.left + 18, y),
            Offset(zone.right - 18, y - 5),
            Paint()
              ..strokeWidth = 6
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFC08A50).withValues(alpha: 0.58),
          );
        }
      case GardenZoneStyle.meadow:
        for (int i = 0; i < 18; i += 1) {
          canvas.drawCircle(
            Offset(
              zone.left + ((i * 67 + seed) % 1000) / 1000 * zone.width,
              zone.top + ((i * 109 + seed) % 1000) / 1000 * zone.height,
            ),
            3 + (i % 2).toDouble(),
            Paint()..color = const Color(0xFF7EB44A).withValues(alpha: 0.52),
          );
        }
      case GardenZoneStyle.trellis:
        final Paint wood = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6
          ..color = const Color(0xFFA8753D).withValues(alpha: 0.82);
        for (int i = 0; i < 4; i += 1) {
          final double x = zone.left + 28 + i * (zone.width - 56) / 3;
          canvas.drawLine(
            Offset(x, zone.bottom - 8),
            Offset(x, zone.top + 12),
            wood,
          );
        }
        canvas.drawLine(
          Offset(zone.left + 20, zone.top + 28),
          Offset(zone.right - 20, zone.top + 28),
          wood,
        );
    }
  }

  void _drawSmallTree(
    Canvas canvas,
    Offset base,
    double scale, {
    required bool fruit,
  }) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(scale);
    final double sway = sin(time * 1.15 + base.dx * 0.01) * 7;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 74), width: 28, height: 96),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFF7A4F29),
    );
    final Paint leaves = Paint()
      ..color = _winter ? const Color(0xFFB8D5A8) : const Color(0xFF4D9838);
    int canopyIndex = 0;
    for (final offset in const [
      Offset(-42, 20),
      Offset(0, -2),
      Offset(42, 20),
      Offset(-20, 52),
      Offset(28, 58),
    ]) {
      final double canopySway = sway * (0.55 + canopyIndex * 0.08);
      canvas.drawCircle(offset + Offset(canopySway, 0), 46, leaves);
      canopyIndex += 1;
    }
    if (fruit) {
      final Paint apple = Paint()..color = const Color(0xFFD84D33);
      for (final offset in const [
        Offset(-34, 22),
        Offset(15, 10),
        Offset(40, 46),
        Offset(-4, 62),
      ]) {
        canvas.drawCircle(offset + Offset(sway * 0.72, 0), 8, apple);
      }
    }
    canvas.restore();
  }

  void _drawBambooStand(Canvas canvas, Offset base, double scale) {
    final Paint stalk = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 11 * scale
      ..color = const Color(0xFF62A94C).withValues(alpha: 0.86);
    final Paint ring = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2 * scale
      ..color = const Color(0xFFD9F7A2).withValues(alpha: 0.82);
    for (int i = 0; i < 5; i += 1) {
      final double x = base.dx + i * 22 * scale;
      final double top = base.dy - (i % 2) * 44 * scale;
      final double bottom = base.dy + 360 * scale;
      canvas.drawLine(Offset(x, top), Offset(x + 24 * scale, bottom), stalk);
      for (double y = top + 44 * scale; y < bottom; y += 58 * scale) {
        canvas.drawLine(
          Offset(x - 5 * scale, y),
          Offset(x + 14 * scale, y),
          ring,
        );
      }
    }
  }

  void _drawMoodOverlay(Canvas canvas, Size size) {
    if (mood < 38) {
      final double strength = (38 - mood) / 38;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = const Color(
            0xFF6F684B,
          ).withValues(alpha: 0.08 + strength * 0.16),
      );
    } else if (mood >= 82) {
      final Rect glowRect = Rect.fromLTWH(
        size.width * 0.12,
        310,
        size.width * 0.76,
        size.height * 0.62,
      );
      canvas.drawOval(
        glowRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF2A1).withValues(alpha: 0.1),
              Colors.transparent,
            ],
          ).createShader(glowRect),
      );
    }
    if (_night) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x66233F78),
      );
    }
    if (_winter) {
      final Paint snowPatch = Paint()
        ..color = Colors.white.withValues(alpha: 0.36)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      for (int i = 0; i < 18; i += 1) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              ((i * 97) % 1000) / 1000 * size.width,
              260 + ((i * 173) % 1000) / 1000 * (size.height - 280),
            ),
            width: 90 + (i % 4) * 30,
            height: 24 + (i % 3) * 13,
          ),
          snowPatch,
        );
      }
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: _night ? 0.03 : 0.08),
            Colors.transparent,
            Colors.black.withValues(alpha: _night ? 0.18 : 0.08),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _BackyardGardenPainter oldDelegate) {
    return oldDelegate.world != world ||
        oldDelegate.house != house ||
        oldDelegate.time != time ||
        oldDelegate.gardenLevel != gardenLevel ||
        oldDelegate.mood != mood ||
        oldDelegate.dailyComplete != dailyComplete ||
        oldDelegate.houseActive != houseActive ||
        oldDelegate.plots != plots;
  }
}

class _GardenAmbientPainter extends CustomPainter {
  const _GardenAmbientPainter({required this.world, required this.time});

  final GardenWorld world;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    switch (world.ambient) {
      case GardenAmbient.petals:
        _paintPetals(canvas, size, const Color(0xFFF8A7D1), 34);
      case GardenAmbient.bambooLeaves:
        _paintLeaves(canvas, size, const Color(0xFFA8E96C), 30);
      case GardenAmbient.fireflies:
        _paintFireflies(canvas, size);
      case GardenAmbient.snow:
        _paintSnow(canvas, size);
    }
  }

  void _paintPetals(Canvas canvas, Size size, Color color, int count) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.48);
    for (int i = 0; i < count; i += 1) {
      final double x =
          ((i * 83) % 1000) / 1000 * size.width + sin(time * 0.7 + i) * 26;
      final double y =
          ((((i * 137) % 1000) / 1000 * size.height) + time * 18 + i * 5) %
              (size.height + 80) -
          40;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(sin(time + i) * 0.8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 5 + (i % 3).toDouble(),
          height: 10 + (i % 4).toDouble(),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintLeaves(Canvas canvas, Size size, Color color, int count) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.42);
    for (int i = 0; i < count; i += 1) {
      final double x =
          ((((i * 97) % 1000) / 1000 * size.width) - time * 22 + i * 3) %
              (size.width + 90) -
          45;
      final double y =
          ((((i * 151) % 1000) / 1000 * size.height) + time * 15 + i * 4) %
              (size.height + 80) -
          40;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.7 + sin(time * 0.9 + i) * 0.45);
      final Path leaf = Path()
        ..moveTo(0, -8)
        ..quadraticBezierTo(8, 0, 0, 9)
        ..quadraticBezierTo(-8, 0, 0, -8)
        ..close();
      canvas.drawPath(leaf, paint);
      canvas.restore();
    }
  }

  void _paintFireflies(Canvas canvas, Size size) {
    for (int i = 0; i < 24; i += 1) {
      final double pulse = (sin(time * 2.1 + i * 1.7) + 1) / 2;
      final double x =
          ((i * 113) % 1000) / 1000 * size.width + sin(time * 0.55 + i) * 18;
      final double y =
          ((i * 179) % 1000) / 1000 * size.height +
          cos(time * 0.45 + i * 0.6) * 15;
      final Paint glow = Paint()
        ..color = const Color(0xFFFFEE8A).withValues(alpha: 0.12 + pulse * 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      canvas.drawCircle(Offset(x, y), 5 + pulse * 5, glow);
      canvas.drawCircle(
        Offset(x, y),
        1.3 + pulse,
        Paint()
          ..color = const Color(
            0xFFFFF6A0,
          ).withValues(alpha: 0.42 + pulse * 0.44),
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.white.withValues(alpha: 0.62);
    for (int i = 0; i < 52; i += 1) {
      final double x =
          ((i * 71) % 1000) / 1000 * size.width + sin(time * 0.4 + i) * 14;
      final double y =
          ((((i * 127) % 1000) / 1000 * size.height) + time * 24 + i * 6) %
              (size.height + 60) -
          30;
      canvas.drawCircle(Offset(x, y), 1.2 + (i % 4) * 0.45, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GardenAmbientPainter oldDelegate) {
    return oldDelegate.world != world || oldDelegate.time != time;
  }
}

class _GardenStatChip extends StatelessWidget {
  const _GardenStatChip({required this.value, this.asset, this.icon});

  final String value;
  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 39,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEE304A43), Color(0xEE1A2F2B)],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xAA9FC485), width: 1.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (asset != null)
            Image.asset(asset!, width: 25, height: 25)
          else
            Icon(icon, color: const Color(0xFFC8F783), size: 24),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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
    final (Color top, Color bottom, Color border, Color glow) = switch (label) {
      'Water' => (
        const Color(0xFF60A8CB),
        const Color(0xFF1F5E83),
        const Color(0xFF94D7FF),
        const Color(0x6639A7E8),
      ),
      'Clear' => (
        const Color(0xFFC4914F),
        const Color(0xFF71411D),
        const Color(0xFFFFD58B),
        const Color(0x66D18B35),
      ),
      'Sun' => (
        const Color(0xFFC8A126),
        const Color(0xFF6F5A12),
        const Color(0xFFFFDD63),
        const Color(0x66FFD84D),
      ),
      _ => (
        const Color(0xFF8AC448),
        const Color(0xFF356D1F),
        const Color(0xFFCFF78A),
        const Color(0x668CEB4E),
      ),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: selected ? 1.03 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? const Color(0xFFFFF08A) : border,
              width: selected ? 3 : 2,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x99000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
              BoxShadow(
                color: selected ? glow : Colors.transparent,
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 40),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Color(0xAA000000),
                        blurRadius: 2,
                        offset: Offset(0, 2),
                      ),
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
    final bool tree = option.name.endsWith('Tree');
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
                  width: tree ? 58 : 46,
                  height: tree ? 74 : 62,
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

class _GardenPlantTargetGlow extends StatelessWidget {
  const _GardenPlantTargetGlow({super.key, required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.scale(
        scale: 1 + (pulse * 0.045),
        child: SizedBox(
          width: 178,
          height: 120,
          child: CustomPaint(painter: _GardenGroundTargetPainter(pulse: pulse)),
        ),
      ),
    );
  }
}

class _GardenGroundTargetPainter extends CustomPainter {
  const _GardenGroundTargetPainter({required this.pulse});

  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Rect.fromLTWH(
      10,
      12,
      size.width - 20,
      size.height - 24,
    );
    final List<Offset> points = [];
    for (int i = 0; i < 12; i += 1) {
      final double angle = -pi / 2 + i * pi * 2 / 12;
      final double wobble = 1 + sin(i * 2.3) * 0.08;
      points.add(
        Offset(
          bounds.center.dx + cos(angle) * bounds.width * 0.5 * wobble,
          bounds.center.dy + sin(angle) * bounds.height * 0.5 * wobble,
        ),
      );
    }
    final Path path = Path();
    final Offset start = (points.last + points.first) / 2;
    path.moveTo(start.dx, start.dy);
    for (int i = 0; i < points.length; i += 1) {
      final Offset current = points[i];
      final Offset next = points[(i + 1) % points.length];
      final Offset midpoint = (current + next) / 2;
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14 + pulse * 4
        ..color = const Color(0xFFFFE65D).withValues(alpha: 0.16 + pulse * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2 + pulse
      ..color = Color.lerp(
        const Color(0xFFF5FFB5),
        const Color(0xFFFFD83D),
        pulse,
      )!;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 22) {
        canvas.drawPath(
          metric.extractPath(d, min(metric.length, d + 11)),
          dash,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GardenGroundTargetPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}

class _GardenPlantTargetMarker extends StatelessWidget {
  const _GardenPlantTargetMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: -18,
          child: Container(
            width: 7,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF6D4420),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xFF3F240F), width: 1),
            ),
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7B5B2A), Color(0xFF3F2B14)],
            ),
            border: Border.all(color: const Color(0xFFE9CC7A), width: 2.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 9,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_florist_rounded,
            color: Color(0xFFBDF57A),
            size: 27,
          ),
        ),
      ],
    );
  }
}

class _GardenTinyBadge extends StatelessWidget {
  const _GardenTinyBadge({
    required this.text,
    this.color = const Color(0xEE2E6D24),
    this.borderColor = const Color(0xFFFFFFFF),
  });

  final String text;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 7,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _GardenBadgeTailPainter(
            color: color,
            borderColor: borderColor,
          ),
        ),
      ],
    );
  }
}

class _GardenBadgeTailPainter extends CustomPainter {
  const _GardenBadgeTailPainter({
    required this.color,
    required this.borderColor,
  });

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = borderColor,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GardenBadgeTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
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

class _GardenStreakChip extends StatelessWidget {
  const _GardenStreakChip({
    super.key,
    required this.streak,
    required this.tendedToday,
  });

  final int streak;
  final bool tendedToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xDD263B31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tendedToday
              ? const Color(0xFFFFDF7E)
              : const Color(0xCCBEEB86),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 9,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/icons/star_reward.png',
            width: 18,
            height: 18,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Day $streak',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              if (tendedToday) ...[
                const SizedBox(width: 3),
                const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey('garden-tended-star'),
                  color: Color(0xFFB9F177),
                  size: 11,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GardenForecastPill extends StatelessWidget {
  const _GardenForecastPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xC9152E14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x99CDEF9A), width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: Color(0xFFD7F5A8),
            size: 15,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFFEFFFDD),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GardenWelcomeCard extends StatelessWidget {
  const _GardenWelcomeCard({
    super.key,
    required this.streak,
    required this.lines,
    required this.onClose,
  });

  final int streak;
  final List<String> lines;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 34),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xF2153B17),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBDEB78), width: 2.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/sprites/ninja_mascot.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Day $streak in the garden',
                    style: const TextStyle(
                      color: Color(0xFFD7F5A8),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.eco_rounded,
                            color: Color(0xFF9EDB5A),
                            size: 15,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: Color(0xFFEFFFDD),
                                fontSize: 13.5,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap anywhere to tend your garden',
                    style: TextStyle(
                      color: Color(0xFFA8CE7F),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
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
            SizedBox(
              width: 52,
              height: 46,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(height: 5),
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
