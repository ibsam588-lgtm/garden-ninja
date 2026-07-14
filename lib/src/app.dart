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

enum GardenTool { harvest, plant, water, build, move, sun }

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

class GardenMarketOrder {
  const GardenMarketOrder({
    required this.produce,
    required this.quantity,
    required this.coinReward,
    required this.pointReward,
  });

  final String produce;
  final int quantity;
  final int coinReward;
  final int pointReward;
}

class GardenCustomerOrder {
  const GardenCustomerOrder({
    required this.customer,
    required this.produce,
    required this.quantity,
    required this.coinReward,
    required this.pointReward,
  });

  final String customer;
  final String produce;
  final int quantity;
  final int coinReward;
  final int pointReward;
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
    this.carePoints = 0,
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
  int carePoints;
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
  static const double _playerGardenHeight = 1900;
  static const double _gardenMinScale = 0.445;
  static const double _gardenMaxScale = 1.65;
  static const double _gardenInitialScale = 0.445;
  static const double _gardenInitialTranslateX = -9;
  static const double _gardenInitialTranslateY = 66;
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
      maxGardenLevel: 6,
      unlockPoints: 1800,
      seedCost: 350,
      roofColor: Color(0xFF8E5A31),
      wallColor: Color(0xFFFFD6A1),
      bonus: 'market orders and Lv 3 plants',
    ),
    GardenHouseTier(
      name: 'Garden Villa',
      maxGardenLevel: 9,
      unlockPoints: 5200,
      seedCost: 1200,
      roofColor: Color(0xFF4F6F86),
      wallColor: Color(0xFFE8F3FF),
      bonus: 'orchard land and Lv 4 plants',
    ),
    GardenHouseTier(
      name: 'Orchard Manor',
      maxGardenLevel: 12,
      unlockPoints: 11000,
      seedCost: 2800,
      roofColor: Color(0xFF6D466F),
      wallColor: Color(0xFFFFE4D0),
      bonus: 'larger pantry and golden orders',
    ),
    GardenHouseTier(
      name: 'Blossom Estate',
      maxGardenLevel: 15,
      unlockPoints: 22000,
      seedCost: 6200,
      roofColor: Color(0xFF375A4A),
      wallColor: Color(0xFFF3EBDD),
      bonus: 'final estate and Lv 4 plants',
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
      position: const Offset(486, 650),
      unlockLevel: 1,
      asset: 'assets/images/sprites/tree_apple.png',
      plantIndex: 6,
      growth: 0.7,
      watered: true,
      grassCut: true,
    ),
    PlayerGardenPlot(
      id: 1,
      position: const Offset(182, 908),
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
      position: const Offset(704, 964),
      unlockLevel: 1,
      asset: 'assets/images/sprites/blue_bell_bloom.png',
      plantIndex: 1,
      growth: 0.74,
      grassCut: true,
    ),
    PlayerGardenPlot(
      id: 3,
      position: const Offset(474, 1064),
      unlockLevel: 1,
      grassCut: true,
    ),
    PlayerGardenPlot(id: 4, position: const Offset(704, 286), unlockLevel: 2),
    PlayerGardenPlot(id: 5, position: const Offset(772, 456), unlockLevel: 3),
    PlayerGardenPlot(id: 6, position: const Offset(788, 638), unlockLevel: 4),
    PlayerGardenPlot(id: 7, position: const Offset(184, 1080), unlockLevel: 5),
    PlayerGardenPlot(id: 8, position: const Offset(476, 1100), unlockLevel: 6),
    PlayerGardenPlot(id: 9, position: const Offset(742, 1110), unlockLevel: 7),
    PlayerGardenPlot(id: 10, position: const Offset(184, 1320), unlockLevel: 8),
    PlayerGardenPlot(id: 11, position: const Offset(476, 1340), unlockLevel: 9),
    PlayerGardenPlot(
      id: 12,
      position: const Offset(742, 1340),
      unlockLevel: 10,
    ),
    PlayerGardenPlot(
      id: 13,
      position: const Offset(154, 1580),
      unlockLevel: 11,
    ),
    PlayerGardenPlot(
      id: 14,
      position: const Offset(374, 1600),
      unlockLevel: 12,
    ),
    PlayerGardenPlot(
      id: 15,
      position: const Offset(590, 1600),
      unlockLevel: 13,
    ),
    PlayerGardenPlot(
      id: 16,
      position: const Offset(790, 1570),
      unlockLevel: 14,
    ),
    PlayerGardenPlot(
      id: 17,
      position: const Offset(500, 1810),
      unlockLevel: 15,
    ),
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
  GardenTool _gardenTool = GardenTool.harvest;
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
  int? _gardenMovingPlotId;
  int _gardenLoginStreak = 1;
  int _gardenBestStreak = 1;
  int _gardenMood = 62;
  int _gardenCompost = 0;
  int _gardenBouquets = 0;
  int _gardenApples = 0;
  int _gardenLemons = 0;
  int _gardenOranges = 0;
  int _gardenPondWater = 4;
  int _gardenMarketSales = 0;
  int _gardenCustomersServed = 0;
  int _gardenCustomerOrderIndex = 0;
  int _gardenHeartPoints = 12;
  int? _gardenCustomerNextAtMs;
  int? _gardenLawnLastMowedMs;
  int? _gardenPondRefillMs;
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
  bool _showGardenMarketPanel = false;
  bool _showGardenHeartPanel = false;
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
  double _gardenHeartPulse = 0;
  double _gardenCustomerCelebration = 0;
  double _gardenCutBurst = 0;
  double _motionTime = 0;
  int? _gardenCutPlotId;
  Offset? _lastSlashPoint;
  Offset _gardenCaretakerPosition = const Offset(360, 760);
  Offset _gardenCaretakerTarget = const Offset(360, 760);
  bool _gardenCaretakerMoving = false;
  String _gardenMessage = 'Tap empty plot to open nursery';
  String? _gardenLastLoginDay;
  String? _gardenStreakGraceDay;
  String? _gardenLastTendedDay;
  String? _gardenGiftDay;
  String? _gardenDailyTaskDay;
  String? _gardenWaterBarrelDay;
  String? _gardenHabitatDay;
  String? _gardenOrderClaimedDay;
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
    if (duration.inMinutes < 1) {
      return '${max(1, duration.inSeconds)}s';
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
    _gardenBouquets = max(
      0,
      (data['gardenBouquets'] as num?)?.toInt() ?? _gardenBouquets,
    );
    _gardenApples = max(
      0,
      (data['gardenApples'] as num?)?.toInt() ?? _gardenApples,
    );
    _gardenLemons = max(
      0,
      (data['gardenLemons'] as num?)?.toInt() ?? _gardenLemons,
    );
    _gardenOranges = max(
      0,
      (data['gardenOranges'] as num?)?.toInt() ?? _gardenOranges,
    );
    _gardenPondWater =
        ((data['gardenPondWater'] as num?)?.toInt() ?? _gardenPondWater)
            .clamp(0, 6)
            .toInt();
    _gardenMarketSales = max(
      0,
      (data['gardenMarketSales'] as num?)?.toInt() ?? _gardenMarketSales,
    );
    _gardenCustomersServed = max(
      0,
      (data['gardenCustomersServed'] as num?)?.toInt() ??
          _gardenCustomersServed,
    );
    _gardenCustomerOrderIndex = max(
      0,
      (data['gardenCustomerOrderIndex'] as num?)?.toInt() ??
          _gardenCustomerOrderIndex,
    );
    _gardenCustomerNextAtMs = (data['gardenCustomerNextAtMs'] as num?)?.toInt();
    _gardenHeartPoints = max(
      0,
      (data['gardenHeartPoints'] as num?)?.toInt() ??
          min(60, _gardenHarvests * 3 + _gardenLevel * 5),
    );
    _gardenLawnLastMowedMs = (data['gardenLawnLastMowedMs'] as num?)?.toInt();
    _gardenPondRefillMs = (data['gardenPondRefillMs'] as num?)?.toInt();
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
    _gardenOrderClaimedDay = data['gardenOrderClaimedDay'] as String?;
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
          plot.carePoints = 0;
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
          plot.carePoints = max(
            0,
            (rawPlot['carePoints'] as num?)?.toInt() ??
                (rawPlot['mature'] == true ? 3 : 1),
          );
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
      'version': 7,
      'seeds': _seeds,
      'waterCharges': _waterCharges,
      'sunDrops': _sunDrops,
      'gardenPoints': _gardenPoints,
      'gardenLevel': _gardenLevel,
      'gardenHouseTier': _gardenHouseTier,
      'gardenHarvests': _gardenHarvests,
      'gardenMood': _gardenMood,
      'gardenCompost': _gardenCompost,
      'gardenBouquets': _gardenBouquets,
      'gardenApples': _gardenApples,
      'gardenLemons': _gardenLemons,
      'gardenOranges': _gardenOranges,
      'gardenPondWater': _gardenPondWater,
      'gardenMarketSales': _gardenMarketSales,
      'gardenCustomersServed': _gardenCustomersServed,
      'gardenCustomerOrderIndex': _gardenCustomerOrderIndex,
      'gardenCustomerNextAtMs': _gardenCustomerNextAtMs,
      'gardenHeartPoints': _gardenHeartPoints,
      'gardenLawnLastMowedMs': _gardenLawnLastMowedMs,
      'gardenPondRefillMs': _gardenPondRefillMs,
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
      'gardenOrderClaimedDay': _gardenOrderClaimedDay,
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
            'carePoints': plot.carePoints,
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

  int get _gardenHeartLevel {
    if (_gardenHeartPoints >= 280) {
      return 5;
    }
    if (_gardenHeartPoints >= 150) {
      return 4;
    }
    if (_gardenHeartPoints >= 70) {
      return 3;
    }
    if (_gardenHeartPoints >= 25) {
      return 2;
    }
    return 1;
  }

  int get _gardenHeartLevelFloor => switch (_gardenHeartLevel) {
    1 => 0,
    2 => 25,
    3 => 70,
    4 => 150,
    _ => 280,
  };

  int get _gardenHeartNextLevelAt => switch (_gardenHeartLevel) {
    1 => 25,
    2 => 70,
    3 => 150,
    4 => 280,
    _ => 280,
  };

  double get _gardenHeartProgress {
    if (_gardenHeartLevel >= 5) {
      return 1;
    }
    final int floor = _gardenHeartLevelFloor;
    return ((_gardenHeartPoints - floor) / (_gardenHeartNextLevelAt - floor))
        .clamp(0.0, 1.0);
  }

  String get _gardenHeartTitle => switch (_gardenHeartLevel) {
    1 => 'Tender Seed',
    2 => 'Cozy Sprout',
    3 => 'Blooming Heart',
    4 => 'Giving Garden',
    _ => 'Radiant Heart',
  };

  String get _gardenHeartThought {
    final int day =
        _gardenNow.toUtc().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
    return const [
      'Small care, repeated gently, becomes a beautiful place.',
      'Your plants notice every visit, even the quiet ones.',
      'Nothing here needs rushing. Growing together is enough.',
      'A welcoming garden is made one kind action at a time.',
      'Today the garden feels a little more like home.',
    ][day % 5];
  }

  int _gardenPlantCareLevel(PlayerGardenPlot plot) {
    if (plot.carePoints >= 36) {
      return 5;
    }
    if (plot.carePoints >= 20) {
      return 4;
    }
    if (plot.carePoints >= 10) {
      return 3;
    }
    if (plot.carePoints >= 4) {
      return 2;
    }
    return 1;
  }

  int get _gardenBondedPlantCount => _playerGardenPlots
      .where(
        (plot) =>
            _isGardenPlotUnlocked(plot) &&
            plot.planted &&
            _gardenPlantCareLevel(plot) >= 2,
      )
      .length;

  int get _gardenHeartMarketBonus => (_gardenHeartLevel - 1) * 4;

  void _nurtureGardenHeart(
    int points, {
    PlayerGardenPlot? plot,
    int plantCare = 0,
  }) {
    final int previousLevel = _gardenHeartLevel;
    _gardenHeartPoints = max(0, _gardenHeartPoints + points);
    if (plot != null && plantCare > 0) {
      plot.carePoints = max(0, plot.carePoints + plantCare);
      plot.sparkle = 1;
    }
    _gardenHeartPulse = 1;
    if (_gardenHeartLevel > previousLevel) {
      _dailySummaryLines.add('Garden Heart grew into $_gardenHeartTitle');
    }
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
    _nurtureGardenHeart(3);
    if (_dailyGardenTasksComplete && !_gardenDailyRewardClaimed) {
      _gardenMessage = 'Daily care complete - a Heart Gift is ready';
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
      _nurtureGardenHeart(6);
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
      _nurtureGardenHeart(2);
      _gardenMessage = _gardenMood >= 82
          ? 'Journal bonus: +$pointReward pts, +1 sun'
          : 'Journal bonus: +$pointReward pts';
      _gardenMessageLife = 2.4;
      _playSfx(_sfxComboSpark, volume: 0.4);
    });
    _queueGardenSave();
  }

  int get _gardenFruitTotal => _gardenApples + _gardenLemons + _gardenOranges;

  int get _gardenProduceTotal => _gardenBouquets + _gardenFruitTotal;

  String _gardenProduceForOption(GardenPlantOption option) {
    return switch (option.name) {
      'Apple Tree' => 'Apple',
      'Lemon Tree' => 'Lemon',
      'Orange Tree' => 'Orange',
      _ => 'Bouquet',
    };
  }

  IconData _gardenProduceIcon(String produce) {
    return switch (produce) {
      'Apple' => Icons.apple_rounded,
      'Lemon' => Icons.circle_rounded,
      'Orange' => Icons.circle_rounded,
      _ => Icons.local_florist_rounded,
    };
  }

  Color _gardenProduceColor(String produce) {
    return switch (produce) {
      'Apple' => const Color(0xFFD94B3E),
      'Lemon' => const Color(0xFFF4CE3C),
      'Orange' => const Color(0xFFF28A31),
      _ => const Color(0xFFE978A6),
    };
  }

  String _gardenProduceLabel(String produce, int quantity) {
    final String lower = produce.toLowerCase();
    return '$quantity $lower${quantity == 1 ? '' : 's'}';
  }

  bool _gardenHasProduceSource(String produce) {
    if (_gardenFruitCount(produce) > 0) {
      return true;
    }
    return _playerGardenPlots.any(
      (plot) =>
          plot.planted &&
          _gardenProduceForOption(_plantOptionForPlot(plot)) == produce,
    );
  }

  GardenCustomerOrder get _gardenCustomerOrder {
    final List<String> producePool = [
      'Bouquet',
      if (_gardenHasProduceSource('Apple')) 'Apple',
      if (_gardenHasProduceSource('Lemon')) 'Lemon',
      if (_gardenHasProduceSource('Orange')) 'Orange',
    ];
    const List<String> customers = ['Maya', 'Theo', 'June', 'Ari', 'Nora'];
    final int index = _gardenCustomerOrderIndex;
    final String produce = producePool[index % producePool.length];
    final int quantity = produce == 'Bouquet'
        ? 1 + ((index ~/ producePool.length) % 2)
        : 1 + ((index + _gardenHouseTier) % 2);
    final int basePrice = switch (produce) {
      'Apple' => 22,
      'Lemon' => 30,
      'Orange' => 38,
      _ => 26,
    };
    return GardenCustomerOrder(
      customer: customers[index % customers.length],
      produce: produce,
      quantity: quantity,
      coinReward: quantity * basePrice * 2 + 18 + _gardenLevel * 5,
      pointReward: 24 + quantity * 12 + _gardenHouseTier * 8,
    );
  }

  bool get _gardenCustomerAvailable {
    final int? nextAt = _gardenCustomerNextAtMs;
    return nextAt == null || _gardenNow.millisecondsSinceEpoch >= nextAt;
  }

  Duration get _gardenCustomerWait {
    final int remaining = max(
      0,
      (_gardenCustomerNextAtMs ?? _gardenNow.millisecondsSinceEpoch) -
          _gardenNow.millisecondsSinceEpoch,
    );
    return Duration(milliseconds: remaining);
  }

  bool get _canServeGardenCustomer {
    final GardenCustomerOrder order = _gardenCustomerOrder;
    return _gardenCustomerAvailable &&
        _gardenFruitCount(order.produce) >= order.quantity;
  }

  void _focusGardenCustomerProduce() {
    final GardenCustomerOrder order = _gardenCustomerOrder;
    _gardenTool = GardenTool.harvest;
    final PlayerGardenPlot? ready = _playerGardenPlots
        .where(
          (plot) =>
              _isGardenPlotUnlocked(plot) &&
              plot.ready &&
              !plot.weed &&
              _gardenProduceForOption(_plantOptionForPlot(plot)) ==
                  order.produce,
        )
        .firstOrNull;
    if (ready != null) {
      ready.sparkle = 1;
      _guideGardenCaretakerToPlot(ready);
      _gardenMessage =
          '${order.customer} needs ${_gardenProduceLabel(order.produce, order.quantity)} - cut the glowing crop';
      _gardenMessageLife = 2.8;
      return;
    }

    final PlayerGardenPlot? growing = _playerGardenPlots
        .where(
          (plot) =>
              _isGardenPlotUnlocked(plot) &&
              plot.planted &&
              _gardenProduceForOption(_plantOptionForPlot(plot)) ==
                  order.produce,
        )
        .firstOrNull;
    if (growing != null) {
      _gardenMessage =
          '${order.customer} is waiting - ${_plantOptionForPlot(growing).name} is ready in ${_durationLabel(_remainingGardenTime(growing, _gardenNow))}';
      _gardenMessageLife = 2.8;
      return;
    }

    _gardenTool = GardenTool.plant;
    _gardenMessage = order.produce == 'Bouquet'
        ? 'Plant any flower to fill ${order.customer}\'s bouquet order'
        : 'Plant an ${order.produce} Tree for ${order.customer}\'s order';
    _gardenMessageLife = 2.8;
  }

  void _handleGardenCustomerAction() {
    setState(() {
      if (!_gardenCustomerAvailable) {
        _gardenMessage =
            'Next customer arrives in ${_durationLabel(_gardenCustomerWait)}';
        _gardenMessageLife = 2.0;
        return;
      }
      if (!_canServeGardenCustomer) {
        _focusGardenCustomerProduce();
        _playSfx(_sfxCrispLeaf, volume: 0.36);
        return;
      }

      final GardenCustomerOrder order = _gardenCustomerOrder;
      final int stock = _gardenFruitCount(order.produce);
      _setGardenFruitCount(order.produce, stock - order.quantity);
      _seeds += order.coinReward;
      _gardenPoints += order.pointReward;
      _score += order.pointReward;
      _gardenMarketSales += order.coinReward;
      _gardenCustomersServed += 1;
      _gardenCustomerOrderIndex += 1;
      _gardenCustomerNextAtMs = _gardenNow
          .add(const Duration(seconds: 20))
          .millisecondsSinceEpoch;
      _gardenCustomerCelebration = 1;
      _guideGardenCaretaker(const Offset(700, 748));
      _bumpGardenMood(4);
      _nurtureGardenHeart(2);
      _gardenMessage =
          '${order.customer} bought ${_gardenProduceLabel(order.produce, order.quantity)}: +${order.coinReward} coins';
      _gardenMessageLife = 3.0;
      _playSfx(_sfxComboSpark, volume: 0.62);
    });
    _queueGardenSave();
  }

  double get _gardenLawnGrowth {
    final int? lastMowedMs = _gardenLawnLastMowedMs;
    if (lastMowedMs == null) {
      return 0.82;
    }
    final int elapsedMs = max(
      0,
      _gardenNow.millisecondsSinceEpoch - lastMowedMs,
    );
    const int fullGrowthMs = 36 * 60 * 60 * 1000;
    return (0.08 + elapsedMs / fullGrowthMs).clamp(0.08, 1.0);
  }

  String get _featuredGardenFruit {
    final int dayIndex =
        _gardenNow.toUtc().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
    return const ['Apple', 'Lemon', 'Orange'][dayIndex % 3];
  }

  GardenMarketOrder get _dailyGardenOrder {
    final int dayIndex =
        _gardenNow.toUtc().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
    final String produce = const [
      'Apple',
      'Lemon',
      'Orange',
    ][(dayIndex + _gardenHouseTier) % 3];
    final int quantity = 3 + _gardenHouseTier + (dayIndex % 3);
    final int basePrice = switch (produce) {
      'Apple' => 22,
      'Lemon' => 30,
      _ => 38,
    };
    return GardenMarketOrder(
      produce: produce,
      quantity: quantity,
      coinReward: quantity * basePrice * 2 + _gardenLevel * 18,
      pointReward: 45 + _gardenLevel * 12 + _gardenHouseTier * 30,
    );
  }

  bool get _dailyGardenOrderClaimed =>
      _gardenOrderClaimedDay == _dayKey(_gardenNow);

  bool get _canFulfillDailyGardenOrder {
    final GardenMarketOrder order = _dailyGardenOrder;
    return !_dailyGardenOrderClaimed &&
        _gardenFruitCount(order.produce) >= order.quantity;
  }

  int _gardenFruitCount(String fruit) {
    return switch (fruit) {
      'Bouquet' => _gardenBouquets,
      'Apple' => _gardenApples,
      'Lemon' => _gardenLemons,
      'Orange' => _gardenOranges,
      _ => 0,
    };
  }

  void _setGardenFruitCount(String fruit, int count) {
    final int safeCount = max(0, count);
    switch (fruit) {
      case 'Bouquet':
        _gardenBouquets = safeCount;
      case 'Apple':
        _gardenApples = safeCount;
      case 'Lemon':
        _gardenLemons = safeCount;
      case 'Orange':
        _gardenOranges = safeCount;
    }
  }

  void _addGardenFruit(String fruit, int amount) {
    _setGardenFruitCount(fruit, _gardenFruitCount(fruit) + amount);
  }

  int _gardenFruitPrice(String fruit) {
    final int basePrice = switch (fruit) {
      'Bouquet' => 26,
      'Apple' => 22,
      'Lemon' => 30,
      'Orange' => 38,
      _ => 0,
    };
    final int featuredPrice = fruit == _featuredGardenFruit
        ? (basePrice * 1.5).round()
        : basePrice;
    return (featuredPrice * (100 + _gardenHeartMarketBonus) / 100).round();
  }

  void _fulfillDailyGardenOrder() {
    setState(() {
      final GardenMarketOrder order = _dailyGardenOrder;
      if (_dailyGardenOrderClaimed) {
        _gardenMessage = 'Today\'s garden order is already complete';
        _gardenMessageLife = 2.0;
        return;
      }
      final int available = _gardenFruitCount(order.produce);
      if (available < order.quantity) {
        _gardenMessage =
            'Order needs ${order.quantity} ${order.produce.toLowerCase()}s - ${order.quantity - available} more';
        _gardenMessageLife = 2.4;
        return;
      }
      _setGardenFruitCount(order.produce, available - order.quantity);
      _gardenOrderClaimedDay = _dayKey(_gardenNow);
      _seeds += order.coinReward;
      _gardenPoints += order.pointReward;
      _score += order.pointReward;
      _gardenMarketSales += order.coinReward;
      _gardenCompost = min(24, _gardenCompost + 1);
      _bumpGardenMood(8);
      _nurtureGardenHeart(5);
      _gardenMessage =
          'Order delivered: +${order.coinReward} coins, +${order.pointReward} pts';
      _gardenMessageLife = 3.0;
      _playSfx(_sfxComboSpark, volume: 0.62);
    });
    _queueGardenSave();
  }

  void _refreshGardenPond(DateTime now) {
    final int nowMs = now.millisecondsSinceEpoch;
    final int? refillMs = _gardenPondRefillMs;
    if (refillMs == null || _gardenPondWater >= 6) {
      _gardenPondRefillMs = nowMs;
      return;
    }
    const int refillStepMs = 3 * 60 * 60 * 1000;
    final int units = max(0, (nowMs - refillMs) ~/ refillStepMs);
    if (units <= 0) {
      return;
    }
    _gardenPondWater = min(6, _gardenPondWater + units);
    _gardenPondRefillMs = refillMs + units * refillStepMs;
  }

  String get _gardenPondStatus {
    if (_gardenPondWater >= 6) {
      return 'Reservoir full';
    }
    final int refillMs =
        _gardenPondRefillMs ?? _gardenNow.millisecondsSinceEpoch;
    const int refillStepMs = 3 * 60 * 60 * 1000;
    final int remainingMs = max(
      0,
      refillStepMs - (_gardenNow.millisecondsSinceEpoch - refillMs),
    );
    return 'Next drop ${_durationLabel(Duration(milliseconds: remainingMs))}';
  }

  void _mowGardenLawn() {
    setState(() {
      final double growth = _gardenLawnGrowth;
      if (growth < 0.28) {
        _gardenMessage =
            'Side lawn is still short - ${_gardenLawnStatusText()}';
        _gardenMessageLife = 2.1;
        return;
      }
      final int compostReward = max(1, (growth * 4).round());
      final int coinReward = 12 + (growth * 28).round();
      _gardenLawnLastMowedMs = _gardenNow.millisecondsSinceEpoch;
      _gardenCompost = min(24, _gardenCompost + compostReward);
      _seeds += coinReward;
      _completeDailyEcosystemTask(GardenEcosystemTask.tidy, moodBoost: 5);
      _gardenMessage =
          'Lawn mowed: +$compostReward compost, +$coinReward coins';
      _gardenMessageLife = 2.7;
      _playSfx(_sfxBambooBlade, volume: 0.54);
    });
    _queueGardenSave();
  }

  String _gardenLawnStatusText() {
    final int percent = (_gardenLawnGrowth * 100).round();
    return percent >= 28 ? 'Mow $percent%' : 'Regrowing $percent%';
  }

  void _collectGardenPondWater() {
    setState(() {
      _refreshGardenPond(_gardenNow);
      if (_gardenPondWater <= 0) {
        _gardenMessage = 'Pond reservoir empty - $_gardenPondStatus';
        _gardenMessageLife = 2.2;
        return;
      }
      final int collected = min(2, _gardenPondWater);
      _gardenPondWater -= collected;
      _waterCharges = min(12, _waterCharges + collected);
      _completeDailyEcosystemTask(GardenEcosystemTask.water, moodBoost: 3);
      _gardenMessage =
          'Pond irrigation: +$collected water ($_gardenPondWater/6 left)';
      _gardenMessageLife = 2.5;
      _playSfx(_sfxComboSpark, volume: 0.42);
    });
    _queueGardenSave();
  }

  void _openGardenMarket() {
    setState(() {
      _showGardenHousePanel = false;
      _showGardenHeartPanel = false;
      _showGardenMarketPanel = true;
      _gardenNurseryPlotId = null;
      _guideGardenCaretaker(const Offset(700, 748));
      _gardenMessageLife = 0;
    });
    _playSfx(_sfxCrispLeaf, volume: 0.4);
  }

  void _closeGardenMarket() {
    setState(() {
      _showGardenMarketPanel = false;
      _gardenMessage = _gardenProduceTotal > 0
          ? 'Produce saved in the stand basket'
          : 'Cut flowers or fruit to stock the garden stand';
      _gardenMessageLife = 2.0;
    });
  }

  void _sellGardenFruit(String fruit, {bool sellAll = false}) {
    setState(() {
      final int available = _gardenFruitCount(fruit);
      if (available <= 0) {
        _gardenMessage = 'No ${fruit.toLowerCase()}s in the pantry';
        _gardenMessageLife = 1.8;
        return;
      }
      final int quantity = sellAll ? available : 1;
      final int coins = quantity * _gardenFruitPrice(fruit);
      _setGardenFruitCount(fruit, available - quantity);
      _seeds += coins;
      _gardenMarketSales += coins;
      _gardenPoints += quantity * 4;
      _bumpGardenMood(min(4, quantity));
      _gardenMessage =
          'Sold $quantity ${fruit.toLowerCase()}${quantity == 1 ? '' : 's'} for $coins coins';
      _gardenMessageLife = 2.4;
      _playSfx(_sfxComboSpark, volume: 0.46);
    });
    _queueGardenSave();
  }

  void _openGardenHeart() {
    setState(() {
      _gardenNurseryPlotId = null;
      _showGardenHousePanel = false;
      _showGardenMarketPanel = false;
      _showGardenHeartPanel = true;
      _guideGardenCaretaker(const Offset(460, 850));
      _gardenMessageLife = 0;
      _gardenHeartPulse = 1;
    });
    _playSfx(_sfxComboSpark, volume: 0.42);
  }

  void _closeGardenHeart() {
    setState(() {
      _showGardenHeartPanel = false;
      _gardenMessage = _gardenHeartThought;
      _gardenMessageLife = 2.6;
    });
  }

  void _continueGardenCare() {
    setState(() {
      _showGardenHeartPanel = false;
      _gardenMessage = _gardenNextDailyAction() ?? _gardenHeartThought;
      _gardenMessageLife = 2.8;
      if (!_gardenDailyPlantDone) {
        _gardenTool = GardenTool.plant;
      } else if (!_gardenDailyWaterDone) {
        _gardenTool = GardenTool.water;
      } else if (!_gardenDailyCollectDone) {
        _gardenTool = GardenTool.harvest;
      } else if (!_gardenDailyTidyDone) {
        _gardenTool = GardenTool.build;
      }
    });
  }

  void _sellAllGardenFruit() {
    setState(() {
      final int total = _gardenProduceTotal;
      if (total <= 0) {
        _gardenMessage = 'The produce crates are empty';
        _gardenMessageLife = 1.8;
        return;
      }
      final int coins =
          _gardenBouquets * _gardenFruitPrice('Bouquet') +
          _gardenApples * _gardenFruitPrice('Apple') +
          _gardenLemons * _gardenFruitPrice('Lemon') +
          _gardenOranges * _gardenFruitPrice('Orange');
      _gardenBouquets = 0;
      _gardenApples = 0;
      _gardenLemons = 0;
      _gardenOranges = 0;
      _seeds += coins;
      _gardenMarketSales += coins;
      _gardenPoints += total * 4;
      _bumpGardenMood(min(8, total));
      _gardenMessage = 'Garden stand sold $total items for $coins coins';
      _gardenMessageLife = 2.8;
      _playSfx(_sfxComboSpark, volume: 0.58);
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
        _showGardenMarketPanel = false;
        _showGardenHeartPanel = false;
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
      _refreshGardenPond(now);
      _refreshAllGardenPlots(now);
      _phase = GamePhase.garden;
      _gardenTool = GardenTool.harvest;
      _gardenMovingPlotId = null;
      _gardenMessageLife = 0;
      _gardenSessionWeedSpawns = 0;
      _showGardenHousePanel = false;
      _showGardenMarketPanel = false;
      _showGardenHeartPanel = false;
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
      _showGardenMarketPanel = false;
      _showGardenHeartPanel = false;
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
        _showGardenMarketPanel = false;
        _showGardenHeartPanel = false;
        _gardenMovingPlotId = null;
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
    if (_isGardenPlotUnlocked(plot)) {
      return true;
    }
    if (plot.unlockLevel == _gardenLevel + 1 &&
        plot.unlockLevel <= _currentGardenHouse.maxGardenLevel) {
      return true;
    }
    return _gardenTool == GardenTool.build &&
        _gardenLevel >= _currentGardenHouse.maxGardenLevel &&
        plot.unlockLevel == _currentGardenHouse.maxGardenLevel + 1;
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

  int get _currentHouseFirstGardenLevel => _gardenHouseTier == 0
      ? 1
      : _gardenHouseTiers[_gardenHouseTier - 1].maxGardenLevel + 1;

  int get _currentHouseBackyardLevel =>
      (_gardenLevel - _currentHouseFirstGardenLevel + 1)
          .clamp(1, _currentHouseBackyardLevelCount)
          .toInt();

  int get _currentHouseBackyardLevelCount =>
      _currentGardenHouse.maxGardenLevel - _currentHouseFirstGardenLevel + 1;

  int get _maxGardenLevel => _currentGardenHouse.maxGardenLevel;

  int get _maxPlantUpgradeLevel => min(4, _gardenHouseTier + 2);

  int get _currentHousePlantCap => min(4, _gardenHouseTier + 2);

  Iterable<PlayerGardenPlot> get _currentHouseGardenPlots => _playerGardenPlots
      .where((plot) => plot.unlockLevel <= _currentGardenHouse.maxGardenLevel);

  PlayerGardenPlot? get _nextGardenExpansionPlot => _playerGardenPlots
      .where(
        (plot) =>
            plot.unlockLevel == _gardenLevel + 1 &&
            plot.unlockLevel <= _currentGardenHouse.maxGardenLevel,
      )
      .firstOrNull;

  int get _gardenBuildAttentionCount {
    int count = _gardenLawnGrowth >= 0.28 ? 1 : 0;
    if (_nextGardenExpansionPlot != null) {
      count += 1;
    }
    if (_currentHouseGardenPlots.any(
      (plot) => _isGardenPlotUnlocked(plot) && plot.weed,
    )) {
      count += 1;
    }
    return count;
  }

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
      return _gardenTool == GardenTool.harvest ? 'CUT WEED' : 'Weed';
    }
    if (_gardenTool == GardenTool.move) {
      if (_gardenMovingPlotId == plot.id) {
        return 'Selected';
      }
      if (_gardenMovingPlotId != null && !plot.planted) {
        return 'Move here';
      }
      if (plot.planted) {
        return 'Tap to move';
      }
    }
    if (!plot.planted) {
      return _gardenTool == GardenTool.plant ? 'Plant here' : 'Empty plot';
    }
    if (_gardenTool == GardenTool.build &&
        plot.upgradeLevel < _maxPlantUpgradeLevel) {
      return 'Upgrade Lv ${plot.upgradeLevel + 1}';
    }
    if (plot.ready) {
      final String produce = _gardenProduceForOption(_plantOptionForPlot(plot));
      return _gardenTool == GardenTool.harvest
          ? 'CUT ${produce.toUpperCase()}'
          : 'Ready to cut';
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
    _refreshGardenPond(now);
    if (_dailySummaryLines.isNotEmpty && !_showGardenWelcome) {
      _gardenMessage = _dailySummaryLines.first;
      _gardenMessageLife = 3.0;
      _dailySummaryLines = [];
    }
    _refreshAllGardenPlots(now);
    _stepGardenCaretaker(dt);
    _gardenMessageLife = max(0, _gardenMessageLife - dt);
    _gardenHeartPulse = max(0, _gardenHeartPulse - dt * 0.72);
    _gardenCustomerCelebration = max(0, _gardenCustomerCelebration - dt * 0.85);
    _gardenCutBurst = max(0, _gardenCutBurst - dt * 2.1);
    if (_gardenCutBurst <= 0) {
      _gardenCutPlotId = null;
    }
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
      if (tool != GardenTool.move) {
        _gardenMovingPlotId = null;
      }
      _gardenMessage = switch (tool) {
        GardenTool.harvest => 'Cut glowing crops and weeds for the stand',
        GardenTool.plant => 'Tap an empty plot to open nursery',
        GardenTool.move => 'Tap a plant, then tap its new empty bed',
        GardenTool.water => 'Tap growing plants to water',
        GardenTool.build => 'Build mode: choose an action or tap a plant',
        GardenTool.sun => 'Tap growing plants for sun boost',
      };
      _gardenMessageLife = 2.1;
    });
  }

  void _buildNextGardenLand() {
    setState(() {
      final PlayerGardenPlot? plot = _nextGardenExpansionPlot;
      if (plot == null) {
        _gardenMessage = _nextGardenHouse == null
            ? 'Every backyard zone is developed'
            : 'This backyard is complete - upgrade the house next';
        _gardenMessageLife = 2.2;
        return;
      }
      _gardenTool = GardenTool.build;
      _guideGardenCaretakerToPlot(plot);
      _tryExpandGarden(plot);
    });
    _queueGardenSave();
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
    _showGardenMarketPanel = false;
    _showGardenHeartPanel = false;
    _gardenNurseryPlotId = plot.id;
    _gardenMovingPlotId = null;
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
        if (_gardenTool == GardenTool.harvest ||
            _gardenTool == GardenTool.build) {
          _clearGardenWeed(plot);
        } else {
          _gardenMessage = 'Choose Cut to clear this weed';
          _gardenMessageLife = 2.1;
        }
        return;
      }
      if (_gardenTool == GardenTool.move) {
        _handleGardenMoveTap(plot);
        return;
      }
      if (plot.planted && _gardenTool == GardenTool.build) {
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
      if (_gardenTool == GardenTool.harvest) {
        final GardenPlantOption option = _plantOptionForPlot(plot);
        _gardenMessage =
            '${option.name} is ready in ${_durationLabel(_remainingGardenTime(plot, _gardenNow))}';
        _gardenMessageLife = 2.1;
        return;
      }
      if (_gardenTool == GardenTool.plant) {
        _gardenMessage = 'This bed is already planted';
        _gardenMessageLife = 1.8;
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

  PlayerGardenPlot? get _gardenMovingPlot {
    final int? id = _gardenMovingPlotId;
    if (id == null) {
      return null;
    }
    return _playerGardenPlots.where((plot) => plot.id == id).firstOrNull;
  }

  void _handleGardenMoveTap(PlayerGardenPlot target) {
    final PlayerGardenPlot? source = _gardenMovingPlot;
    if (source == null) {
      if (!target.planted) {
        _gardenMessage = 'Choose a plant to move first';
        _gardenMessageLife = 1.9;
        return;
      }
      _gardenMovingPlotId = target.id;
      target.sparkle = 1;
      _gardenMessage =
          '${_plantOptionForPlot(target).name} selected - tap an empty bed';
      _gardenMessageLife = 2.3;
      _playSfx(_sfxCrispLeaf, volume: 0.42);
      return;
    }

    if (source.id == target.id) {
      _gardenMovingPlotId = null;
      _gardenMessage = 'Move cancelled';
      _gardenMessageLife = 1.6;
      return;
    }
    if (target.planted) {
      _gardenMovingPlotId = target.id;
      target.sparkle = 1;
      _gardenMessage = '${_plantOptionForPlot(target).name} selected instead';
      _gardenMessageLife = 1.9;
      return;
    }

    target.asset = source.asset;
    target.plantIndex = source.plantIndex;
    target.plantedAt = source.plantedAt;
    target.readyAt = source.readyAt;
    target.lastWateredDay = source.lastWateredDay;
    target.growth = source.growth;
    target.watered = source.watered;
    target.grassCut = true;
    target.upgradeLevel = source.upgradeLevel;
    target.carePoints = source.carePoints;
    target.mature = source.mature;
    target.sparkle = 1;

    source.asset = null;
    source.plantIndex = null;
    source.plantedAt = null;
    source.readyAt = null;
    source.lastWateredDay = null;
    source.growth = 0;
    source.watered = false;
    source.upgradeLevel = 1;
    source.carePoints = 0;
    source.mature = false;
    source.sparkle = 0.5;

    final String plantName = _plantOptionForPlot(target).name;
    _gardenMovingPlotId = null;
    _gardenMessage = '$plantName moved to its new bed';
    _gardenMessageLife = 2.3;
    _playSfx(_sfxComboSpark, volume: 0.48);
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
      if (_gardenTool != GardenTool.build) {
        _gardenMessage = 'Use Build to clear this land first';
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
      _gardenMessage = 'Blossom Estate is fully developed';
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
    plot.carePoints = 0;
    plot.mature = false;
    plot.sparkle = 1;
    _nurtureGardenHeart(2, plot: plot, plantCare: 1);
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
    _nurtureGardenHeart(1, plot: plot, plantCare: 1);
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
    _nurtureGardenHeart(1, plot: plot, plantCare: 1);
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

    _gardenCutPlotId = plot.id;
    _gardenCutBurst = 1;
    plot.weed = false;
    plot.sparkle = 1;
    _seeds += 18;
    _gardenCompost = min(24, _gardenCompost + 1);
    _nurtureGardenHeart(
      1,
      plot: plot.planted ? plot : null,
      plantCare: plot.planted ? 1 : 0,
    );
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
    _nurtureGardenHeart(2, plot: plot, plantCare: 3);
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
    final String produce = _gardenProduceForOption(option);
    final int upgradeBonus = plot.upgradeLevel - 1;
    final int pointReward =
        option.points + ((plot.unlockLevel - 1) * 35) + (upgradeBonus * 60);
    final int seedReward =
        _gardenSeedRewardFor(option) +
        ((plot.unlockLevel - 1) * 10) +
        (upgradeBonus * 24);
    final String? fruit = produce == 'Bouquet' ? null : produce;
    final int fruitCount = fruit == null
        ? 0
        : 2 +
              plot.upgradeLevel +
              (_gardenMood >= 82 ? 1 : 0) +
              ((_gardenPlantCareLevel(plot) - 1) ~/ 2);
    final int bouquetCount = fruit == null
        ? 1 +
              plot.upgradeLevel +
              (_gardenMood >= 82 ? 1 : 0) +
              ((_gardenPlantCareLevel(plot) - 1) ~/ 2)
        : 0;
    final int coinReward = fruit == null
        ? seedReward
        : max(12, seedReward ~/ 4);
    _gardenPoints += pointReward;
    _score += pointReward;
    _seeds += coinReward;
    if (fruit != null) {
      _addGardenFruit(fruit, fruitCount);
    } else {
      _gardenBouquets += bouquetCount;
    }
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
    _gardenCutPlotId = plot.id;
    _gardenCutBurst = 1;
    _nurtureGardenHeart(2, plot: plot, plantCare: 2);
    final String harvestLabel = _gardenHarvestLabel(option);
    if (fruit != null) {
      _gardenMessage =
          'Cut $fruitCount ${fruit.toLowerCase()}s for the stand: +$pointReward pts, +$coinReward coins';
    } else if (_gardenOptionIsTree(option)) {
      _gardenMessage =
          'Collected $harvestLabel: +$pointReward pts, +$coinReward coins';
    } else {
      _gardenMessage =
          'Cut $bouquetCount bouquets for the stand: +$pointReward pts, +$coinReward coins';
    }
    _gardenMessageLife = 2.3;
    _completeDailyEcosystemTask(GardenEcosystemTask.collect, moodBoost: 5);
    _playSfx(_sfxBambooBlade, volume: 0.58);
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

  // ignore: unused_element
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
            if (_gardenMessageLife > 0)
              Positioned(
                left: 42,
                right: 42,
                top: 76,
                child: Opacity(
                  opacity: _gardenMessageLife.clamp(0.0, 1.0),
                  child: _GardenToast(message: _gardenMessage),
                ),
              ),
            if (_gardenTool == GardenTool.build)
              Positioned(
                left: 18,
                right: 18,
                bottom: 112,
                child: _buildGardenBuildTray(),
              ),
            if (_gardenTool != GardenTool.build)
              Positioned(
                left: 12,
                right: 12,
                bottom: 108,
                child: _buildGardenCustomerOrderBar(),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _buildGardenToolbar(),
            ),
            if (_gardenNurseryPlot != null) _buildGardenNurseryOverlay(),
            if (_showGardenHousePanel) _buildGardenHouseOverlay(),
            if (_showGardenMarketPanel) _buildGardenMarketOverlay(),
            if (_showGardenHeartPanel) _buildGardenHeartOverlay(),
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
                painter: _BuilderBackyardPainter(
                  world: world,
                  house: _currentGardenHouse,
                  plots: _playerGardenPlots,
                  gardenLevel: _gardenLevel,
                  mood: _gardenMood,
                  dailyComplete: _dailyGardenTasksComplete,
                  houseActive: _showGardenHousePanel,
                  lawnGrowth: _gardenLawnGrowth,
                  pondWater: _gardenPondWater,
                  marketReady: _gardenProduceTotal > 0,
                  heartLevel: _gardenHeartLevel,
                  heartPulse: _gardenHeartPulse,
                  tool: _gardenTool,
                  movingPlotId: _gardenMovingPlotId,
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
              for (final plot in _playerGardenPlots.where(_isGardenPlotVisible))
                _buildGardenPlot(plot),
              _buildGardenPondTarget(),
              _buildGardenHouseTarget(),
              _buildGardenHeartTarget(),
              _buildGardenLawnTarget(),
              if (_gardenTool == GardenTool.build)
                _buildGardenStation(
                  key: const ValueKey('garden-station-journal'),
                  position: const Offset(350, 524),
                  icon: Icons.menu_book_rounded,
                  title: 'Garden journal',
                  status: _gardenHabitatDay == _dayKey(_gardenNow)
                      ? 'Checked in'
                      : 'Daily bonus',
                  color: const Color(0xFF78A544),
                  ready: _gardenHabitatDay != _dayKey(_gardenNow),
                  onTap: () {
                    _guideGardenCaretaker(const Offset(348, 590));
                    _visitGardenJournal();
                  },
                ),
              _buildGardenStation(
                key: const ValueKey('garden-station-water'),
                position: const Offset(438, 526),
                icon: Icons.water_drop_rounded,
                title: 'Rain barrel',
                status: _gardenWaterBarrelDay == _dayKey(_gardenNow)
                    ? 'Refills tomorrow'
                    : '+1 water',
                color: const Color(0xFF328EC1),
                ready: _gardenWaterBarrelDay != _dayKey(_gardenNow),
                onTap: () {
                  _guideGardenCaretaker(const Offset(565, 592));
                  _collectGardenWaterBarrel();
                },
              ),
              if (_gardenTool == GardenTool.build)
                _buildGardenStation(
                  key: const ValueKey('garden-station-compost'),
                  position: const Offset(342, 1050),
                  icon: Icons.recycling_rounded,
                  title: 'Compost mixer',
                  status: _gardenCompost > 0
                      ? 'Mix x$_gardenCompost'
                      : 'Clear to fill',
                  color: const Color(0xFF9A6B35),
                  ready: _gardenCompost > 0,
                  onTap: () {
                    _guideGardenCaretaker(const Offset(342, 1058));
                    _collectGardenCompost();
                  },
                ),
              _buildGardenStation(
                key: const ValueKey('garden-produce-market'),
                position: const Offset(800, 784),
                icon: Icons.storefront_rounded,
                title: 'Garden stand',
                status: _gardenCustomerAvailable
                    ? '${_gardenCustomerOrder.customer} is waiting'
                    : 'Next customer soon',
                color: const Color(0xFFC47731),
                ready: _gardenCustomerAvailable,
                onTap: _openGardenMarket,
              ),
              _buildGardenCustomerScene(),
              if (_gardenGiftPlot != null) _buildGardenGift(_gardenGiftPlot!),
              _buildGardenCaretaker(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGardenCustomerOrderBar() {
    final GardenCustomerOrder order = _gardenCustomerOrder;
    final int stock = _gardenFruitCount(order.produce);
    final bool available = _gardenCustomerAvailable;
    final bool canServe = _canServeGardenCustomer;
    final bool celebrating = _gardenCustomerCelebration > 0;
    final Color produceColor = _gardenProduceColor(order.produce);
    final String actionLabel = available
        ? canServe
              ? 'SERVE'
              : 'FIND'
        : _durationLabel(_gardenCustomerWait);
    final String customerAsset =
        _avatarAssets[(_selectedAvatar + 1 + _gardenCustomerOrderIndex) %
            _avatarAssets.length];

    return GestureDetector(
      key: const ValueKey('garden-customer-order-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: _handleGardenCustomerAction,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 72,
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: celebrating
                ? const [Color(0xFFF0B63E), Color(0xFFB86B24)]
                : const [Color(0xFFF8E8BD), Color(0xFFE7C782)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: canServe ? const Color(0xFFFFE67A) : const Color(0xFF7A5528),
            width: canServe ? 3 : 2,
          ),
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
            Container(
              width: 51,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFB8D97A),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFF5D7D38), width: 2),
              ),
              child: Transform.translate(
                offset: const Offset(0, 7),
                child: Image.asset(
                  customerAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    celebrating
                        ? 'SOLD - CUSTOMER HAPPY'
                        : available
                        ? '${order.customer.toUpperCase()} WANTS'
                        : 'NEXT: ${order.customer.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4C3218),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _gardenProduceIcon(order.produce),
                        color: produceColor,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${order.quantity} ${order.produce.toUpperCase()}  BASKET $stock/${order.quantity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2E5726),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: order.quantity <= 0
                                ? 0
                                : (stock / order.quantity).clamp(0, 1),
                            backgroundColor: const Color(0xFFC5B17D),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              canServe ? const Color(0xFF4D9B3B) : produceColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+${order.coinReward}',
                        style: const TextStyle(
                          color: Color(0xFF8A5816),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Container(
              key: const ValueKey('garden-customer-order-action'),
              width: 63,
              height: 49,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: canServe
                    ? const Color(0xFF3F8F3D)
                    : available
                    ? const Color(0xFF315F42)
                    : const Color(0xFF766D54),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFFFEDAA), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    canServe
                        ? Icons.handshake_rounded
                        : available
                        ? Icons.content_cut_rounded
                        : Icons.schedule_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                  Text(
                    actionLabel,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
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

  Widget _buildGardenCustomerScene() {
    final GardenCustomerOrder order = _gardenCustomerOrder;
    final bool available = _gardenCustomerAvailable;
    final bool canServe = _canServeGardenCustomer;
    final double bob = sin(_motionTime * 2.2 + _gardenCustomerOrderIndex) * 4;
    final double celebrate = _gardenCustomerCelebration.clamp(0.0, 1.0);
    final String customerAsset =
        _avatarAssets[(_selectedAvatar + 1 + _gardenCustomerOrderIndex) %
            _avatarAssets.length];

    return Positioned(
      left: 728,
      top: 486,
      width: 182,
      height: 238,
      child: GestureDetector(
        key: const ValueKey('garden-customer-scene'),
        behavior: HitTestBehavior.opaque,
        onTap: _handleGardenCustomerAction,
        child: Opacity(
          opacity: available ? 1 : 0.62,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 9,
                right: 9,
                child: Transform.translate(
                  offset: Offset(0, bob * 0.35),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF8E8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: canServe
                            ? const Color(0xFFFFD858)
                            : const Color(0xFF6D5131),
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 7,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          available
                              ? _gardenProduceIcon(order.produce)
                              : Icons.schedule_rounded,
                          color: available
                              ? _gardenProduceColor(order.produce)
                              : const Color(0xFF766D54),
                          size: 28,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          available ? 'x${order.quantity}' : 'SOON',
                          style: const TextStyle(
                            color: Color(0xFF38532D),
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 53 + bob,
                child: Transform.rotate(
                  angle: sin(_motionTime * 1.5) * 0.02,
                  child: Image.asset(
                    customerAsset,
                    width: 104,
                    height: 142,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              if (celebrate > 0)
                ...List<Widget>.generate(7, (index) {
                  final double angle = index * pi * 2 / 7;
                  return Positioned(
                    left: 82 + cos(angle) * 68 * celebrate,
                    top: 105 + sin(angle) * 74 * celebrate,
                    child: Opacity(
                      opacity: celebrate,
                      child: const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD849),
                        size: 21,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGardenHouseTarget() {
    final double pulse = (sin(_motionTime * 2.2) + 1) / 2;
    final GardenHouseTier? next = _nextGardenHouse;
    final bool upgradeReady =
        next != null &&
        _gardenHouseUpgradeBlocker(_currentGardenHouse, next) == null;
    return Positioned(
      left: 0,
      top: 72,
      width: 490,
      height: 510,
      child: GestureDetector(
        key: const ValueKey('garden-house-scene'),
        behavior: HitTestBehavior.translucent,
        onTap: _openGardenHousePanel,
        child: Align(
          alignment: const Alignment(0.72, 0.76),
          child: upgradeReady
              ? Transform.scale(
                  scale: 1 + pulse * 0.06,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E8C5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFD85B),
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x77FFD95C),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Color(0xFF56872C),
                      size: 30,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildGardenHeartTarget() {
    final double pulse = (sin(_motionTime * 2.7) + 1) / 2;
    final bool giftReady =
        _dailyGardenTasksComplete && !_gardenDailyRewardClaimed;
    return Positioned(
      left: 404,
      top: 516,
      width: 112,
      height: 132,
      child: IgnorePointer(
        ignoring: !giftReady,
        child: GestureDetector(
          key: const ValueKey('garden-heart-scene'),
          behavior: HitTestBehavior.translucent,
          onTap: _openGardenHeart,
          child: giftReady
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Transform.scale(
                    scale: 1 + pulse * 0.08,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xEEF0A51A),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFF1A0),
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88FFD95C),
                            blurRadius: 14,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildGardenPondTarget() {
    final double pulse = (sin(_motionTime * 2.1) + 1) / 2;
    final bool ready = _gardenPondWater > 0;
    return Positioned(
      left: 42,
      top: 598,
      width: 300,
      height: 166,
      child: GestureDetector(
        key: const ValueKey('garden-pond-reservoir'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _guideGardenCaretaker(const Offset(252, 704));
          _collectGardenPondWater();
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Transform.scale(
            scale: ready ? 1 + pulse * 0.025 : 1,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: const Color(0xE8174D5E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ready
                      ? Color.lerp(
                          const Color(0xFF86DEFF),
                          const Color(0xFFE9FCFF),
                          pulse,
                        )!
                      : const Color(0xFF79969A),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 7,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFFBCEFFF),
                    size: 21,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      ready
                          ? 'Collect water  $_gardenPondWater/6'
                          : _gardenPondStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
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

  Widget _buildGardenLawnTarget() {
    final bool ready = _gardenLawnGrowth >= 0.28;
    final bool buildMode = _gardenTool == GardenTool.build;
    final double pulse = (sin(_motionTime * 3.1) + 1) / 2;
    return Positioned(
      left: 54,
      top: 986,
      width: 224,
      height: 164,
      child: GestureDetector(
        key: const ValueKey('garden-lawn-mower'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _guideGardenCaretaker(const Offset(166, 1072));
          _mowGardenLawn();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: buildMode
                  ? const Color(
                      0xFFFFE66D,
                    ).withValues(alpha: 0.62 + pulse * 0.3)
                  : Colors.transparent,
              width: buildMode ? 5 : 0,
            ),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: ready ? 1 + pulse * 0.035 : 1,
              child: Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: ready
                      ? const Color(0xEE4B7D26)
                      : const Color(0xD92D4B2C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: ready
                        ? const Color(0xFFFFE579)
                        : const Color(0xFF9DC889),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 7,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ready ? Icons.content_cut_rounded : Icons.grass_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      ready ? 'MOW LAWN' : _gardenLawnStatusText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
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
      left: position.dx - 56,
      top: position.dy - 62,
      width: 112,
      height: 104,
      child: Tooltip(
        message: '$title: $status',
        child: Semantics(
          button: true,
          label: '$title, $status',
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Align(
              alignment: Alignment.topRight,
              child: Transform.scale(
                scale: ready ? 1 + pulse * 0.05 : 1,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      color,
                      const Color(0xFF1A3520),
                      ready ? 0.06 : 0.32,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ready
                          ? Color.lerp(
                              const Color(0xFFFFD85D),
                              const Color(0xFFFFFFB1),
                              pulse,
                            )!
                          : const Color(0xFFB5D98B),
                      width: ready ? 2.5 : 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 7,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
              ),
            ),
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
    final int careLevel = plot.planted ? _gardenPlantCareLevel(plot) : 1;
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
    final bool moveTarget =
        unlocked &&
        !plot.weed &&
        !plot.planted &&
        _gardenTool == GardenTool.move &&
        _gardenMovingPlotId != null;
    final bool moveSelected = _gardenMovingPlotId == plot.id;
    final bool harvestTarget =
        unlocked &&
        _gardenTool == GardenTool.harvest &&
        (plot.ready || plot.weed);
    final bool activeTarget =
        plantTarget || moveTarget || moveSelected || harvestTarget;
    final bool cutBurst = _gardenCutPlotId == plot.id && _gardenCutBurst > 0;
    final bool showStatusBadge =
        unlocked && !plantTarget && (plot.weed || plot.planted || moveTarget);
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
              if (harvestTarget)
                Positioned(
                  bottom: 27,
                  child: Transform.scale(
                    scale: 1 + targetPulse * 0.1,
                    child: Container(
                      width: tree ? 126 : 104,
                      height: tree ? 52 : 44,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFF07B),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFFDF58,
                            ).withValues(alpha: 0.36 + targetPulse * 0.35),
                            blurRadius: 18 + targetPulse * 10,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (activeTarget)
                Positioned.fill(
                  child: IgnorePointer(
                    child: SizedBox.expand(
                      key: ValueKey('garden-plant-target-glow-${plot.id}'),
                    ),
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
              ] else if (plantTarget || moveTarget)
                Positioned(
                  right: 42,
                  bottom: 35,
                  child: Transform.scale(
                    scale: 1 + targetPulse * 0.08,
                    child: moveTarget
                        ? const Icon(
                            Icons.open_with_rounded,
                            color: Colors.white,
                            size: 36,
                          )
                        : const _GardenPlantTargetMarker(),
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
                    child: Transform.translate(
                      offset: Offset(plantSway * 90, 0),
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
              if (harvestTarget)
                Positioned(
                  right: 25,
                  top: 30,
                  child: Transform.scale(
                    scale: 1 + targetPulse * 0.14,
                    child: Container(
                      width: 39,
                      height: 39,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7C842),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88FFD83D),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.content_cut_rounded,
                        color: Color(0xFF31552C),
                        size: 23,
                      ),
                    ),
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
              if (unlocked && plot.planted && careLevel > 1)
                Positioned(
                  right: 27,
                  top: 82,
                  child: Tooltip(
                    message: 'Plant bond level $careLevel',
                    child: Container(
                      key: ValueKey('garden-plant-care-${plot.id}'),
                      height: 25,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xEE7A3F60),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFFFFC5D9)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFF91B2),
                            size: 14,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$careLevel',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
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
              if (cutBurst)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: _gardenCutBurst.clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: -0.42,
                        child: Transform.scale(
                          scale: 0.82 + (1 - _gardenCutBurst) * 0.34,
                          child: Image.asset(
                            'assets/images/fx/slash_arc.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
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

  Widget _buildGardenHeartOverlay() {
    final bool giftReady =
        _dailyGardenTasksComplete && !_gardenDailyRewardClaimed;

    Widget careStep({
      required IconData icon,
      required String label,
      required bool done,
      required Color color,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: done ? color : const Color(0xFFE4EED9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: done
                      ? const Color(0xFFFFE986)
                      : const Color(0xFF9AAF87),
                  width: 2,
                ),
              ),
              child: Icon(
                done ? Icons.check_rounded : icon,
                color: done ? Colors.white : const Color(0xFF5B7350),
                size: 23,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: done ? const Color(0xFF3A6B30) : const Color(0xFF738269),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    Widget heartStat(IconData icon, String value, String label, Color color) {
      return Expanded(
        child: Column(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF2E5C2B),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF68805D),
                fontSize: 9,
                fontWeight: FontWeight.w800,
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
              onTap: _closeGardenHeart,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.52)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 124,
            bottom: 94,
            child: Container(
              key: const ValueKey('garden-heart-panel'),
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FFEA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFC9DE), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xAA000000),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4E9C43),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFE986),
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x449ACE55),
                                  blurRadius: 12,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFF8EAC),
                            size: 36,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 1,
                            child: Container(
                              width: 23,
                              height: 23,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFD75A),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$_gardenHeartLevel',
                                style: const TextStyle(
                                  color: Color(0xFF5D3C16),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Garden Heart',
                              style: TextStyle(
                                color: Color(0xFF285320),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Lv $_gardenHeartLevel  $_gardenHeartTitle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9A4E70),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RoundIconButton(
                        icon: Icons.close_rounded,
                        onPressed: _closeGardenHeart,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            minHeight: 12,
                            value: _gardenHeartProgress,
                            backgroundColor: const Color(0xFFDCE8CF),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFFF7FA6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _gardenHeartLevel >= 5
                            ? 'MAX'
                            : '$_gardenHeartPoints/$_gardenHeartNextLevelAt',
                        style: const TextStyle(
                          color: Color(0xFF4B6E39),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F6),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFF2B5CA)),
                    ),
                    child: Text(
                      _gardenHeartThought,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      style: const TextStyle(
                        color: Color(0xFF75445A),
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "TODAY'S CARE",
                      style: TextStyle(
                        color: Color(0xFF3B692F),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      careStep(
                        icon: Icons.spa_rounded,
                        label: 'Plant',
                        done: _gardenDailyPlantDone,
                        color: const Color(0xFF70AB3D),
                      ),
                      careStep(
                        icon: Icons.water_drop_rounded,
                        label: 'Water',
                        done: _gardenDailyWaterDone,
                        color: const Color(0xFF3B9CCC),
                      ),
                      careStep(
                        icon: Icons.local_florist_rounded,
                        label: 'Gather',
                        done: _gardenDailyCollectDone,
                        color: const Color(0xFFE483A8),
                      ),
                      careStep(
                        icon: Icons.content_cut_rounded,
                        label: 'Tidy',
                        done: _gardenDailyTidyDone,
                        color: const Color(0xFFA8753D),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4DE),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        heartStat(
                          Icons.favorite_rounded,
                          '$_gardenBondedPlantCount',
                          'plant bonds',
                          const Color(0xFFE46D94),
                        ),
                        heartStat(
                          Icons.sell_rounded,
                          '+$_gardenHeartMarketBonus%',
                          'market value',
                          const Color(0xFFC7832C),
                        ),
                        heartStat(
                          Icons.local_fire_department_rounded,
                          '$_gardenLoginStreak',
                          'day care streak',
                          const Color(0xFFE89A2D),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5CC),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFE6C75B)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD95F),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _gardenHeartLevel >= 5
                                ? Icons.auto_awesome_rounded
                                : Icons.park_rounded,
                            color: const Color(0xFF6B5720),
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _gardenHeartLevel >= 5
                                    ? 'RADIANT GARDEN'
                                    : 'NEXT BLOOM AT $_gardenHeartNextLevelAt CARE',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF66531E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                _gardenHeartLevel >= 5
                                    ? 'Every plant now shares the Heart at its brightest.'
                                    : 'A fuller canopy and +${_gardenHeartMarketBonus + 4}% produce value.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF7C6A36),
                                  fontSize: 10,
                                  height: 1.18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _PrimaryButton(
                      key: const ValueKey('garden-heart-action'),
                      label: giftReady
                          ? 'OPEN HEART GIFT'
                          : _gardenDailyRewardClaimed
                          ? 'COME BACK TOMORROW'
                          : 'CONTINUE CARE $_dailyGardenTaskCount/4',
                      icon: giftReady
                          ? Icons.redeem_rounded
                          : _gardenDailyRewardClaimed
                          ? Icons.favorite_rounded
                          : Icons.spa_rounded,
                      onPressed: giftReady
                          ? _claimDailyEcosystemReward
                          : _continueGardenCare,
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
                  _GardenWorldSelector(
                    world: _currentGardenWorld,
                    index: _selectedGardenWorld,
                    total: _gardenWorlds.length,
                    unlockedCount: _unlockedGardenWorldCount,
                    onPrevious: () => _selectGardenWorld(-1),
                    onNext: () => _selectGardenWorld(1),
                  ),
                  const SizedBox(height: 8),
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
                    height: 44,
                    child: OutlinedButton.icon(
                      key: const ValueKey('garden-house-open-market'),
                      onPressed: _openGardenMarket,
                      icon: const Icon(Icons.storefront_rounded, size: 22),
                      label: Text(
                        _gardenProduceTotal > 0
                            ? 'GARDEN STAND - $_gardenProduceTotal ITEMS'
                            : 'OPEN GARDEN STAND',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF396B2E),
                        side: const BorderSide(
                          color: Color(0xFFC99A2B),
                          width: 2,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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

  Widget _buildGardenMarketOverlay() {
    const Map<String, String> fruitAssets = {
      'Bouquet': 'assets/images/sprites/pink_blossom_bush.png',
      'Apple': 'assets/images/sprites/tree_apple.png',
      'Lemon': 'assets/images/sprites/tree_lemon.png',
      'Orange': 'assets/images/sprites/tree_orange.png',
    };
    final GardenMarketOrder order = _dailyGardenOrder;
    final int orderStock = _gardenFruitCount(order.produce);

    Widget fruitRow(String fruit) {
      final int count = _gardenFruitCount(fruit);
      final int price = _gardenFruitPrice(fruit);
      final bool featured = fruit == _featuredGardenFruit;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: featured ? const Color(0xFFFFF4C4) : const Color(0xFFEAF4D8),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: featured ? const Color(0xFFE5A92B) : const Color(0xFF94B965),
            width: featured ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                fruitAssets[fruit]!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$fruit  x$count',
                    style: const TextStyle(
                      color: Color(0xFF285320),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    featured
                        ? '$price coins - daily premium'
                        : '$price coins each',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: featured
                          ? const Color(0xFFA4630C)
                          : const Color(0xFF58753D),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              key: ValueKey('garden-market-sell-$fruit'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _sellGardenFruit(fruit),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: count > 0 ? 1 : 0.42,
                child: Container(
                  width: 76,
                  height: 48,
                  decoration: BoxDecoration(
                    color: count > 0
                        ? const Color(0xFF4C9C3D)
                        : const Color(0xFF78906E),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xFFDDF39A),
                      width: 2,
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sell_rounded, color: Colors.white, size: 21),
                      Text(
                        'SELL 1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
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

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeGardenMarket,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.54)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 126,
            bottom: 96,
            child: Container(
              key: const ValueKey('garden-market-panel'),
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FFE9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD55D), width: 3),
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
                          color: const Color(0xFFC47731),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFF6C431D),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 29,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Backyard Garden Stand',
                              style: TextStyle(
                                color: Color(0xFF285320),
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Basket $_gardenProduceTotal - served $_gardenCustomersServed customers',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                        onPressed: _closeGardenMarket,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('garden-daily-order'),
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: _dailyGardenOrderClaimed
                          ? const Color(0xFFE5F1D4)
                          : const Color(0xFFFFE9AF),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: _dailyGardenOrderClaimed
                            ? const Color(0xFF78A858)
                            : const Color(0xFFD79625),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC47731),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _dailyGardenOrderClaimed
                                ? Icons.check_rounded
                                : Icons.local_shipping_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _dailyGardenOrderClaimed
                                    ? 'DAILY ORDER DELIVERED'
                                    : '${order.quantity} ${order.produce.toUpperCase()} ORDER',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF66420F),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                _dailyGardenOrderClaimed
                                    ? 'A new order arrives tomorrow'
                                    : '$orderStock/${order.quantity} stocked  +${order.coinReward} coins  +${order.pointReward} pts',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF715A32),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 7),
                        GestureDetector(
                          key: const ValueKey('garden-market-order-action'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _dailyGardenOrderClaimed
                              ? null
                              : _fulfillDailyGardenOrder,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 68,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _canFulfillDailyGardenOrder
                                  ? const Color(0xFF4C9C3D)
                                  : const Color(0xFF849273),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: const Color(0xFFDDF39A),
                              ),
                            ),
                            child: Text(
                              _dailyGardenOrderClaimed ? 'DONE' : 'DELIVER',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0B5),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFE0A62C)),
                    ),
                    child: Text(
                      'TODAY: ${_featuredGardenFruit.toUpperCase()} PAYS 50% MORE',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF86510E),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        fruitRow('Bouquet'),
                        fruitRow('Apple'),
                        fruitRow('Lemon'),
                        fruitRow('Orange'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: _PrimaryButton(
                      key: const ValueKey('garden-market-sell-all'),
                      label: _gardenProduceTotal > 0
                          ? 'SELL ALL $_gardenProduceTotal ITEMS'
                          : 'PANTRY EMPTY',
                      icon: Icons.savings_rounded,
                      onPressed: _sellAllGardenFruit,
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

  // ignore: unused_element
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
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xF21D4A28), Color(0xF25E304B)],
        ),
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
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _gardenHeartTitle,
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
                      value: _gardenHeartProgress,
                      backgroundColor: const Color(0xFF0D2814),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFFF83AA),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _gardenHeartLevel >= 5
                      ? 'Lv 5  radiant'
                      : '$_gardenHeartPoints/$_gardenHeartNextLevelAt care',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      left: 8,
      right: 8,
      top: 8,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              flex: 16,
              child: GestureDetector(
                key: const ValueKey('garden-house-upgrade'),
                behavior: HitTestBehavior.opaque,
                onTap: _openGardenHousePanel,
                child: _GardenCompactProgressBoard(
                  level: _gardenLevel,
                  streak: _gardenLoginStreak,
                  progress:
                      _currentHouseBackyardLevel /
                      _currentHouseBackyardLevelCount,
                  subtitle:
                      'House ${_gardenHouseTier + 1}/${_gardenHouseTiers.length}',
                  dailyReady:
                      _dailyGardenTasksComplete && !_gardenDailyRewardClaimed,
                  tendedToday: _gardenLastTendedDay == _dayKey(_gardenNow),
                  onDailyTap: _openGardenHeart,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 10,
              child: _GardenStatChip(
                asset: 'assets/images/icons/seed_coin.png',
                value: _formatNumber(_seeds),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 8,
              child: GestureDetector(
                key: const ValueKey('garden-resource-water'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectGardenTool(GardenTool.water),
                child: _GardenStatChip(
                  asset: 'assets/images/icons/water_drop.png',
                  value: '$_waterCharges',
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 8,
              child: _GardenStatChip(
                icon: Icons.eco_rounded,
                value: _gardenPoints >= 1000
                    ? '${(_gardenPoints / 1000).toStringAsFixed(1)}k'
                    : '$_gardenPoints',
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openUpgrades,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EED4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF9B8354), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: Color(0xFF354237),
                  size: 25,
                ),
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
            key: const ValueKey('garden-tool-harvest'),
            icon: Icons.content_cut_rounded,
            label: 'Cut',
            selected: _gardenTool == GardenTool.harvest,
            onTap: () => _selectGardenTool(GardenTool.harvest),
          ),
        ),
        const SizedBox(width: 10),
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
            key: const ValueKey('garden-tool-build'),
            icon: Icons.handyman_rounded,
            label: 'Build',
            selected: _gardenTool == GardenTool.build,
            badge: _gardenBuildAttentionCount,
            onTap: () => _selectGardenTool(GardenTool.build),
          ),
        ),
      ],
    );
  }

  Widget _buildGardenBuildTray() {
    Widget action({
      required Key key,
      required IconData icon,
      required String label,
      required bool ready,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: ready ? const Color(0xFFFFF0C8) : const Color(0xFFE2DBC6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ready
                    ? const Color(0xFFD59A35)
                    : const Color(0xFF918B78),
                width: 1.8,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: ready
                      ? const Color(0xFF6A4A24)
                      : const Color(0xFF777265),
                  size: 20,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: ready
                            ? const Color(0xFF4D351C)
                            : const Color(0xFF777265),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
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

    final PlayerGardenPlot? nextLand = _nextGardenExpansionPlot;
    final String landLabel = nextLand == null
        ? 'Land done'
        : nextLand.grassCut
        ? 'Expand'
        : 'Clear land';
    return Container(
      key: const ValueKey('garden-build-tray'),
      height: 58,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xF5F8EED4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF9F7440), width: 2),
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
          action(
            key: const ValueKey('garden-tool-move'),
            icon: Icons.open_with_rounded,
            label: 'Move',
            ready: true,
            onTap: () => _selectGardenTool(GardenTool.move),
          ),
          const SizedBox(width: 5),
          action(
            key: const ValueKey('garden-build-mow'),
            icon: Icons.content_cut_rounded,
            label: _gardenLawnGrowth >= 0.28 ? 'Mow lawn' : 'Regrowing',
            ready: _gardenLawnGrowth >= 0.28,
            onTap: _mowGardenLawn,
          ),
          const SizedBox(width: 5),
          action(
            key: const ValueKey('garden-build-land'),
            icon: Icons.grid_view_rounded,
            label: landLabel,
            ready: nextLand != null,
            onTap: _buildNextGardenLand,
          ),
          const SizedBox(width: 5),
          action(
            key: const ValueKey('garden-build-home'),
            icon: Icons.home_work_rounded,
            label: 'House',
            ready: true,
            onTap: _openGardenHousePanel,
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

// ignore: unused_element
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

class _GardenCompactProgressBoard extends StatelessWidget {
  const _GardenCompactProgressBoard({
    required this.level,
    required this.streak,
    required this.progress,
    required this.subtitle,
    required this.dailyReady,
    required this.tendedToday,
    required this.onDailyTap,
  });

  final int level;
  final int streak;
  final double progress;
  final String subtitle;
  final bool dailyReady;
  final bool tendedToday;
  final VoidCallback onDailyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF527C35), Color(0xFF294D2C)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9CCA1), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            key: const ValueKey('garden-streak-chip'),
            behavior: HitTestBehavior.opaque,
            onTap: onDailyTap,
            child: SizedBox(
              width: 43,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFF8CCF4E),
                    size: 42,
                    shadows: [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 3,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  Text(
                    '$level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Color(0xAA27411D),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (dailyReady)
                    Positioned(
                      right: 1,
                      top: 1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74A3B),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  if (tendedToday)
                    const Positioned(
                      right: 0,
                      bottom: 1,
                      child: Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('garden-tended-star'),
                        color: Color(0xFFDFFF83),
                        size: 13,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(1, 4, 7, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'MY GARDEN',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: progress.clamp(0, 1),
                      backgroundColor: const Color(0xFF1A3420),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFC94A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$subtitle  Day $streak',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE7F5C7),
                      fontSize: 7.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
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

class _BuilderBackyardPainter extends CustomPainter {
  const _BuilderBackyardPainter({
    required this.world,
    required this.house,
    required this.plots,
    required this.gardenLevel,
    required this.mood,
    required this.dailyComplete,
    required this.houseActive,
    required this.lawnGrowth,
    required this.pondWater,
    required this.marketReady,
    required this.heartLevel,
    required this.heartPulse,
    required this.tool,
    required this.movingPlotId,
    required this.time,
  });

  final GardenWorld world;
  final GardenHouseTier house;
  final List<PlayerGardenPlot> plots;
  final int gardenLevel;
  final int mood;
  final bool dailyComplete;
  final bool houseActive;
  final double lawnGrowth;
  final int pondWater;
  final bool marketReady;
  final int heartLevel;
  final double heartPulse;
  final GardenTool tool;
  final int? movingPlotId;
  final double time;

  bool get _night => world.ambient == GardenAmbient.fireflies;
  bool get _winter => world.ambient == GardenAmbient.snow;
  bool get _bamboo => world.ambient == GardenAmbient.bambooLeaves;

  int get _tier {
    if (house.maxGardenLevel <= 3) {
      return 0;
    }
    if (house.maxGardenLevel <= 6) {
      return 1;
    }
    if (house.maxGardenLevel <= 9) {
      return 2;
    }
    if (house.maxGardenLevel <= 12) {
      return 3;
    }
    return 4;
  }

  Color get _grassLight {
    if (_winter) {
      return const Color(0xFFBBD4B0);
    }
    if (_night) {
      return const Color(0xFF3F7150);
    }
    if (_bamboo) {
      return const Color(0xFF7DBB61);
    }
    return const Color(0xFF8FCB63);
  }

  Color get _grassDark {
    if (_winter) {
      return const Color(0xFF8EAD8B);
    }
    if (_night) {
      return const Color(0xFF294F3B);
    }
    if (_bamboo) {
      return const Color(0xFF4F8C45);
    }
    return const Color(0xFF5B9B46);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGround(canvas, size);
    _drawIsometricFence(canvas, size);
    _drawPaths(canvas, size);
    _drawNaturalTownhouse(canvas);
    _drawIsometricPond(canvas);
    _drawFacilities(canvas);
    _drawIsometricPlotBeds(canvas);
    _drawLivingDetails(canvas, size);
    _drawMoodTint(canvas, size);
  }

  void _drawGround(Canvas canvas, Size size) {
    final Rect full = Offset.zero & size;
    canvas.drawRect(
      full,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _night
              ? const [Color(0xFF203B51), Color(0xFF234C3C)]
              : _winter
              ? const [Color(0xFFCDE3EE), Color(0xFF8EAF91)]
              : const [Color(0xFFBEE8F0), Color(0xFF5F9E55)],
        ).createShader(full),
    );

    final Paint distant = Paint()
      ..color = _night
          ? const Color(0xFF315345)
          : _winter
          ? const Color(0xFF9CB49E)
          : const Color(0xFF79A765);
    final Path hills = Path()
      ..moveTo(0, 220)
      ..quadraticBezierTo(120, 82, 260, 190)
      ..quadraticBezierTo(420, 34, 600, 178)
      ..quadraticBezierTo(770, 72, size.width, 205)
      ..lineTo(size.width, 330)
      ..lineTo(0, 330)
      ..close();
    canvas.drawPath(hills, distant);

    final Path lot = Path()
      ..moveTo(18, 146)
      ..lineTo(size.width - 18, 112)
      ..lineTo(size.width - 12, size.height - 86)
      ..lineTo(size.width * 0.52, size.height - 18)
      ..lineTo(18, size.height - 82)
      ..close();
    canvas.drawPath(
      lot.shift(const Offset(0, 17)),
      Paint()
        ..color = const Color(0x5C142411)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawPath(
      lot,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_grassLight, const Color(0xFFD3D480), 0.12)!,
            _grassLight,
            _grassDark,
          ],
          stops: const [0, 0.46, 1],
        ).createShader(lot.getBounds()),
    );

    canvas.save();
    canvas.clipPath(lot);

    final List<Color> turfColors = _winter
        ? const [
            Color(0xFFAAC59E),
            Color(0xFFC5D4A8),
            Color(0xFF91B18D),
            Color(0xFFD1DAB5),
          ]
        : _night
        ? const [
            Color(0xFF285A3F),
            Color(0xFF3C7250),
            Color(0xFF426B41),
            Color(0xFF234B39),
          ]
        : const [
            Color(0xFF72AD4E),
            Color(0xFF9BC667),
            Color(0xFF5E9846),
            Color(0xFFAFBF64),
            Color(0xFF4F873E),
          ];

    // Broad, irregular color changes keep the lawn organic at every zoom level.
    for (int i = 0; i < 52; i += 1) {
      final double x = 8 + ((i * 191) % 997) / 997 * (size.width - 16);
      final double y = 180 + ((i * 317) % 991) / 991 * (size.height - 250);
      final double patchWidth = 80 + (i % 7) * 27;
      final double patchHeight = 36 + (i % 5) * 18;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-0.34 + (i % 9) * 0.075);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: patchWidth,
          height: patchHeight,
        ),
        Paint()
          ..color = turfColors[i % turfColors.length].withValues(
            alpha: _winter ? 0.15 : 0.14,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 19),
      );
      canvas.restore();
    }

    final List<Path> bladeLayers = List<Path>.generate(5, (_) => Path());
    for (int i = 0; i < 1120; i += 1) {
      final double x = 22 + ((i * 193) % 1009) / 1009 * (size.width - 44);
      final double y = 188 + ((i * 313) % 1013) / 1013 * (size.height - 264);
      final double length = 5.2 + (i % 7) * 1.05;
      final double breeze = sin(time * 1.45 + i * 0.37 + y * 0.006);
      final double sway = breeze * (1.8 + (i % 4) * 0.5);
      bladeLayers[i % bladeLayers.length]
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + sway * 0.35,
          y - length * 0.56,
          x + sway,
          y - length,
        );
    }
    final List<Color> bladeColors = _winter
        ? const [
            Color(0xFF6F946E),
            Color(0xFF87A77E),
            Color(0xFFDDE8C7),
            Color(0xFF789A75),
            Color(0xFFABC39A),
          ]
        : const [
            Color(0xFF2F7636),
            Color(0xFF4D913D),
            Color(0xFF80AD45),
            Color(0xFF326B35),
            Color(0xFF9FAE43),
          ];
    for (int i = 0; i < bladeLayers.length; i += 1) {
      canvas.drawPath(
        bladeLayers[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25 + (i % 3) * 0.28
          ..strokeCap = StrokeCap.round
          ..color = bladeColors[i].withValues(alpha: _night ? 0.42 : 0.52),
      );
    }

    final List<Path> tuftLayers = List<Path>.generate(4, (_) => Path());
    for (int tuft = 0; tuft < 170; tuft += 1) {
      final double x = 30 + ((tuft * 359) % 1009) / 1009 * (size.width - 60);
      final double y = 210 + ((tuft * 557) % 1013) / 1013 * (size.height - 300);
      for (int blade = 0; blade < 4; blade += 1) {
        final double spread = (blade - 1.5) * 3.2;
        final double length = 9 + ((tuft + blade) % 6) * 1.7;
        final double breeze = sin(time * 1.7 + tuft * 0.51 + blade) * 3;
        tuftLayers[tuft % tuftLayers.length]
          ..moveTo(x + spread * 0.2, y)
          ..quadraticBezierTo(
            x + spread * 0.5 + breeze * 0.25,
            y - length * 0.55,
            x + spread + breeze,
            y - length,
          );
      }
    }
    for (int i = 0; i < tuftLayers.length; i += 1) {
      canvas.drawPath(
        tuftLayers[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round
          ..color = bladeColors[(i + 1) % bladeColors.length].withValues(
            alpha: _night ? 0.46 : 0.63,
          ),
      );
    }

    for (int i = 0; i < 34; i += 1) {
      final double x = 34 + ((i * 271) % 997) / 997 * (size.width - 68);
      final double y = 260 + ((i * 431) % 991) / 991 * (size.height - 350);
      final double sway = sin(time * 1.15 + i) * 1.8;
      final Offset center = Offset(x + sway, y);
      final Color leafColor = i.isEven
          ? const Color(0xFF4B8C3B)
          : const Color(0xFF78A746);
      for (int leaf = 0; leaf < 3; leaf += 1) {
        final double angle = -pi / 2 + (leaf - 1) * 1.85;
        canvas.drawOval(
          Rect.fromCenter(
            center: center + Offset(cos(angle) * 3.8, sin(angle) * 3.2),
            width: 6.8,
            height: 4.4,
          ),
          Paint()..color = leafColor.withValues(alpha: 0.72),
        );
      }
      if (i % 6 == 0 && !_winter) {
        canvas.drawCircle(
          center - const Offset(0, 5),
          2.2,
          Paint()..color = const Color(0xFFFFE9A0).withValues(alpha: 0.9),
        );
      }
    }
    canvas.restore();

    _drawMowableLawn(canvas);
  }

  void _drawMowableLawn(Canvas canvas) {
    final double growth = lawnGrowth.clamp(0.0, 1.0);
    final Path patch = Path()
      ..moveTo(64, 1025)
      ..cubicTo(94, 997, 196, 984, 244, 1000)
      ..quadraticBezierTo(277, 1040, 273, 1099)
      ..cubicTo(242, 1136, 134, 1154, 88, 1137)
      ..quadraticBezierTo(58, 1090, 64, 1025)
      ..close();
    canvas.drawPath(
      patch,
      Paint()
        ..color =
            (growth >= 0.28 ? const Color(0xFF367A35) : const Color(0xFFA6C978))
                .withValues(alpha: 0.11 + growth * 0.08),
    );

    canvas.save();
    canvas.clipPath(patch);
    if (growth < 0.28) {
      final Paint mowingTrace = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFCAE39A).withValues(alpha: 0.09);
      for (int stripe = 0; stripe < 5; stripe += 1) {
        canvas.drawArc(
          Rect.fromLTWH(45 + stripe * 41, 1000, 105, 156),
          0.68,
          1.72,
          false,
          mowingTrace,
        );
      }
    }
    final double bladeLength = 3.5 + growth * 27;
    final List<Path> grassLayers = List<Path>.generate(4, (_) => Path());
    for (int i = 0; i < 210; i += 1) {
      final double x = 66 + ((i * 59) % 997) / 997 * 207;
      final double y = 1008 + ((i * 103) % 991) / 991 * 136;
      final double length = bladeLength * (0.58 + (i % 6) * 0.085);
      final double sway = sin(time * 2.1 + i * 0.48) * (1.2 + growth * 5.2);
      grassLayers[i % grassLayers.length]
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + sway * 0.42,
          y - length * 0.55,
          x + sway,
          y - length,
        );
    }
    const List<Color> growthColors = [
      Color(0xFF2B6B31),
      Color(0xFF3D8135),
      Color(0xFF5A963A),
      Color(0xFF789E3B),
    ];
    for (int i = 0; i < grassLayers.length; i += 1) {
      canvas.drawPath(
        grassLayers[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7 + (i % 2) * 0.45
          ..strokeCap = StrokeCap.round
          ..color = growthColors[i].withValues(alpha: 0.78),
      );
    }
    if (growth > 0.62) {
      for (int i = 0; i < 12; i += 1) {
        final double x = 79 + ((i * 73) % 181);
        final double y = 1024 + ((i * 47) % 100);
        final double sway = sin(time * 2 + i) * 4;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + sway, y - 24 - (i % 3) * 4),
          Paint()
            ..strokeWidth = 1.5
            ..color = const Color(0xFF557E2D),
        );
        canvas.drawCircle(
          Offset(x + sway, y - 25 - (i % 3) * 4),
          2.5,
          Paint()..color = const Color(0xFFD8C96A),
        );
      }
    }
    canvas.restore();
    if (tool == GardenTool.build) {
      canvas.drawPath(
        patch,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(
            0xFFFFE36C,
          ).withValues(alpha: 0.58 + (sin(time * 3) + 1) * 0.16),
      );
    }
  }

  void _drawPaths(Canvas canvas, Size size) {
    final Path main = Path()
      ..moveTo(335, 505)
      ..cubicTo(370, 650, 408, 790, 430, 980)
      ..cubicTo(448, 1180, 430, 1470, 460, size.height - 28);
    _drawStonePath(canvas, main, 72);

    final Path pondBranch = Path()
      ..moveTo(405, 690)
      ..quadraticBezierTo(300, 650, 230, 642);
    _drawStonePath(canvas, pondBranch, 52);

    final Path marketBranch = Path()
      ..moveTo(420, 735)
      ..quadraticBezierTo(610, 730, 755, 714);
    _drawStonePath(canvas, marketBranch, 54);

    final Path lowerBranch = Path()
      ..moveTo(440, 1090)
      ..quadraticBezierTo(300, 1050, 190, 1075)
      ..moveTo(445, 1100)
      ..quadraticBezierTo(590, 1060, 740, 1110);
    _drawStonePath(canvas, lowerBranch, 46);
  }

  void _drawStonePath(Canvas canvas, Path path, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 12
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x33513520),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = _night ? const Color(0xFF718276) : const Color(0xFFC8B78E),
    );
    for (final metric in path.computeMetrics()) {
      for (double distance = 18; distance < metric.length; distance += 54) {
        final tangent = metric.getTangentForOffset(distance);
        if (tangent == null) {
          continue;
        }
        canvas.save();
        canvas.translate(tangent.position.dx, tangent.position.dy);
        canvas.rotate(tangent.angle);
        final Rect stone = Rect.fromCenter(
          center: Offset.zero,
          width: 40 + ((distance / 54).round() % 3) * 4,
          height: max(22, width * 0.43),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(stone, const Radius.circular(9)),
          Paint()..color = const Color(0xFFE8D9B6).withValues(alpha: 0.76),
        );
        canvas.drawLine(
          stone.topLeft + const Offset(7, 5),
          stone.topRight + const Offset(-7, 5),
          Paint()
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.26),
        );
        canvas.restore();
      }
    }
  }

  void _drawNaturalTownhouse(Canvas canvas) {
    Path polygon(List<Offset> points) {
      final Path path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final Offset point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    canvas.save();
    canvas.translate(14, 0);

    final Color wallFront = Color.lerp(
      house.wallColor,
      const Color(0xFFFFF8E7),
      0.72,
    )!;
    final Color wallSide = Color.lerp(
      house.wallColor,
      const Color(0xFFC9B990),
      0.42,
    )!;
    final Color roofBase = Color.lerp(
      house.roofColor,
      const Color(0xFF26394B),
      0.68,
    )!;
    final Color roofLight = Color.lerp(roofBase, const Color(0xFF60758A), 0.3)!;
    final Color roofDark = Color.lerp(roofBase, const Color(0xFF111C29), 0.4)!;
    final Color trim = _night
        ? const Color(0xFFE7E2D1)
        : const Color(0xFFFFF8E8);
    final double roofLift = _tier * 3.5;

    final Path footprint = polygon(const [
      Offset(43, 486),
      Offset(309, 551),
      Offset(468, 467),
      Offset(199, 405),
    ]);
    canvas.drawPath(
      footprint.shift(const Offset(13, 20)),
      Paint()
        ..color = const Color(0x55152113)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );

    final Path patio = polygon(const [
      Offset(278, 535),
      Offset(405, 468),
      Offset(480, 507),
      Offset(350, 579),
    ]);
    canvas.drawPath(
      patio,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE0D3B5), Color(0xFFA99574)],
        ).createShader(patio.getBounds()),
    );
    for (int i = 0; i < 4; i += 1) {
      canvas.drawLine(
        Offset(302 + i * 31, 530 - i * 16),
        Offset(374 + i * 29, 569 - i * 16),
        Paint()
          ..strokeWidth = 1.5
          ..color = const Color(0x33604C35),
      );
    }

    final Path frontWall = polygon([
      Offset(45, 264 - roofLift),
      Offset(306, 326 - roofLift),
      const Offset(306, 554),
      const Offset(45, 493),
    ]);
    final Path sideWall = polygon([
      Offset(306, 326 - roofLift),
      Offset(449, 250 - roofLift),
      const Offset(449, 477),
      const Offset(306, 554),
    ]);
    canvas.drawPath(
      frontWall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(wallFront, Colors.white, 0.18)!, wallFront],
        ).createShader(frontWall.getBounds()),
    );
    canvas.drawPath(
      sideWall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [wallSide, Color.lerp(wallSide, Colors.black, 0.1)!],
        ).createShader(sideWall.getBounds()),
    );

    canvas.save();
    canvas.clipPath(frontWall);
    final Paint siding = Paint()
      ..strokeWidth = 1.6
      ..color = const Color(0x29564634);
    for (int row = 0; row < 10; row += 1) {
      final double y = 287 - roofLift + row * 24.5;
      canvas.drawLine(Offset(48, y), Offset(304, y + 61), siding);
      canvas.drawLine(
        Offset(48, y - 1.7),
        Offset(304, y + 59.3),
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.3),
      );
    }
    canvas.restore();

    canvas.save();
    canvas.clipPath(sideWall);
    for (int row = 0; row < 9; row += 1) {
      final double y = 350 - roofLift + row * 25;
      canvas.drawLine(
        Offset(307, y),
        Offset(448, y - 75),
        Paint()
          ..strokeWidth = 1.4
          ..color = const Color(0x28504030),
      );
    }
    canvas.restore();

    final Path foundationFront = polygon(const [
      Offset(45, 470),
      Offset(306, 531),
      Offset(306, 554),
      Offset(45, 493),
    ]);
    final Path foundationSide = polygon(const [
      Offset(306, 531),
      Offset(449, 454),
      Offset(449, 477),
      Offset(306, 554),
    ]);
    canvas.drawPath(foundationFront, Paint()..color = const Color(0xFFB7A989));
    canvas.drawPath(foundationSide, Paint()..color = const Color(0xFF8E8068));

    final Offset ridgeStart = Offset(165, 100 - roofLift);
    final Offset ridgeEnd = Offset(380, 198 - roofLift);
    final Offset eaveLeft = Offset(28, 273 - roofLift);
    final Offset eaveFront = Offset(316, 342 - roofLift);
    final Offset eaveSide = Offset(468, 259 - roofLift);
    final Offset eaveBack = Offset(193, 190 - roofLift);
    final Path roofFront = polygon([eaveLeft, eaveFront, ridgeEnd, ridgeStart]);
    final Path roofSide = polygon([eaveFront, eaveSide, ridgeEnd]);
    final Path roofBack = polygon([eaveBack, eaveSide, ridgeEnd, ridgeStart]);

    canvas.drawPath(
      roofFront.shift(const Offset(7, 11)),
      Paint()..color = const Color(0x40121B18),
    );
    canvas.drawPath(
      roofBack,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [roofLight, roofBase],
        ).createShader(roofBack.getBounds()),
    );
    canvas.drawPath(
      roofFront,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [roofLight, roofBase, roofDark],
          stops: const [0, 0.62, 1],
        ).createShader(roofFront.getBounds()),
    );
    canvas.drawPath(roofSide, Paint()..color = roofDark);

    canvas.save();
    canvas.clipPath(roofFront);
    for (int row = 1; row <= 7; row += 1) {
      final double t = row / 8;
      final Offset left = Offset.lerp(ridgeStart, eaveLeft, t)!;
      final Offset right = Offset.lerp(ridgeEnd, eaveFront, t)!;
      canvas.drawLine(
        left,
        right,
        Paint()
          ..strokeWidth = row.isEven ? 3 : 2
          ..color = Colors.black.withValues(alpha: 0.19),
      );
      final int shingles = 5 + row;
      for (int shingle = 1; shingle < shingles; shingle += 1) {
        if ((shingle + row).isOdd) {
          continue;
        }
        final Offset start = Offset.lerp(left, right, shingle / shingles)!;
        canvas.drawLine(
          start,
          start + Offset(-4, 8 + row * 0.55),
          Paint()
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: 0.11),
        );
      }
    }
    canvas.restore();
    canvas.drawLine(
      eaveLeft,
      eaveFront,
      Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFEEE6D3),
    );
    canvas.drawLine(
      eaveFront,
      eaveSide,
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFC8BCA6),
    );
    canvas.drawLine(
      ridgeStart,
      ridgeEnd,
      Paint()
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(roofLight, Colors.white, 0.18)!,
    );

    final Path chimney = polygon([
      Offset(262, 155 - roofLift),
      Offset(291, 167 - roofLift),
      Offset(291, 103 - roofLift),
      Offset(262, 91 - roofLift),
    ]);
    canvas.drawPath(
      chimney,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF9D5A42), Color(0xFF6E382E)],
        ).createShader(chimney.getBounds()),
    );
    canvas.drawLine(
      Offset(257, 91 - roofLift),
      Offset(296, 107 - roofLift),
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4F302B),
    );
    for (int puff = 0; puff < 4; puff += 1) {
      final double progress = (time * (0.055 + puff * 0.004) + puff * 0.23) % 1;
      final Offset smoke = Offset(
        276 + sin(time * 0.8 + puff) * 9 + progress * 10,
        77 - roofLift - progress * 78,
      );
      canvas.drawCircle(
        smoke,
        8 + progress * 10,
        Paint()
          ..color = (_night ? const Color(0xFF9FA9B1) : Colors.white)
              .withValues(alpha: (1 - progress) * 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    void frontWindow(Offset center, {bool flowerBox = false}) {
      const double width = 58;
      const double height = 58;
      final double slope = width * 0.118;
      final Path outer = polygon([
        Offset(center.dx - width / 2, center.dy - height / 2 - slope),
        Offset(center.dx + width / 2, center.dy - height / 2 + slope),
        Offset(center.dx + width / 2, center.dy + height / 2 + slope),
        Offset(center.dx - width / 2, center.dy + height / 2 - slope),
      ]);
      final Path glass = polygon([
        Offset(center.dx - 22, center.dy - 22 - 5),
        Offset(center.dx + 22, center.dy - 22 + 5),
        Offset(center.dx + 22, center.dy + 22 + 5),
        Offset(center.dx - 22, center.dy + 22 - 5),
      ]);
      canvas.drawPath(
        outer.shift(const Offset(3, 5)),
        Paint()..color = const Color(0x4A30251A),
      );
      canvas.drawPath(outer, Paint()..color = trim);
      canvas.drawPath(
        glass,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _night
                ? const [Color(0xFFFFE28A), Color(0xFFE69A43)]
                : const [Color(0xFFBFE9ED), Color(0xFF4D99B0)],
          ).createShader(glass.getBounds()),
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - 23),
        Offset(center.dx, center.dy + 27),
        Paint()
          ..strokeWidth = 4
          ..color = trim,
      );
      canvas.drawLine(
        Offset(center.dx - 22, center.dy - 1),
        Offset(center.dx + 22, center.dy + 9),
        Paint()
          ..strokeWidth = 4
          ..color = trim,
      );
      canvas.drawLine(
        Offset(center.dx - 16, center.dy - 16),
        Offset(center.dx - 2, center.dy - 9),
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.52),
      );

      if (flowerBox) {
        final Path box = polygon([
          Offset(center.dx - 34, center.dy + 30),
          Offset(center.dx + 35, center.dy + 46),
          Offset(center.dx + 31, center.dy + 62),
          Offset(center.dx - 38, center.dy + 46),
        ]);
        canvas.drawPath(box, Paint()..color = const Color(0xFF83512D));
        for (int flower = 0; flower < 6; flower += 1) {
          final double sway = sin(time * 1.6 + flower) * 1.5;
          final Offset bloom = Offset(
            center.dx - 27 + flower * 11.2 + sway,
            center.dy + 31 + flower * 2.3,
          );
          canvas.drawCircle(
            bloom,
            6,
            Paint()
              ..color = flower.isEven
                  ? const Color(0xFFF28FB6)
                  : const Color(0xFF86B64B),
          );
        }
      }
    }

    void sideWindow(Offset center) {
      final Path outer = polygon([
        center + const Offset(-29, -18),
        center + const Offset(29, -49),
        center + const Offset(29, 20),
        center + const Offset(-29, 51),
      ]);
      final Path glass = polygon([
        center + const Offset(-21, -14),
        center + const Offset(21, -36),
        center + const Offset(21, 16),
        center + const Offset(-21, 38),
      ]);
      canvas.drawPath(
        outer.shift(const Offset(3, 5)),
        Paint()..color = const Color(0x4A30251A),
      );
      canvas.drawPath(outer, Paint()..color = trim);
      canvas.drawPath(
        glass,
        Paint()
          ..shader = LinearGradient(
            colors: _night
                ? const [Color(0xFFFFE18A), Color(0xFFD78E3C)]
                : const [Color(0xFFA9DFE8), Color(0xFF397F9B)],
          ).createShader(glass.getBounds()),
      );
      canvas.drawLine(
        center + const Offset(0, -29),
        center + const Offset(0, 28),
        Paint()
          ..strokeWidth = 4
          ..color = trim,
      );
    }

    frontWindow(Offset(102, 331 - roofLift * 0.32), flowerBox: true);
    frontWindow(Offset(228, 361 - roofLift * 0.32), flowerBox: true);
    frontWindow(const Offset(103, 435));
    frontWindow(const Offset(229, 465));
    sideWindow(Offset(375, 344 - roofLift * 0.28));

    final Path dormerWall = polygon([
      Offset(169, 205 - roofLift),
      Offset(224, 218 - roofLift),
      Offset(224, 255 - roofLift),
      Offset(169, 242 - roofLift),
    ]);
    final Path dormerRoof = polygon([
      Offset(158, 204 - roofLift),
      Offset(195, 169 - roofLift),
      Offset(236, 202 - roofLift),
      Offset(225, 221 - roofLift),
    ]);
    canvas.drawPath(dormerWall, Paint()..color = wallFront);
    canvas.drawPath(dormerRoof, Paint()..color = roofDark);
    final Path dormerGlass = polygon([
      Offset(181, 207 - roofLift),
      Offset(214, 215 - roofLift),
      Offset(214, 240 - roofLift),
      Offset(181, 232 - roofLift),
    ]);
    canvas.drawPath(dormerGlass, Paint()..color = const Color(0xFF74B6C8));
    canvas.drawPath(
      dormerGlass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = trim,
    );

    final Path door = polygon(const [
      Offset(337, 424),
      Offset(407, 387),
      Offset(407, 500),
      Offset(337, 538),
    ]);
    canvas.drawPath(
      door,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF315E70), Color(0xFF173C4A)],
        ).createShader(door.getBounds()),
    );
    canvas.drawPath(
      door,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round
        ..color = trim,
    );
    final Path doorWindow = polygon(const [
      Offset(350, 428),
      Offset(393, 405),
      Offset(393, 438),
      Offset(350, 461),
    ]);
    canvas.drawPath(
      doorWindow,
      Paint()
        ..color = _night ? const Color(0xFFFFD673) : const Color(0xFF8DD0DA),
    );
    canvas.drawCircle(
      const Offset(392, 469),
      5,
      Paint()..color = const Color(0xFFFFD76A),
    );

    final Path canopy = polygon(const [
      Offset(322, 408),
      Offset(409, 361),
      Offset(450, 382),
      Offset(358, 432),
    ]);
    canvas.drawPath(canopy, Paint()..color = roofDark);
    canvas.drawLine(
      const Offset(348, 425),
      const Offset(348, 536),
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = trim,
    );
    final Path stepOne = polygon(const [
      Offset(326, 538),
      Offset(410, 493),
      Offset(460, 519),
      Offset(373, 566),
    ]);
    final Path stepTwo = polygon(const [
      Offset(344, 555),
      Offset(420, 514),
      Offset(469, 539),
      Offset(390, 582),
    ]);
    canvas.drawPath(stepTwo, Paint()..color = const Color(0xFF96866C));
    canvas.drawPath(stepOne, Paint()..color = const Color(0xFFC7B89B));

    final double lampPulse = 0.82 + sin(time * 2.3) * 0.05;
    canvas.drawCircle(
      const Offset(424, 412),
      22,
      Paint()
        ..color = const Color(0xFFFFD96A).withValues(alpha: 0.12 * lampPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );
    canvas.drawCircle(
      const Offset(424, 412),
      6,
      Paint()..color = const Color(0xFFFFE48B).withValues(alpha: lampPulse),
    );

    for (int pot = 0; pot < 2; pot += 1) {
      final Offset base = pot == 0
          ? const Offset(322, 531)
          : const Offset(449, 502);
      canvas.drawOval(
        Rect.fromCenter(center: base, width: 30, height: 12),
        Paint()..color = const Color(0xFF6D4428),
      );
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - 12, base.dy)
          ..lineTo(base.dx + 12, base.dy)
          ..lineTo(base.dx + 8, base.dy + 24)
          ..lineTo(base.dx - 8, base.dy + 24)
          ..close(),
        Paint()..color = const Color(0xFFA76339),
      );
      for (int leaf = 0; leaf < 5; leaf += 1) {
        final double angle = -2.7 + leaf * 0.65;
        final double sway = sin(time * 1.4 + leaf + pot) * 2;
        canvas.drawOval(
          Rect.fromCenter(
            center: base + Offset(cos(angle) * 13 + sway, -9 + sin(angle) * 9),
            width: 13,
            height: 7,
          ),
          Paint()
            ..color = leaf.isEven
                ? const Color(0xFF4A8C43)
                : const Color(0xFF75A84B),
        );
      }
    }

    if (_tier >= 2) {
      final Path solarPanel = polygon([
        Offset(301, 181 - roofLift),
        Offset(361, 208 - roofLift),
        Offset(335, 236 - roofLift),
        Offset(273, 207 - roofLift),
      ]);
      canvas.drawPath(solarPanel, Paint()..color = const Color(0xFF244E66));
      canvas.drawPath(
        solarPanel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF9ED4E3),
      );
    }

    if (houseActive) {
      final double pulse = 0.46 + (sin(time * 3) + 1) * 0.14;
      canvas.drawPath(
        frontWall,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = const Color(0xFFFFE774).withValues(alpha: pulse),
      );
      canvas.drawPath(
        roofFront,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = const Color(0xFFFFE774).withValues(alpha: pulse),
      );
    }
    canvas.restore();
  }

  // Kept temporarily so older scene snapshots can still be compared locally.
  // ignore: unused_element
  void _drawIsometricHouse(Canvas canvas) {
    final double levelLift = _tier * 10;
    final Color wallFront = Color.lerp(house.wallColor, Colors.white, 0.12)!;
    final Color wallSide = Color.lerp(
      house.wallColor,
      const Color(0xFF8D765C),
      0.25,
    )!;

    final Path shadow = Path()
      ..moveTo(18, 500)
      ..lineTo(318, 580)
      ..lineTo(478, 492)
      ..lineTo(185, 420)
      ..close();
    canvas.drawPath(
      shadow.shift(const Offset(13, 17)),
      Paint()
        ..color = const Color(0x4A172014)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final Path front = Path()
      ..moveTo(18, 244 - levelLift)
      ..lineTo(324, 316 - levelLift)
      ..lineTo(324, 570)
      ..lineTo(18, 500)
      ..close();
    final Path side = Path()
      ..moveTo(324, 316 - levelLift)
      ..lineTo(462, 242 - levelLift)
      ..lineTo(462, 492)
      ..lineTo(324, 570)
      ..close();
    canvas.drawPath(front, Paint()..color = wallFront);
    canvas.drawPath(side, Paint()..color = wallSide);

    for (int row = 0; row < 8; row += 1) {
      final double y = 288 - levelLift + row * 30;
      canvas.drawLine(
        Offset(26, y),
        Offset(316, y + 69),
        Paint()
          ..strokeWidth = 1.3
          ..color = const Color(0x225B4938),
      );
    }

    final Path roofFront = Path()
      ..moveTo(-8, 245 - levelLift)
      ..lineTo(176, 76 - levelLift)
      ..lineTo(363, 224 - levelLift)
      ..lineTo(322, 344 - levelLift)
      ..close();
    final Path roofSide = Path()
      ..moveTo(176, 76 - levelLift)
      ..lineTo(490, 220 - levelLift)
      ..lineTo(363, 224 - levelLift)
      ..close();
    final Color roofLight = Color.lerp(house.roofColor, Colors.white, 0.12)!;
    final Color roofDark = Color.lerp(house.roofColor, Colors.black, 0.18)!;
    canvas.drawPath(
      roofFront.shift(const Offset(8, 10)),
      Paint()..color = const Color(0x43191813),
    );
    canvas.drawPath(roofFront, Paint()..color = roofLight);
    canvas.drawPath(roofSide, Paint()..color = roofDark);

    final Paint roofLine = Paint()
      ..strokeWidth = 3
      ..color = Colors.black.withValues(alpha: 0.16);
    for (int i = 0; i < 9; i += 1) {
      final double t = i / 9;
      canvas.drawLine(
        Offset.lerp(
          Offset(4, 242 - levelLift),
          Offset(176, 84 - levelLift),
          t,
        )!,
        Offset.lerp(
          Offset(322, 335 - levelLift),
          Offset(354, 228 - levelLift),
          t,
        )!,
        roofLine,
      );
    }
    for (int i = 1; i < 7; i += 1) {
      final double t = i / 7;
      canvas.drawLine(
        Offset.lerp(
          Offset(0, 244 - levelLift),
          Offset(322, 340 - levelLift),
          t,
        )!,
        Offset.lerp(
          Offset(176, 82 - levelLift),
          Offset(360, 225 - levelLift),
          t,
        )!,
        roofLine,
      );
    }

    if (houseActive) {
      canvas.drawPath(
        roofFront,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = const Color(
            0xFFFFE66F,
          ).withValues(alpha: 0.45 + (sin(time * 3) + 1) * 0.16),
      );
    }

    void window(Offset center, {bool sideWindow = false}) {
      final Path frame = Path()
        ..moveTo(center.dx - 34, center.dy - 31)
        ..lineTo(center.dx + 31, center.dy - 17)
        ..lineTo(center.dx + 31, center.dy + 37)
        ..lineTo(center.dx - 34, center.dy + 23)
        ..close();
      if (sideWindow) {
        frame
          ..reset()
          ..moveTo(center.dx - 27, center.dy - 15)
          ..lineTo(center.dx + 27, center.dy - 43)
          ..lineTo(center.dx + 27, center.dy + 15)
          ..lineTo(center.dx - 27, center.dy + 43)
          ..close();
      }
      canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF66513D),
      );
      canvas.drawPath(
        frame,
        Paint()
          ..color = _night ? const Color(0xFFFFD66F) : const Color(0xFF73BDD1),
      );
    }

    window(Offset(92, 346 - levelLift * 0.45));
    window(Offset(236, 380 - levelLift * 0.45));
    if (_tier >= 1) {
      window(Offset(95, 438 - levelLift * 0.2));
      window(Offset(232, 470 - levelLift * 0.2));
    }
    window(Offset(390, 392 - levelLift * 0.25), sideWindow: true);

    final Path door = Path()
      ..moveTo(349, 438)
      ..lineTo(411, 405)
      ..lineTo(411, 506)
      ..lineTo(349, 541)
      ..close();
    canvas.drawPath(
      door,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF315B52), Color(0xFF183A34)],
        ).createShader(door.getBounds()),
    );
    canvas.drawCircle(
      const Offset(397, 469),
      5,
      Paint()..color = const Color(0xFFFFD467),
    );

    final Path steps = Path()
      ..moveTo(342, 545)
      ..lineTo(414, 506)
      ..lineTo(462, 531)
      ..lineTo(385, 574)
      ..close();
    canvas.drawPath(steps, Paint()..color = const Color(0xFFB49C78));

    for (final Offset base in const [Offset(58, 382), Offset(208, 416)]) {
      final Path box = Path()
        ..moveTo(base.dx - 36, base.dy + 28)
        ..lineTo(base.dx + 36, base.dy + 45)
        ..lineTo(base.dx + 33, base.dy + 61)
        ..lineTo(base.dx - 39, base.dy + 44)
        ..close();
      canvas.drawPath(box, Paint()..color = const Color(0xFF84552E));
      for (int i = 0; i < 5; i += 1) {
        canvas.drawCircle(
          base + Offset(-25 + i * 13, 26 + i * 3),
          7,
          Paint()
            ..color = i.isEven
                ? const Color(0xFFF18AB0)
                : const Color(0xFF7CB74C),
        );
      }
    }
  }

  void _drawIsometricFence(Canvas canvas, Size size) {
    final Color backWood = _tier >= 2
        ? const Color(0xFFE9DFC8)
        : const Color(0xFF9B6B3A);
    final Color frontWood = _tier >= 2
        ? const Color(0xFFF6F1DF)
        : const Color(0xFFF0E7D0);
    final Color edge = const Color(0xFF695037);

    void segment(Offset start, Offset end, Color wood, {int posts = 7}) {
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = edge,
      );
      canvas.drawLine(
        start - const Offset(0, 5),
        end - const Offset(0, 5),
        Paint()
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = wood,
      );
      for (int i = 0; i <= posts; i += 1) {
        final Offset point = Offset.lerp(start, end, i / posts)!;
        final Path post = Path()
          ..moveTo(point.dx - 8, point.dy + 15)
          ..lineTo(point.dx + 8, point.dy + 12)
          ..lineTo(point.dx + 8, point.dy - 43)
          ..lineTo(point.dx, point.dy - 54)
          ..lineTo(point.dx - 8, point.dy - 40)
          ..close();
        canvas.drawPath(post, Paint()..color = wood);
        canvas.drawPath(
          post,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = edge,
        );
      }
    }

    segment(const Offset(470, 188), const Offset(884, 122), backWood);
    segment(
      const Offset(884, 122),
      const Offset(900, 1180),
      backWood,
      posts: 12,
    );
    segment(
      const Offset(20, 530),
      const Offset(24, 1248),
      frontWood,
      posts: 10,
    );
    segment(
      const Offset(24, 1248),
      const Offset(366, 1304),
      frontWood,
      posts: 6,
    );
    segment(
      const Offset(550, 1304),
      const Offset(894, 1240),
      frontWood,
      posts: 6,
    );

    final Path gate = Path()
      ..moveTo(374, 1262)
      ..lineTo(544, 1262)
      ..lineTo(544, 1342)
      ..lineTo(374, 1342)
      ..close();
    canvas.drawPath(gate, Paint()..color = const Color(0xFF7F542E));
    canvas.drawPath(
      gate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = edge,
    );
    final Rect gateBounds = gate.getBounds();
    for (int i = 1; i < 5; i += 1) {
      final double x = gateBounds.left + gateBounds.width * i / 5;
      canvas.drawLine(
        Offset(x, gateBounds.top + 5),
        Offset(x, gateBounds.bottom - 5),
        Paint()
          ..strokeWidth = 4
          ..color = const Color(0xFFB78248),
      );
    }
  }

  // ignore: unused_element
  void _drawHouse(Canvas canvas) {
    final double extraWidth = _tier * 13;
    final double extraHeight = _tier * 18;
    final Rect body = Rect.fromLTWH(
      46,
      238 - extraHeight,
      482 + extraWidth,
      246 + extraHeight,
    );
    final RRect shadow = RRect.fromRectAndRadius(
      body.shift(const Offset(18, 20)).inflate(8),
      const Radius.circular(16),
    );
    canvas.drawRRect(
      shadow,
      Paint()
        ..color = const Color(0x4D1E1A12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final Path side = Path()
      ..moveTo(body.right, body.top + 32)
      ..lineTo(body.right + 42, body.top)
      ..lineTo(body.right + 42, body.bottom - 22)
      ..lineTo(body.right, body.bottom)
      ..close();
    canvas.drawPath(
      side,
      Paint()
        ..color = Color.lerp(house.wallColor, const Color(0xFF7B654C), 0.32)!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(13)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(house.wallColor, Colors.white, 0.16)!,
            Color.lerp(house.wallColor, const Color(0xFFB58C5A), 0.12)!,
          ],
        ).createShader(body),
    );
    for (double y = body.top + 22; y < body.bottom; y += 25) {
      canvas.drawLine(
        Offset(body.left + 7, y),
        Offset(body.right - 7, y),
        Paint()
          ..strokeWidth = 1.5
          ..color = const Color(0x1F543C27),
      );
    }

    final Path roof = Path()
      ..moveTo(body.left - 25, body.top + 30)
      ..lineTo(body.left + body.width * 0.48, body.top - 122)
      ..lineTo(body.right + 25, body.top + 30)
      ..lineTo(body.right + 4, body.top + 76)
      ..lineTo(body.left + body.width * 0.48, body.top - 54)
      ..lineTo(body.left - 4, body.top + 76)
      ..close();
    canvas.drawPath(
      roof.shift(const Offset(8, 12)),
      Paint()
        ..color = const Color(0x4A1E1711)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      roof,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(house.roofColor, Colors.white, 0.2)!,
            Color.lerp(house.roofColor, Colors.black, 0.22)!,
          ],
        ).createShader(roof.getBounds()),
    );
    for (int i = 0; i < 8; i += 1) {
      final double y = body.top - 72 + i * 17;
      canvas.drawLine(
        Offset(body.left + 34 + i * 15, y),
        Offset(body.right - 32 - i * 14, y),
        Paint()
          ..strokeWidth = 3
          ..color = const Color(0x2E221A13),
      );
    }
    canvas.drawPath(
      roof,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = houseActive ? 8 : 4
        ..color = houseActive
            ? const Color(
                0xFFFFE578,
              ).withValues(alpha: 0.58 + sin(time * 3) * 0.16)
            : const Color(0x77503A24),
    );

    final Rect chimney = Rect.fromLTWH(body.right - 116, body.top - 92, 42, 82);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chimney, const Radius.circular(6)),
      Paint()..color = const Color(0xFF9C6445),
    );
    for (int i = 0; i < 3; i += 1) {
      final double p = (time * 0.16 + i * 0.33) % 1;
      canvas.drawCircle(
        Offset(
          chimney.center.dx + sin(time + i) * 10,
          chimney.top - 10 - p * 65,
        ),
        9 + p * 10,
        Paint()..color = Colors.white.withValues(alpha: 0.18 * (1 - p)),
      );
    }

    final Rect door = Rect.fromLTWH(
      body.left + 240,
      body.bottom - 132,
      70,
      132,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(door, const Radius.circular(15)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF35624B), Color(0xFF1D4234)],
        ).createShader(door),
    );
    canvas.drawCircle(
      Offset(door.right - 15, door.center.dy + 6),
      5,
      Paint()..color = const Color(0xFFFFD56B),
    );

    final int windows = min(4, 2 + _tier);
    for (int i = 0; i < windows; i += 1) {
      final bool left = i.isEven;
      final int row = i ~/ 2;
      final Rect window = Rect.fromLTWH(
        left ? body.left + 48 : body.right - 102,
        body.top + 60 + row * 86,
        54,
        60,
      );
      final double shine = (sin(time * 1.4 + i) + 1) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(window, const Radius.circular(8)),
        Paint()
          ..color = (_night ? const Color(0xFFFFD77A) : const Color(0xFF77C8E1))
              .withValues(alpha: 0.72 + shine * 0.17),
      );
      canvas.drawLine(
        window.topCenter,
        window.bottomCenter,
        Paint()
          ..strokeWidth = 3
          ..color = const Color(0xAA55402D),
      );
      canvas.drawLine(
        window.centerLeft,
        window.centerRight,
        Paint()
          ..strokeWidth = 3
          ..color = const Color(0xAA55402D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(window, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xAA5A422C),
      );
      if (_tier >= 1) {
        _drawWindowBox(canvas, window.bottomCenter + const Offset(0, 8));
      }
    }

    if (_tier >= 2) {
      _drawDormer(canvas, Offset(body.left + 145, body.top - 55));
    }
    if (_tier >= 4) {
      _drawDormer(canvas, Offset(body.right - 150, body.top - 52));
    }

    final Rect porch = Rect.fromLTWH(
      body.left + 168,
      body.bottom - 10,
      220,
      34,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(porch, const Radius.circular(8)),
      Paint()..color = const Color(0xFFA77943),
    );
    for (int i = 0; i < 3; i += 1) {
      final Rect step = Rect.fromCenter(
        center: Offset(porch.center.dx, porch.bottom + 9 + i * 13),
        width: porch.width - 34 - i * 24,
        height: 16,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(step, const Radius.circular(6)),
        Paint()
          ..color = Color.lerp(
            const Color(0xFFC8A16C),
            const Color(0xFF86613B),
            i / 4,
          )!,
      );
    }
  }

  void _drawWindowBox(Canvas canvas, Offset center) {
    final Rect box = Rect.fromCenter(center: center, width: 70, height: 15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xFF80512D),
    );
    for (int i = 0; i < 5; i += 1) {
      canvas.drawCircle(
        Offset(box.left + 9 + i * 13, box.top),
        5,
        Paint()
          ..color = i.isEven
              ? const Color(0xFFF08BB6)
              : const Color(0xFFFFD661),
      );
    }
  }

  void _drawDormer(Canvas canvas, Offset center) {
    final Rect front = Rect.fromCenter(
      center: center + const Offset(0, 20),
      width: 78,
      height: 70,
    );
    canvas.drawRect(front, Paint()..color = house.wallColor);
    final Path cap = Path()
      ..moveTo(front.left - 10, front.top + 4)
      ..lineTo(front.center.dx, front.top - 38)
      ..lineTo(front.right + 10, front.top + 4)
      ..close();
    canvas.drawPath(cap, Paint()..color = house.roofColor);
    final Rect glass = Rect.fromCenter(
      center: front.center + const Offset(0, 4),
      width: 36,
      height: 38,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(glass, const Radius.circular(6)),
      Paint()
        ..color = _night ? const Color(0xFFFFD77A) : const Color(0xFF79CBE2),
    );
  }

  // ignore: unused_element
  void _drawFence(Canvas canvas, Size size) {
    final Color wood = _tier >= 2
        ? const Color(0xFFF1E4CB)
        : const Color(0xFF9A6B38);
    final Color edge = _tier >= 2
        ? const Color(0xFFA89D85)
        : const Color(0xFF654321);
    final Paint rail = Paint()
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = edge;
    final Paint railTop = Paint()
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = wood;
    for (final double x in [31, size.width - 31]) {
      canvas.drawLine(
        const Offset(31, 160),
        Offset(31, size.height - 80),
        rail,
      );
      canvas.drawLine(Offset(x, 160), Offset(x, size.height - 80), railTop);
    }
    canvas.drawLine(const Offset(38, 120), Offset(size.width - 38, 120), rail);
    canvas.drawLine(
      const Offset(38, 120),
      Offset(size.width - 38, 120),
      railTop,
    );

    for (double y = 145; y < size.height - 70; y += 72) {
      _drawFencePost(canvas, Offset(31, y), wood, edge, horizontal: false);
      _drawFencePost(
        canvas,
        Offset(size.width - 31, y),
        wood,
        edge,
        horizontal: false,
      );
    }
    for (double x = 45; x < size.width - 40; x += 76) {
      _drawFencePost(canvas, Offset(x, 120), wood, edge, horizontal: true);
    }

    final Rect gate = Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 55),
      width: 162,
      height: 82,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gate, const Radius.circular(10)),
      Paint()..color = edge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gate.deflate(7), const Radius.circular(7)),
      Paint()..color = wood,
    );
    for (double x = gate.left + 25; x < gate.right; x += 34) {
      canvas.drawLine(
        Offset(x, gate.top + 7),
        Offset(x, gate.bottom - 7),
        Paint()
          ..strokeWidth = 5
          ..color = edge.withValues(alpha: 0.45),
      );
    }
    canvas.drawCircle(
      gate.centerRight - const Offset(20, 0),
      5,
      Paint()..color = const Color(0xFFFFD46A),
    );
  }

  void _drawFencePost(
    Canvas canvas,
    Offset center,
    Color wood,
    Color edge, {
    required bool horizontal,
  }) {
    final Rect post = Rect.fromCenter(
      center: center,
      width: horizontal ? 17 : 22,
      height: horizontal ? 52 : 58,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(post.inflate(3), const Radius.circular(5)),
      Paint()..color = edge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(post, const Radius.circular(4)),
      Paint()..color = wood,
    );
  }

  void _drawIsometricPond(Canvas canvas) {
    final Path rim = Path()
      ..moveTo(46, 660)
      ..lineTo(222, 604)
      ..lineTo(334, 672)
      ..lineTo(154, 750)
      ..close();
    final Path water = Path()
      ..moveTo(67, 661)
      ..lineTo(221, 617)
      ..lineTo(310, 672)
      ..lineTo(153, 730)
      ..close();
    canvas.drawPath(
      rim.shift(const Offset(0, 13)),
      Paint()
        ..color = const Color(0x48182016)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(rim, Paint()..color = const Color(0xFF6F705D));
    canvas.drawPath(
      water,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF77D4E6), Color(0xFF2D8DAC)],
        ).createShader(water.getBounds()),
    );
    canvas.drawPath(
      water,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0xFFB8B092),
    );

    for (int i = 0; i < 5; i += 1) {
      final double phase = (time * 0.28 + i * 0.19) % 1;
      final Offset center = Offset(
        145 + i * 28 + sin(time * 0.7 + i) * 4,
        666 + (i % 2) * 22,
      );
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 31, height: 14),
        Paint()..color = const Color(0xFF6CB153),
      );
      if (i.isEven) {
        canvas.drawCircle(
          center - const Offset(0, 5),
          5,
          Paint()..color = const Color(0xFFF6A0C5),
        );
      }
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(205, 660),
          width: 24 + phase * 90,
          height: 8 + phase * 28,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: (1 - phase) * 0.45),
      );
    }

    if (pondWater > 0) {
      for (int i = 0; i < pondWater + 2; i += 1) {
        final double phase = (time * 0.9 + i / (pondWater + 2)) % 1;
        final Offset drop = Offset(
          205 + (i - pondWater / 2) * 7 * phase,
          659 - 58 * sin(phase * pi),
        );
        canvas.drawCircle(drop, 2.6, Paint()..color = const Color(0xFFD6FAFF));
      }
    }
  }

  // ignore: unused_element
  void _drawPond(Canvas canvas) {
    final Path pond = Path()
      ..moveTo(55, 600)
      ..quadraticBezierTo(80, 548, 152, 548)
      ..quadraticBezierTo(250, 548, 288, 616)
      ..quadraticBezierTo(302, 688, 225, 730)
      ..quadraticBezierTo(118, 756, 60, 700)
      ..quadraticBezierTo(34, 650, 55, 600)
      ..close();
    canvas.drawPath(
      pond.shift(const Offset(0, 12)),
      Paint()
        ..color = const Color(0x4D172118)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      pond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 32
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF817B61),
    );
    canvas.drawPath(
      pond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFBDB28A),
    );
    canvas.drawPath(
      pond,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF65C6DE), Color(0xFF237D9D)],
        ).createShader(pond.getBounds()),
    );

    final double waterPulse = (sin(time * 2.2) + 1) / 2;
    for (int i = 0; i < 4; i += 1) {
      final double phase = (time * 0.32 + i * 0.23) % 1;
      final Rect ripple = Rect.fromCenter(
        center: Offset(158 + sin(i * 2.1) * 45, 640 + cos(i) * 28),
        width: 28 + phase * 70,
        height: 10 + phase * 22,
      );
      canvas.drawOval(
        ripple,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white.withValues(alpha: (1 - phase) * 0.48),
      );
    }
    for (int i = 0; i < 5; i += 1) {
      final Offset pad = Offset(
        92 + i * 34 + sin(time * 0.55 + i) * 4,
        625 + (i % 2) * 43,
      );
      canvas.drawOval(
        Rect.fromCenter(center: pad, width: 31, height: 17),
        Paint()..color = const Color(0xFF69B04B),
      );
      if (i.isEven) {
        canvas.drawCircle(
          pad - const Offset(0, 6),
          6,
          Paint()..color = const Color(0xFFF59CC4),
        );
      }
    }
    if (pondWater > 0) {
      final Offset fountain = const Offset(160, 622);
      for (int i = 0; i < pondWater; i += 1) {
        final double phase = (time * 0.85 + i / pondWater) % 1;
        final Offset drop =
            fountain +
            Offset((i - pondWater / 2) * 8 * phase, -52 * sin(phase * pi));
        canvas.drawCircle(
          drop,
          2.5 + waterPulse,
          Paint()..color = const Color(0xFFC9F7FF),
        );
      }
    }
  }

  void _drawFacilities(Canvas canvas) {
    _drawJournal(canvas);
    _drawRainBarrel(canvas);
    _drawMarket(canvas);
    _drawCompost(canvas);
    _drawMower(canvas);
    if (_tier >= 1) {
      _drawBeehive(canvas);
    }
    if (_tier >= 2) {
      _drawGreenhouse(canvas);
    }
  }

  void _drawJournal(Canvas canvas) {
    const Offset base = Offset(332, 548);
    canvas.drawLine(
      base + const Offset(0, -52),
      base + const Offset(0, 30),
      Paint()
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF76502B),
    );
    final Rect sign = Rect.fromCenter(
      center: base - const Offset(0, 58),
      width: 108,
      height: 60,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sign, const Radius.circular(8)),
      Paint()..color = const Color(0xFF9D713C),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sign.deflate(5), const Radius.circular(6)),
      Paint()..color = const Color(0xFFE7D6A4),
    );
    final Path leaf = Path()
      ..moveTo(sign.center.dx - 22, sign.center.dy + 12)
      ..quadraticBezierTo(
        sign.center.dx - 7,
        sign.center.dy - 20,
        sign.center.dx + 18,
        sign.center.dy - 10,
      )
      ..quadraticBezierTo(
        sign.center.dx + 5,
        sign.center.dy + 14,
        sign.center.dx - 22,
        sign.center.dy + 12,
      )
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF5C9A3D));
  }

  void _drawRainBarrel(Canvas canvas) {
    const Offset center = Offset(438, 526);
    final Rect barrel = Rect.fromCenter(center: center, width: 65, height: 82);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 38),
        width: 72,
        height: 18,
      ),
      Paint()..color = const Color(0x44351F12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barrel, const Radius.circular(20)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF62A8C4), Color(0xFF286C8B)],
        ).createShader(barrel),
    );
    for (double y = barrel.top + 18; y < barrel.bottom; y += 30) {
      canvas.drawLine(
        Offset(barrel.left + 4, y),
        Offset(barrel.right - 4, y),
        Paint()
          ..strokeWidth = 5
          ..color = const Color(0xFF1D4C61),
      );
    }
    canvas.drawOval(
      Rect.fromLTWH(barrel.left + 3, barrel.top - 4, barrel.width - 6, 18),
      Paint()..color = const Color(0xFF9DDDF0),
    );
    canvas.drawCircle(
      barrel.bottomRight - const Offset(10, 18),
      6,
      Paint()..color = const Color(0xFFFFD269),
    );
  }

  void _drawMarket(Canvas canvas) {
    const Rect counter = Rect.fromLTWH(726, 678, 164, 92);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        counter.shift(const Offset(8, 10)),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0x4425150B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(counter, const Radius.circular(10)),
      Paint()..color = const Color(0xFF9A622F),
    );
    for (double x = counter.left + 16; x < counter.right; x += 28) {
      canvas.drawLine(
        Offset(x, counter.top + 8),
        Offset(x, counter.bottom - 8),
        Paint()
          ..strokeWidth = 3
          ..color = const Color(0xFF68401F),
      );
    }
    canvas.drawLine(
      Offset(counter.left + 13, counter.top),
      Offset(counter.left + 13, counter.top - 86),
      Paint()
        ..strokeWidth = 9
        ..color = const Color(0xFF76502B),
    );
    canvas.drawLine(
      Offset(counter.right - 13, counter.top),
      Offset(counter.right - 13, counter.top - 86),
      Paint()
        ..strokeWidth = 9
        ..color = const Color(0xFF76502B),
    );
    final Rect awning = Rect.fromLTWH(
      counter.left - 12,
      counter.top - 105,
      counter.width + 24,
      44,
    );
    for (int i = 0; i < 7; i += 1) {
      final Rect stripe = Rect.fromLTWH(
        awning.left + i * awning.width / 7,
        awning.top,
        awning.width / 7 + 1,
        awning.height,
      );
      canvas.drawRect(
        stripe,
        Paint()
          ..color = i.isEven
              ? const Color(0xFFF7E9CF)
              : const Color(0xFFD75B45),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(awning, const Radius.circular(7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF85472E),
    );
    for (int i = 0; i < 7; i += 1) {
      final double bob = marketReady ? sin(time * 2.5 + i) * 2 : 0;
      canvas.drawCircle(
        Offset(counter.left + 22 + (i % 4) * 38, counter.top - 7 + bob),
        11,
        Paint()
          ..color = i % 3 == 0
              ? const Color(0xFFE14E3F)
              : i % 3 == 1
              ? const Color(0xFFF1B43A)
              : const Color(0xFF65A946),
      );
    }

    final Rect sign = Rect.fromLTWH(
      counter.left + 15,
      counter.top + 16,
      counter.width - 58,
      34,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sign, const Radius.circular(6)),
      Paint()..color = const Color(0xFF315F42),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sign.deflate(3), const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFF4D487),
    );
    final TextPainter signText = TextPainter(
      text: const TextSpan(
        text: 'GARDEN STAND',
        style: TextStyle(
          color: Color(0xFFFFF5D7),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    signText.paint(
      canvas,
      Offset(
        sign.center.dx - signText.width / 2,
        sign.center.dy - signText.height / 2,
      ),
    );
  }

  void _drawCompost(Canvas canvas) {
    const Rect bin = Rect.fromLTWH(284, 966, 116, 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bin.shift(const Offset(7, 10)),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0x4423150B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bin, const Radius.circular(9)),
      Paint()..color = const Color(0xFF8A5B31),
    );
    for (double y = bin.top + 18; y < bin.bottom; y += 24) {
      canvas.drawLine(
        Offset(bin.left + 8, y),
        Offset(bin.right - 8, y),
        Paint()
          ..strokeWidth = 4
          ..color = const Color(0xFF5C3B22),
      );
    }
    canvas.drawCircle(bin.center, 28, Paint()..color = const Color(0xFF4C8F3C));
    _drawRecycleMark(canvas, bin.center);
  }

  void _drawRecycleMark(Canvas canvas, Offset center) {
    final Paint mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE1F3B4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 16),
      -pi * 0.25,
      pi * 0.55,
      false,
      mark,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 16),
      pi * 0.42,
      pi * 0.55,
      false,
      mark,
    );
  }

  void _drawMower(Canvas canvas) {
    const Offset center = Offset(86, 1018);
    final double bounce = lawnGrowth >= 0.28 ? sin(time * 2.4) * 2 : 0;
    canvas.save();
    canvas.translate(0, bounce);
    final Rect body = Rect.fromCenter(center: center, width: 78, height: 48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(12)),
      Paint()..color = const Color(0xFFCF4A3C),
    );
    canvas.drawCircle(
      body.bottomLeft + const Offset(15, 3),
      12,
      Paint()..color = const Color(0xFF26352A),
    );
    canvas.drawCircle(
      body.bottomRight - const Offset(15, -3),
      12,
      Paint()..color = const Color(0xFF26352A),
    );
    canvas.drawLine(
      body.topRight - const Offset(6, 2),
      body.topRight + const Offset(25, -62),
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF44544B),
    );
    canvas.drawLine(
      body.topRight + const Offset(15, -62),
      body.topRight + const Offset(42, -62),
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF44544B),
    );
    canvas.restore();
  }

  // ignore: unused_element
  void _drawVegetableBed(Canvas canvas) {
    const Rect bed = Rect.fromLTWH(618, 964, 238, 104);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bed.shift(const Offset(0, 10)),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0x55311B0F),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bed, const Radius.circular(10)),
      Paint()..color = const Color(0xFF8C5932),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bed.deflate(12), const Radius.circular(6)),
      Paint()..color = const Color(0xFF4A2C1C),
    );
    for (int row = 0; row < 3; row += 1) {
      for (int column = 0; column < 7; column += 1) {
        final Offset plant = Offset(
          bed.left + 30 + column * 29,
          bed.top + 26 + row * 26,
        );
        final double sway = sin(time * 1.1 + row + column) * 2;
        canvas.drawOval(
          Rect.fromCenter(
            center: plant + Offset(-5 + sway, 0),
            width: 14,
            height: 9,
          ),
          Paint()..color = const Color(0xFF69A946),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: plant + Offset(5 + sway, -2),
            width: 14,
            height: 9,
          ),
          Paint()..color = const Color(0xFF82C45A),
        );
      }
    }
  }

  void _drawBeehive(Canvas canvas) {
    const Offset center = Offset(842, 914);
    canvas.drawLine(
      center + const Offset(0, 20),
      center + const Offset(0, 80),
      Paint()
        ..strokeWidth = 14
        ..color = const Color(0xFF76502B),
    );
    for (int i = 0; i < 4; i += 1) {
      final Rect layer = Rect.fromCenter(
        center: center + Offset(0, i * 14),
        width: 80 - i * 7,
        height: 24,
      );
      canvas.drawOval(layer, Paint()..color = const Color(0xFFE5AD3D));
    }
    canvas.drawCircle(
      center + const Offset(0, 22),
      7,
      Paint()..color = const Color(0xFF59391E),
    );
    for (int i = 0; i < 3; i += 1) {
      final double angle = time * (0.7 + i * 0.1) + i * 2.1;
      final Offset bee = center + Offset(cos(angle) * 58, sin(angle) * 28 - 10);
      canvas.drawOval(
        Rect.fromCenter(center: bee, width: 12, height: 8),
        Paint()..color = const Color(0xFFFFD249),
      );
      canvas.drawLine(
        bee - const Offset(2, 4),
        bee + const Offset(2, 4),
        Paint()
          ..strokeWidth = 2
          ..color = const Color(0xFF332519),
      );
    }
  }

  void _drawGreenhouse(Canvas canvas) {
    const Rect houseRect = Rect.fromLTWH(520, 1690, 300, 150);
    canvas.drawRRect(
      RRect.fromRectAndRadius(houseRect, const Radius.circular(18)),
      Paint()..color = const Color(0x557DE0CE),
    );
    final Paint frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0xFFDDF8E5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(houseRect, const Radius.circular(18)),
      frame,
    );
    final Path roof = Path()
      ..moveTo(houseRect.left + 18, houseRect.top)
      ..lineTo(houseRect.center.dx, houseRect.top - 72)
      ..lineTo(houseRect.right - 18, houseRect.top)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0x557DE0CE));
    canvas.drawPath(roof, frame);
    for (double x = houseRect.left + 55; x < houseRect.right; x += 60) {
      canvas.drawLine(
        Offset(x, houseRect.top + 5),
        Offset(x, houseRect.bottom - 5),
        frame,
      );
    }
  }

  Path _isometricBedPath(
    Offset center,
    double width,
    double height, {
    double inset = 0,
  }) {
    final double halfWidth = max(4, width / 2 - inset);
    final double halfHeight = max(3, height / 2 - inset * 0.52);
    return Path()
      ..moveTo(center.dx, center.dy - halfHeight)
      ..lineTo(center.dx + halfWidth, center.dy)
      ..lineTo(center.dx, center.dy + halfHeight)
      ..lineTo(center.dx - halfWidth, center.dy)
      ..close();
  }

  void _drawIsometricPlotBeds(Canvas canvas) {
    for (final PlayerGardenPlot plot in plots) {
      final bool unlocked = plot.unlockLevel <= gardenLevel;
      final bool next =
          plot.unlockLevel == gardenLevel + 1 &&
          plot.unlockLevel <= house.maxGardenLevel;
      final bool nextHouse =
          tool == GardenTool.build &&
          gardenLevel >= house.maxGardenLevel &&
          plot.unlockLevel == house.maxGardenLevel + 1;
      if (!unlocked && !next && !nextHouse) {
        continue;
      }
      final bool tree = plot.plantIndex != null && plot.plantIndex! >= 6;
      final double width = tree ? 174 : 168;
      final double height = tree ? 78 : 98;
      final Path top = _isometricBedPath(plot.position, width, height);
      final Path lower = _isometricBedPath(
        plot.position + const Offset(0, 13),
        width,
        height,
      );
      final bool moveTarget =
          tool == GardenTool.move &&
          movingPlotId != null &&
          !plot.planted &&
          unlocked;
      final bool moveSelected = movingPlotId == plot.id;
      final bool plantTarget =
          tool == GardenTool.plant && !plot.planted && unlocked && !plot.weed;
      final bool harvestTarget =
          tool == GardenTool.harvest && unlocked && (plot.ready || plot.weed);
      final bool active =
          moveTarget || moveSelected || plantTarget || harvestTarget;
      final double pulse = (sin(time * 3.2 + plot.id) + 1) / 2;

      canvas.drawPath(
        lower.shift(const Offset(0, 7)),
        Paint()
          ..color = const Color(0x44241710)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      if (!unlocked) {
        canvas.drawPath(lower, Paint()..color = const Color(0xFF596B48));
        canvas.drawPath(
          top,
          Paint()
            ..color = plot.grassCut
                ? const Color(0xFF9A8C68)
                : const Color(0xFF6F8E55),
        );
        final Path inner = _isometricBedPath(
          plot.position,
          width,
          height,
          inset: 13,
        );
        canvas.drawPath(
          inner,
          Paint()
            ..color = plot.grassCut
                ? const Color(0xFF76664D)
                : const Color(0xFF537A45),
        );
        canvas.drawPath(
          top,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = next ? 7 : 3
            ..color = next
                ? const Color(0xFFFFE56E).withValues(alpha: 0.55 + pulse * 0.33)
                : const Color(0x779BB18A),
        );
        for (int i = -1; i < 3; i += 1) {
          canvas.save();
          canvas.clipPath(inner);
          canvas.drawLine(
            Offset(plot.position.dx - 90 + i * 50, plot.position.dy + 48),
            Offset(plot.position.dx - 20 + i * 50, plot.position.dy - 48),
            Paint()
              ..strokeWidth = 13
              ..color = Colors.white.withValues(alpha: 0.09),
          );
          canvas.restore();
        }
        _drawLock(canvas, plot.position, next);
        continue;
      }

      if (tree) {
        canvas.drawPath(
          top,
          Paint()
            ..color = active
                ? const Color(0x555BDF62)
                : const Color(0x2A70B95A),
        );
        final Paint grid = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 4 : 2
          ..color = active
              ? Colors.white.withValues(alpha: 0.78)
              : Colors.white.withValues(alpha: 0.18);
        canvas.drawPath(top, grid);
        canvas.drawLine(
          Offset(
            plot.position.dx - width * 0.25,
            plot.position.dy - height * 0.25,
          ),
          Offset(
            plot.position.dx + width * 0.25,
            plot.position.dy + height * 0.25,
          ),
          grid,
        );
        canvas.drawLine(
          Offset(
            plot.position.dx + width * 0.25,
            plot.position.dy - height * 0.25,
          ),
          Offset(
            plot.position.dx - width * 0.25,
            plot.position.dy + height * 0.25,
          ),
          grid,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: plot.position + const Offset(0, 9),
            width: 76,
            height: 29,
          ),
          Paint()..color = const Color(0xAA4A3321),
        );
      } else {
        canvas.drawPath(lower, Paint()..color = const Color(0xFF765035));
        canvas.drawPath(
          top,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD8C391), Color(0xFF8F7650)],
            ).createShader(top.getBounds()),
        );
        final Path soil = _isometricBedPath(
          plot.position,
          width,
          height,
          inset: 15,
        );
        canvas.drawPath(
          soil,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(-0.25, -0.4),
              colors: [Color(0xFF7A5131), Color(0xFF3F291C)],
            ).createShader(soil.getBounds()),
        );
        for (int i = 0; i < 10; i += 1) {
          final double dx = -52 + ((i * 43 + plot.id * 19) % 100) / 100 * 104;
          final double dy = -15 + ((i * 67 + plot.id * 11) % 100) / 100 * 30;
          canvas.drawCircle(
            plot.position + Offset(dx, dy),
            1.4 + (i % 2),
            Paint()..color = const Color(0x557DAB5A),
          );
        }
      }

      if (active) {
        canvas.drawPath(
          _isometricBedPath(
            plot.position,
            width + 15 + pulse * 12,
            height + 8 + pulse * 7,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = moveSelected ? 8 : 6
            ..color = moveSelected
                ? const Color(0xFF74C8FF)
                : const Color(0xFFDFFF75).withValues(alpha: 0.62 + pulse * 0.3),
        );
      }
    }
  }

  // ignore: unused_element
  void _drawPlotBeds(Canvas canvas) {
    for (final PlayerGardenPlot plot in plots) {
      if (plot.unlockLevel > house.maxGardenLevel + 1) {
        continue;
      }
      final bool unlocked = plot.unlockLevel <= gardenLevel;
      final bool next =
          plot.unlockLevel == gardenLevel + 1 &&
          plot.unlockLevel <= house.maxGardenLevel;
      final bool tree = plot.plantIndex != null && plot.plantIndex! >= 6;
      final Size size = tree ? const Size(170, 104) : const Size(146, 88);
      final Rect outer = Rect.fromCenter(
        center: plot.position,
        width: size.width,
        height: size.height,
      );
      final bool moveTarget =
          tool == GardenTool.move &&
          movingPlotId != null &&
          !plot.planted &&
          unlocked;
      final bool moveSelected = movingPlotId == plot.id;
      final bool plantTarget =
          tool == GardenTool.plant && !plot.planted && unlocked && !plot.weed;
      final double pulse = (sin(time * 3.2 + plot.id) + 1) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          outer.shift(const Offset(0, 11)),
          const Radius.circular(22),
        ),
        Paint()
          ..color = const Color(0x55301D12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      if (!unlocked) {
        final Color lockedTop = plot.grassCut
            ? const Color(0xFF9DB675)
            : const Color(0xFF608D4A);
        canvas.drawRRect(
          RRect.fromRectAndRadius(outer, const Radius.circular(20)),
          Paint()..color = lockedTop,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(outer.deflate(8), const Radius.circular(15)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = next ? 6 : 3
            ..color = next
                ? const Color(0xFFFFE56E).withValues(alpha: 0.56 + pulse * 0.3)
                : const Color(0x7792AC7A),
        );
        for (int stripe = -2; stripe < 4; stripe += 1) {
          canvas.save();
          canvas.clipRRect(
            RRect.fromRectAndRadius(
              outer.deflate(12),
              const Radius.circular(12),
            ),
          );
          canvas.drawLine(
            Offset(outer.left + stripe * 48, outer.bottom),
            Offset(outer.left + stripe * 48 + 92, outer.top),
            Paint()
              ..strokeWidth = 14
              ..color = const Color(0x1FFFFFFF),
          );
          canvas.restore();
        }
        _drawLock(canvas, outer.center, next);
        continue;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(outer, const Radius.circular(22)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFC3AE78), Color(0xFF86704A)],
          ).createShader(outer),
      );
      final Rect soil = outer.deflate(13);
      canvas.drawRRect(
        RRect.fromRectAndRadius(soil, const Radius.circular(15)),
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Color(0xFF765033), Color(0xFF3E281B)],
          ).createShader(soil),
      );
      for (int i = 0; i < 13; i += 1) {
        canvas.drawCircle(
          Offset(
            soil.left +
                9 +
                ((i * 43 + plot.id * 19) % 100) / 100 * (soil.width - 18),
            soil.top +
                8 +
                ((i * 67 + plot.id * 11) % 100) / 100 * (soil.height - 16),
          ),
          1.5 + (i % 3) * 0.5,
          Paint()..color = const Color(0x557DAB5A),
        );
      }

      if (plantTarget || moveTarget || moveSelected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            outer.inflate(8 + pulse * 6),
            const Radius.circular(27),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = moveSelected ? 8 : 6
            ..color = moveSelected
                ? const Color(0xFF74C8FF)
                : const Color(0xFFDFFF75).withValues(alpha: 0.62 + pulse * 0.3),
        );
        final Paint grid = Paint()
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.32 + pulse * 0.2);
        for (int i = 1; i < 3; i += 1) {
          final double dx = soil.left + soil.width * i / 3;
          final double dy = soil.top + soil.height * i / 3;
          canvas.drawLine(Offset(dx, soil.top), Offset(dx, soil.bottom), grid);
          canvas.drawLine(Offset(soil.left, dy), Offset(soil.right, dy), grid);
        }
      }
    }
  }

  void _drawLock(Canvas canvas, Offset center, bool active) {
    final Color color = active
        ? const Color(0xFFFFE57A)
        : const Color(0xFFDBE0CF);
    final Rect body = Rect.fromCenter(
      center: center + const Offset(0, 10),
      width: 42,
      height: 34,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center - const Offset(0, 8),
        width: 28,
        height: 34,
      ),
      pi,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(7)),
      Paint()..color = color,
    );
    canvas.drawCircle(
      center + const Offset(0, 7),
      4,
      Paint()..color = const Color(0xFF58604D),
    );
  }

  void _drawLivingDetails(Canvas canvas, Size size) {
    void drawShrub(Offset center, int index) {
      final double breeze = sin(time * 1.25 + index * 0.9) * 2.4;
      canvas.drawOval(
        Rect.fromCenter(
          center: center + const Offset(3, 18),
          width: 66,
          height: 25,
        ),
        Paint()
          ..color = const Color(0x47182B15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      final List<Color> colors = _night
          ? const [Color(0xFF1D4935), Color(0xFF2E6240), Color(0xFF3C7148)]
          : const [
              Color(0xFF2F7135),
              Color(0xFF4C9440),
              Color(0xFF6BA648),
              Color(0xFF3A813C),
            ];
      for (int lobe = 0; lobe < 7; lobe += 1) {
        final double angle = lobe * pi * 2 / 7 + index * 0.31;
        final double radius = 19 + ((index + lobe * 3) % 9).toDouble();
        final Offset lobeCenter =
            center +
            Offset(
              cos(angle) * (16 + lobe % 3 * 4) + breeze * (0.2 + lobe * 0.04),
              sin(angle) * 13 - (lobe.isEven ? 5 : 0),
            );
        canvas.drawCircle(
          lobeCenter,
          radius,
          Paint()..color = colors[(index + lobe) % colors.length],
        );
        canvas.drawCircle(
          lobeCenter - const Offset(5, 6),
          radius * 0.34,
          Paint()..color = Colors.white.withValues(alpha: 0.055),
        );
      }
      for (int tip = 0; tip < 4; tip += 1) {
        final double angle = -2.7 + tip * 0.82;
        canvas.save();
        canvas.translate(
          center.dx + cos(angle) * 26 + breeze,
          center.dy + sin(angle) * 17,
        );
        canvas.rotate(angle + breeze * 0.015);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 15, height: 7),
          Paint()
            ..color = tip.isEven
                ? const Color(0xFF75AD4D)
                : const Color(0xFF4C8B3F),
        );
        canvas.restore();
      }
    }

    for (int i = 0; i < 13; i += 1) {
      final double y = 210 + i * 132 + (i % 3) * 17;
      drawShrub(Offset(24 + (i % 4) * 7, y), i);
    }
    for (int i = 0; i < 12; i += 1) {
      final double y = 260 + i * 139 + (i % 4) * 13;
      drawShrub(Offset(size.width - 26 - (i % 3) * 6, y), i + 17);
    }

    final int flowerCount = 42 + _tier * 8;
    for (int i = 0; i < flowerCount; i += 1) {
      final bool left = i.isEven;
      final double x = left ? 58 + (i * 19) % 82 : 790 + (i * 23) % 72;
      final double y = 520 + (i * 97) % 1240;
      final Color petal = i % 3 == 0
          ? const Color(0xFF71B9EB)
          : i % 3 == 1
          ? const Color(0xFFF08AB5)
          : const Color(0xFFFFD75F);
      for (int p = 0; p < 5; p += 1) {
        final double angle = p * pi * 2 / 5 + time * 0.02;
        canvas.drawCircle(
          Offset(x + cos(angle) * 4.5, y + sin(angle) * 4.5),
          3.2,
          Paint()..color = petal,
        );
      }
    }

    final int leafCount = 8 + mood ~/ 10;
    for (int i = 0; i < leafCount; i += 1) {
      final double progress = (time * (0.08 + i * 0.004) + i * 0.137) % 1;
      final Offset leaf = Offset(
        70 +
            ((i * 157) % 1000) / 1000 * (size.width - 140) +
            sin(time + i) * 16,
        500 + progress * (size.height - 620),
      );
      canvas.save();
      canvas.translate(leaf.dx, leaf.dy);
      canvas.rotate(time * 0.3 + i);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 5),
        Paint()..color = const Color(0xFFFFE98A).withValues(alpha: 0.38),
      );
      canvas.restore();
    }

    if (dailyComplete) {
      for (int i = 0; i < 18; i += 1) {
        final double pulse = (sin(time * 3 + i) + 1) / 2;
        final Offset sparkle = Offset(
          80 + ((i * 211) % 1000) / 1000 * (size.width - 160),
          520 + ((i * 337) % 1000) / 1000 * (size.height - 650),
        );
        final Paint star = Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(
            0xFFFFF3A0,
          ).withValues(alpha: 0.4 + pulse * 0.4);
        canvas.drawLine(
          sparkle - Offset(5 * pulse, 0),
          sparkle + Offset(5 * pulse, 0),
          star,
        );
        canvas.drawLine(
          sparkle - Offset(0, 5 * pulse),
          sparkle + Offset(0, 5 * pulse),
          star,
        );
      }
    }
  }

  void _drawMoodTint(Canvas canvas, Size size) {
    if (mood < 38) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = const Color(
            0xFF665A42,
          ).withValues(alpha: (38 - mood) / 260),
      );
    }
    if (_night) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x40214370),
      );
    }
    if (_winter) {
      for (int i = 0; i < 70; i += 1) {
        final double y =
            (((i * 127) % 1000) / 1000 * size.height + time * 18 + i * 7) %
            size.height;
        final double x =
            ((i * 71) % 1000) / 1000 * size.width + sin(time + i) * 9;
        canvas.drawCircle(
          Offset(x, y),
          1.5 + (i % 3).toDouble(),
          Paint()..color = Colors.white.withValues(alpha: 0.55),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BuilderBackyardPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.world != world ||
        oldDelegate.house != house ||
        oldDelegate.gardenLevel != gardenLevel ||
        oldDelegate.mood != mood ||
        oldDelegate.dailyComplete != dailyComplete ||
        oldDelegate.houseActive != houseActive ||
        oldDelegate.lawnGrowth != lawnGrowth ||
        oldDelegate.pondWater != pondWater ||
        oldDelegate.marketReady != marketReady ||
        oldDelegate.heartLevel != heartLevel ||
        oldDelegate.heartPulse != heartPulse ||
        oldDelegate.tool != tool ||
        oldDelegate.movingPlotId != movingPlotId ||
        oldDelegate.plots != plots;
  }
}

// Kept while old saves migrate to the modular builder scene.
// ignore: unused_element
class _BackyardGardenPainter extends CustomPainter {
  const _BackyardGardenPainter({
    required this.world,
    required this.house,
    required this.plots,
    required this.gardenLevel,
    required this.mood,
    required this.dailyComplete,
    required this.houseActive,
    required this.lawnGrowth,
    required this.pondWater,
    required this.marketReady,
    required this.heartLevel,
    required this.heartPulse,
    required this.time,
  });

  final GardenWorld world;
  final GardenHouseTier house;
  final List<PlayerGardenPlot> plots;
  final int gardenLevel;
  final int mood;
  final bool dailyComplete;
  final bool houseActive;
  final double lawnGrowth;
  final int pondWater;
  final bool marketReady;
  final int heartLevel;
  final double heartPulse;
  final double time;

  bool get _night => world.ambient == GardenAmbient.fireflies;
  bool get _winter => world.ambient == GardenAmbient.snow;
  bool get _bamboo => world.ambient == GardenAmbient.bambooLeaves;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGround(canvas, size);
    _drawHouseEdge(canvas, size);
    _drawGardenRooms(canvas, size);
    _drawPath(canvas, size);
    _drawPond(canvas, size);
    _drawFenceAndBorders(canvas, size);
    _drawBackyardDetails(canvas, size);
    _drawGardenHeart(canvas);
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
    final double cutVisibility = 1 - lawnGrowth.clamp(0.0, 1.0);
    final Paint lightBand = Paint()
      ..style = PaintingStyle.fill
      ..color = (_winter ? Colors.white : const Color(0xFFD8F69B)).withValues(
        alpha: _winter ? 0.1 : 0.06 + cutVisibility * 0.16,
      );
    final Paint darkBand = Paint()
      ..style = PaintingStyle.fill
      ..color = (_night ? const Color(0xFF183826) : const Color(0xFF2E7432))
          .withValues(
            alpha: _night
                ? 0.08 + cutVisibility * 0.08
                : 0.04 + cutVisibility * 0.13,
          );

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
    final double growth = lawnGrowth.clamp(0.08, 1.0);
    final Paint blade = Paint()
      ..strokeWidth = 1.05 + growth * 0.65
      ..strokeCap = StrokeCap.round
      ..color = (_night ? const Color(0xFF8DD269) : const Color(0xFFE2F58F))
          .withValues(
            alpha: _winter ? 0.16 + growth * 0.1 : 0.2 + growth * 0.2,
          );
    final Paint bloom = Paint()
      ..color = (_night ? const Color(0xFFB8EFFF) : const Color(0xFFFFE49A))
          .withValues(alpha: _winter ? 0.15 : 0.55);
    final Paint clover = Paint()
      ..color = (_night ? const Color(0xFF66B675) : const Color(0xFF2E8A39))
          .withValues(alpha: _winter ? 0.18 : 0.42);

    final int bladeCount = 90 + (growth * 270).round();
    final double bladeHeight = 4 + growth * 15;
    for (int i = 0; i < bladeCount; i += 1) {
      final double x = ((i * 73) % 1000) / 1000 * size.width;
      final double y = 360 + ((i * 137) % 1000) / 1000 * (size.height - 380);
      final double lean = sin(time * 1.8 + i * 1.7) * (1.5 + growth * 5.5);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + lean, y - bladeHeight - (i % 3) * growth * 3),
        blade,
      );
      if (growth > 0.55 && i % 9 == 0) {
        canvas.drawCircle(Offset(x + 3, y - bladeHeight - 2), 2.1, bloom);
      }
      if (growth > 0.35 && i % 17 == 0) {
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

    if (marketReady) {
      final double bounce = sin(time * 3.2) * 3;
      final Rect crate = Rect.fromCenter(
        center: Offset(houseRect.right - 76, porch.top - 8 + bounce),
        width: 98,
        height: 48,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(crate, const Radius.circular(8)),
        Paint()..color = const Color(0xFF9A622C),
      );
      for (int i = 0; i < 5; i += 1) {
        canvas.drawCircle(
          Offset(crate.left + 17 + i * 16, crate.top + 4 - (i % 2) * 5),
          9,
          Paint()
            ..color = i % 3 == 0
                ? const Color(0xFFF0B83E)
                : const Color(0xFFD34D36),
        );
      }
      final Path pennant = Path()
        ..moveTo(crate.left - 4, crate.top - 62)
        ..quadraticBezierTo(
          crate.left + 24 + sin(time * 2.6) * 7,
          crate.top - 51,
          crate.left + 54,
          crate.top - 63,
        )
        ..lineTo(crate.left + 50, crate.top - 30)
        ..quadraticBezierTo(
          crate.left + 20 + sin(time * 2.6) * 5,
          crate.top - 20,
          crate.left - 4,
          crate.top - 32,
        )
        ..close();
      canvas.drawPath(pennant, Paint()..color = const Color(0xFFEFC744));
      canvas.drawLine(
        Offset(crate.left - 4, crate.top - 68),
        Offset(crate.left - 4, crate.bottom),
        Paint()
          ..color = const Color(0xFF6C431F)
          ..strokeWidth = 5,
      );
    }
  }

  void _drawGardenRooms(Canvas canvas, Size size) {
    _drawGardenRoom(
      canvas,
      const Rect.fromLTWH(22, 500, 344, 520),
      seed: 17,
      fill: _night ? const Color(0xFF36513F) : const Color(0xFF8CCB72),
      border: const Color(0xFFECA7C3),
      label: 'BLOOM NOOK',
      labelCenter: const Offset(180, 518),
    );
    _drawGardenRoom(
      canvas,
      const Rect.fromLTWH(554, 500, 344, 620),
      seed: 29,
      fill: _night ? const Color(0xFF334D37) : const Color(0xFF77B65A),
      border: const Color(0xFFD6E675),
      label: 'ORCHARD WALK',
      labelCenter: const Offset(738, 518),
    );
    _drawGardenRoom(
      canvas,
      const Rect.fromLTWH(8, 1036, 512, 624),
      seed: 43,
      fill: _night ? const Color(0xFF294A43) : const Color(0xFF71B99A),
      border: const Color(0xFF8DDDE2),
      label: 'POND MEADOW',
      labelCenter: const Offset(250, 1060),
    );
    _drawGardenRoom(
      canvas,
      const Rect.fromLTWH(526, 1090, 372, 566),
      seed: 61,
      fill: _night ? const Color(0xFF4E4931) : const Color(0xFFAFC768),
      border: const Color(0xFFFFD775),
      label: 'KITCHEN GROVE',
      labelCenter: const Offset(720, 1108),
    );

    final Rect courtyard = Rect.fromCenter(
      center: const Offset(460, 742),
      width: 286,
      height: 226,
    );
    canvas.drawOval(
      courtyard,
      Paint()
        ..shader = RadialGradient(
          colors: _night
              ? const [Color(0xFF527057), Color(0xFF2F563D)]
              : const [Color(0xFFD6EFA0), Color(0xFF73AD54)],
        ).createShader(courtyard),
    );
    for (int i = 0; i < 20; i += 1) {
      final double angle = i * pi * 2 / 20;
      final Offset stone = Offset(
        courtyard.center.dx + cos(angle) * courtyard.width * 0.5,
        courtyard.center.dy + sin(angle) * courtyard.height * 0.5,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: stone,
          width: 30 + (i % 3) * 4,
          height: 18 + (i % 2) * 3,
        ),
        Paint()
          ..color = _winter ? const Color(0xFFE8EFE1) : const Color(0xFFB7A56D),
      );
    }
  }

  void _drawGardenRoom(
    Canvas canvas,
    Rect rect, {
    required int seed,
    required Color fill,
    required Color border,
    required String label,
    required Offset labelCenter,
  }) {
    final Path boundary = _organicZonePath(rect, seed, wobble: 0.045);
    canvas.drawPath(
      boundary,
      Paint()..color = fill.withValues(alpha: _winter ? 0.24 : 0.32),
    );
    canvas.drawPath(
      boundary,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..color = border.withValues(alpha: _winter ? 0.3 : 0.28),
    );
    _drawMapLabel(canvas, labelCenter, label);
  }

  void _drawPath(Canvas canvas, Size size) {
    final Path upper = Path()
      ..moveTo(460, 452)
      ..cubicTo(462, 520, 458, 558, 460, 610);
    final Path leftLoop = Path()
      ..moveTo(460, 600)
      ..cubicTo(354, 608, 306, 664, 320, 744)
      ..cubicTo(330, 812, 386, 842, 460, 852);
    final Path rightLoop = Path()
      ..moveTo(460, 600)
      ..cubicTo(566, 608, 614, 664, 600, 744)
      ..cubicTo(590, 812, 534, 842, 460, 852);
    final Path lower = Path()
      ..moveTo(460, 846)
      ..cubicTo(496, 962, 424, 1082, 460, 1212)
      ..cubicTo(504, 1370, 424, 1502, 482, size.height + 60);
    final Path bloomBranch = Path()
      ..moveTo(328, 690)
      ..cubicTo(270, 704, 232, 754, 208, 844);
    final Path orchardBranch = Path()
      ..moveTo(592, 690)
      ..cubicTo(650, 704, 688, 754, 706, 842);
    final Path meadowBranch = Path()
      ..moveTo(448, 1190)
      ..cubicTo(364, 1234, 322, 1320, 326, 1438);
    final Path groveBranch = Path()
      ..moveTo(474, 1190)
      ..cubicTo(568, 1226, 646, 1286, 696, 1390);

    void drawRoute(Path route, double width) {
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 24
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x88604E2E),
      );
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _winter ? const Color(0xFFE6E0CC) : const Color(0xFFD8C486),
      );
    }

    for (final Path route in [upper, leftLoop, rightLoop, lower]) {
      drawRoute(route, 88);
    }
    for (final Path route in [
      bloomBranch,
      orchardBranch,
      meadowBranch,
      groveBranch,
    ]) {
      drawRoute(route, 42);
    }

    for (int i = 0; i < 17; i += 1) {
      final double y = 490 + i * 72;
      final double x = 460 + sin(i * 1.13) * 22;
      final Rect stone = Rect.fromCenter(
        center: Offset(x, y),
        width: 54 + (i % 3) * 6,
        height: 25 + (i % 2) * 4,
      );
      canvas.save();
      canvas.translate(stone.center.dx, stone.center.dy);
      canvas.rotate(sin(i * 0.8) * 0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: stone.width,
            height: stone.height,
          ),
          const Radius.circular(14),
        ),
        Paint()
          ..color = _winter ? const Color(0xFFF8F5E8) : const Color(0xFFF0DEA3),
      );
      canvas.restore();
    }
  }

  void _drawGardenHeart(Canvas canvas) {
    final double pulse = sin(time * 1.7) * 0.018 + heartPulse * 0.055;
    final double scale = 0.8 + (heartLevel - 1) * 0.075 + pulse;
    final Offset center = const Offset(460, 690);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    final Rect glow = Rect.fromCenter(
      center: const Offset(0, 24),
      width: 260,
      height: 250,
    );
    canvas.drawOval(
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE88C).withValues(alpha: 0.08 + heartPulse * 0.18),
            Colors.transparent,
          ],
        ).createShader(glow),
    );

    final Path trunk = Path()
      ..moveTo(-18, 22)
      ..quadraticBezierTo(-28, 82, -24, 148)
      ..quadraticBezierTo(-2, 158, 24, 148)
      ..quadraticBezierTo(28, 82, 18, 22)
      ..close();
    canvas.drawPath(
      trunk,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6D4325), Color(0xFFB47B42), Color(0xFF674020)],
        ).createShader(const Rect.fromLTWH(-28, 20, 56, 140)),
    );
    final Paint branch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF81502B);
    canvas.drawLine(const Offset(-5, 58), const Offset(-64, -12), branch);
    canvas.drawLine(const Offset(7, 48), const Offset(66, -18), branch);

    final Path heart = Path()
      ..moveTo(0, 88)
      ..cubicTo(-22, 65, -116, 6, -104, -64)
      ..cubicTo(-96, -116, -32, -124, 0, -78)
      ..cubicTo(32, -124, 96, -116, 104, -64)
      ..cubicTo(116, 6, 22, 65, 0, 88)
      ..close();
    canvas.drawPath(
      heart,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _winter
              ? const [Color(0xFFB8D9AC), Color(0xFF729A6A)]
              : _night
              ? const [Color(0xFF5B9D63), Color(0xFF2F6744)]
              : const [Color(0xFF88D94E), Color(0xFF3D963F)],
        ).createShader(const Rect.fromLTWH(-112, -126, 224, 218)),
    );
    canvas.drawPath(
      heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0xFF2F6E35),
    );

    final Path innerHeart = Path()
      ..moveTo(0, 48)
      ..cubicTo(-12, 34, -54, 8, -50, -25)
      ..cubicTo(-46, -50, -16, -54, 0, -32)
      ..cubicTo(16, -54, 46, -50, 50, -25)
      ..cubicTo(54, 8, 12, 34, 0, 48)
      ..close();
    canvas.drawPath(
      innerHeart,
      Paint()
        ..color = Color.lerp(
          const Color(0xFFF08AAC),
          const Color(0xFFFFD45F),
          (heartLevel - 1) / 4,
        )!.withValues(alpha: 0.72),
    );

    final int bloomCount = 4 + heartLevel * 4;
    for (int i = 0; i < bloomCount; i += 1) {
      final double angle = i * 2.399;
      final double radius = 30 + (i % 4) * 17;
      final Offset bloom = Offset(
        cos(angle) * radius,
        sin(angle) * radius * 0.72 - 18 + sin(time * 2 + i) * 2,
      );
      canvas.drawCircle(
        bloom,
        5 + (i % 2).toDouble(),
        Paint()
          ..color = i.isEven
              ? const Color(0xFFFFA9C2)
              : const Color(0xFFFFE47A),
      );
      canvas.drawCircle(bloom, 2, Paint()..color = const Color(0xFFFFF7D6));
    }
    canvas.restore();

    final int moteCount = 4 + heartLevel * 2;
    for (int i = 0; i < moteCount; i += 1) {
      final double phase = (time * (0.12 + i * 0.006) + i * 0.13) % 1;
      final Offset mote = Offset(
        center.dx + sin(time + i * 1.4) * (80 + i * 3),
        804 - phase * 220,
      );
      canvas.drawCircle(
        mote,
        2.5 + (i % 3).toDouble(),
        Paint()
          ..color = const Color(
            0xFFFFE78A,
          ).withValues(alpha: (1 - phase) * 0.72),
      );
    }
  }

  void _drawPond(Canvas canvas, Size size) {
    final double capacity = (pondWater / 6).clamp(0.0, 1.0);
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
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              const Color(0xFF567C78),
              const Color(0xFF65D4E5),
              capacity,
            )!,
            Color.lerp(
              const Color(0xFF355D62),
              const Color(0xFF237FA8),
              capacity,
            )!,
            Color.lerp(
              const Color(0xFF294C4E),
              const Color(0xFF155A78),
              capacity,
            )!,
          ],
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
    final int rippleCount = 2 + pondWater;
    for (int i = 0; i < rippleCount; i += 1) {
      final double drift = sin(time * 1.4 + i * 0.8) * (4 + capacity * 8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            48 + i * 28 + drift,
            1194 + sin(time + i) * 18 + i * 26,
          ),
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
          center: Offset(
            18 + (i * 53) % 210 + sin(time * 0.9 + i) * 3,
            1152 + (i * 47) % 250 + cos(time * 0.8 + i) * 2,
          ),
          width: 34,
          height: 18,
        ),
        lily,
      );
    }

    if (pondWater > 0) {
      final Offset spring = const Offset(70, 1308);
      final Paint spray = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = const Color(0xFFC8F7FF).withValues(alpha: 0.72);
      for (int i = 0; i < pondWater; i += 1) {
        final double phase = (time * 1.2 + i / pondWater) % 1;
        final double angle = -1.12 + i * 0.16;
        final Offset drop =
            spring +
            Offset(
              cos(angle) * phase * 54,
              sin(angle) * phase * 58 + phase * phase * 62,
            );
        canvas.drawCircle(drop, 3 + capacity * 1.5, spray);
      }
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
        oldDelegate.lawnGrowth != lawnGrowth ||
        oldDelegate.pondWater != pondWater ||
        oldDelegate.marketReady != marketReady ||
        oldDelegate.heartLevel != heartLevel ||
        oldDelegate.heartPulse != heartPulse ||
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
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = switch (label) {
      'Move' => const Color(0xFF3C77B9),
      'Water' => const Color(0xFF2F86C1),
      'Build' => const Color(0xFF795027),
      _ => const Color(0xFF5A942F),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: selected ? 1.025 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? const [Color(0xFFFFFFDC), Color(0xFFFFE69A)]
                  : const [Color(0xFFFFF7DE), Color(0xFFEAD7A8)],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? const Color(0xFF79A93C)
                  : const Color(0xFFAD8951),
              width: selected ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x77000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: iconColor, size: 34),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFF3F382B),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -11,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE64B3C),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
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

// ignore: unused_element
class _GardenPlantTargetGlow extends StatelessWidget {
  // ignore: unused_element_parameter
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

// ignore: unused_element
class _GardenStreakChip extends StatelessWidget {
  const _GardenStreakChip({required this.streak, required this.tendedToday});

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

// ignore: unused_element
class _GardenForecastPill extends StatelessWidget {
  // ignore: unused_element_parameter
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
