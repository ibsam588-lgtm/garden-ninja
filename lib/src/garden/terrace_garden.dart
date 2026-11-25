import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terrace_model.dart';
import 'terrace_painter.dart';

const _cream = Color(0xfff5f0dc);
const _ink = Color(0xff254531);
const _muted = Color(0xff53644d);
const _teal = Color(0xff1b5952);
const _assetDir = 'assets/images/terrace';
const _directions = ['north', 'east', 'south', 'west'];

class _TerraceLevelPicker extends StatefulWidget {
  const _TerraceLevelPicker({required this.progress});
  final TerraceProgress progress;

  @override
  State<_TerraceLevelPicker> createState() => _TerraceLevelPickerState();
}

class _TerraceLevelPickerState extends State<_TerraceLevelPicker> {
  static const _pageSize = 10;
  late int _page = widget.progress.stageIndex ~/ _pageSize;

  @override
  Widget build(BuildContext context) {
    final game = widget.progress;
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, terraceStages.length);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Terrace levels',
                      style: TextStyle(
                        color: _ink,
                        fontFamily: 'serif',
                        fontSize: 26,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close levels',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${game.cleared.where((clear) => clear).length} of ${terraceStages.length} in bloom',
                style: const TextStyle(color: _muted),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Previous ten levels',
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    'Levels ${start + 1}–$end',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next ten levels',
                    onPressed: end < terraceStages.length
                        ? () => setState(() => _page++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, bounds) {
                  final columns = (bounds.maxWidth / 56).floor().clamp(1, 5);
                  final width = (bounds.maxWidth - (columns - 1) * 6) / columns;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = start; i < end; i++)
                        SizedBox(width: width, child: _levelButton(context, i)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelButton(BuildContext context, int i) {
    final game = widget.progress;
    final locked = i > game.unlocked;
    final active = game.stageIndex == i;
    final done = game.cleared[i];
    return Semantics(
      button: true,
      enabled: !locked,
      selected: active,
      label:
          'Level ${i + 1}, ${terraceStages[i].name}${locked
              ? ', locked'
              : done
              ? ', in bloom'
              : ''}',
      child: FilledButton(
        key: ValueKey('terrace-stage-$i'),
        onPressed: locked ? null : () => Navigator.pop(context, i),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          minimumSize: const Size(44, 55),
          backgroundColor: active ? _teal : const Color(0xffd6e4ca),
          foregroundColor: active ? _cream : _ink,
          disabledBackgroundColor: const Color(0xffe6e4d4),
          disabledForegroundColor: _muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                locked
                    ? Icons.lock_outline
                    : done
                    ? Icons.local_florist_outlined
                    : Icons.water_drop_outlined,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Phase { edit, flowing, spill, won, expired }

class TerraceGardenScreen extends StatefulWidget {
  const TerraceGardenScreen({
    super.key,
    this.onExit,
    this.onRotate,
    this.onRelease,
    this.onBloom,
    this.suspended = false,
    this.onRoundCompleted,
  });
  final VoidCallback? onExit, onRotate, onRelease, onBloom;
  final bool suspended;
  final ValueChanged<bool>? onRoundCompleted;

  @override
  State<TerraceGardenScreen> createState() => _TerraceGardenScreenState();
}

class _TerraceGardenScreenState extends State<TerraceGardenScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _dry = TerraceFlow(
    const [],
    List.filled(12, -1),
    const [],
    const [],
    false,
  );
  late final AnimationController _water = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && _phase == _Phase.flowing) {
        _settle();
      }
    });
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 210),
  );
  late final _animation = Listenable.merge([_water, _spin]);
  TerraceProgress _game = TerraceProgress();
  SharedPreferences? _prefs;
  TerraceGardenArt? _art;
  TerraceFlow? _result;
  _Phase _phase = _Phase.edit;
  int? _hinted, _rotating;
  String _feedback = '';
  bool _ready = false;
  bool _foreground = true;
  bool _choosingLevel = false;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _clockTick;
  int _startingMs = 0;
  int get _remainingMs => _game.remainingMs[_game.stageIndex];
  bool get _interactive => _foreground && !widget.suspended && !_choosingLevel;
  bool get _canTurn =>
      _ready &&
      _interactive &&
      (_phase == _Phase.edit || _phase == _Phase.spill);
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadArt();
  }

  Future<void> _loadArt() async {
    try {
      final art = await TerraceGardenArt.load();
      if (mounted) setState(() => _art = art);
    } catch (_) {
      // The painter also has a procedural version of every board element.
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _prefs = prefs;
      final saved = prefs.getString(TerraceProgress.storageKey);
      if (saved != null) _game = TerraceProgress.fromJson(jsonDecode(saved));
    } on Object {
      // Missing or invalid local progress starts a fresh terrace.
    }
    if (mounted) {
      setState(() {
        _ready = true;
        _restorePhase();
      });
      _syncPlayback();
    }
  }

  void _save() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(
      prefs
          .setString(TerraceProgress.storageKey, jsonEncode(_game.toJson()))
          .then<void>((saved) {
            if (!saved) _saveFailed();
          }, onError: (Object _) => _saveFailed()),
    );
  }

  void _saveFailed() {
    if (mounted) {
      setState(() => _feedback = 'Progress could not be saved on this device.');
    }
  }

  void _restorePhase() {
    _water.stop();
    _spin.stop();
    _hinted = _rotating = null;
    final won = _game.finished[_game.stageIndex];
    _phase = won
        ? _Phase.won
        : _remainingMs == 0
        ? _Phase.expired
        : _Phase.edit;
    _result = won ? traceTerrace(_game.stage, _game.turns) : null;
    _feedback = switch (_phase) {
      _Phase.won => 'The connected beds will stay in bloom.',
      _Phase.expired => 'Try this route again with a fresh clock.',
      _ => 'Tap the brass channels, then release the water.',
    };
  }

  // The stopwatch accounts for slow frames and app interruptions. The one-shot
  // timer wakes only when the displayed second changes.
  void _startClock() {
    if (_elapsed.isRunning || !_canTurn || _remainingMs <= 0) return;
    _startingMs = _remainingMs;
    _elapsed
      ..reset()
      ..start();
    _scheduleTick();
  }

  void _scheduleTick() {
    final remaining = _remainingMs;
    final delay = (remaining - 1) % 1000 + 1;
    _clockTick = Timer(Duration(milliseconds: delay), () {
      if (!mounted || !_canTurn) return;
      _game.remainingMs[_game.stageIndex] = math.max(
        0,
        math.min(remaining - delay, _startingMs - _elapsed.elapsedMilliseconds),
      );
      if (_remainingMs == 0) {
        _expire();
        return;
      }
      setState(() {});
      if ((_remainingMs / 1000).ceil() % 5 == 0) _save();
      _scheduleTick();
    });
  }

  void _recordTime() {
    if (!_elapsed.isRunning) return;
    _game.remainingMs[_game.stageIndex] = math.max(
      0,
      math.min(_remainingMs, _startingMs - _elapsed.elapsedMilliseconds),
    );
  }

  void _stopClock() {
    _recordTime();
    _clockTick?.cancel();
    _elapsed.stop();
  }

  void _expire() {
    if (_phase == _Phase.expired) return;
    _stopClock();
    _spin.stop();
    setState(() {
      _phase = _Phase.expired;
      _hinted = _rotating = null;
      _feedback = 'Try this route again with a fresh clock.';
    });
    _save();
    widget.onRoundCompleted?.call(false);
  }

  bool _hasTime() {
    if (!_canTurn) return false;
    _recordTime();
    if (_remainingMs > 0) return true;
    _expire();
    return false;
  }

  void _syncPlayback() {
    if (!_ready) return;
    if (!_interactive) {
      _stopClock();
      _water.stop();
      _save();
    } else if (_phase == _Phase.flowing) {
      if (!_water.isAnimating) _water.forward();
    } else if (_canTurn && _remainingMs == 0) {
      _expire();
    } else {
      _startClock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  @override
  void didUpdateWidget(TerraceGardenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suspended != oldWidget.suspended) _syncPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    if (_ready) _save();
    _water.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _rotate(int cell) {
    if (!_hasTime() || _game.stage.tiles[cell].fixed) return;
    setState(() {
      _game.rotate(cell);
      _phase = _Phase.edit;
      _result = null;
      _hinted = null;
      _rotating = _reduced ? null : cell;
      _feedback = 'Channel turned. Release water to test the route.';
    });
    if (_rotating != null) _spin.forward(from: 0);
    widget.onRotate?.call();
    _save();
  }

  void _hint() {
    if (!_hasTime()) return;
    final cell = terraceHint(_game.stage, _game.turns);
    setState(() {
      _hinted = cell;
      _feedback = cell == null
          ? 'All channels line up. Release the water.'
          : 'Turn the highlighted channel in row ${cell ~/ 4 + 1}, column ${cell % 4 + 1}.';
    });
  }

  void _go(int index) {
    if (!_ready ||
        index == _game.stageIndex ||
        index > _game.unlocked ||
        _phase == _Phase.flowing) {
      return;
    }
    _stopClock();
    setState(() {
      _game.stageIndex = index;
      _restorePhase();
    });
    _syncPlayback();
    _save();
  }

  void _replay() {
    _stopClock();
    setState(() {
      _game.replay();
      _restorePhase();
    });
    _syncPlayback();
    _save();
  }

  void _release() {
    if (!_ready || !_interactive || _phase == _Phase.flowing) return;
    if (_phase == _Phase.expired) {
      _replay();
      return;
    }
    if (_phase == _Phase.won) {
      if (_game.stageIndex == terraceStages.length - 1) {
        _replay();
      } else {
        _go(_game.stageIndex + 1);
      }
      return;
    }
    _stopClock();
    if (_remainingMs == 0) {
      _expire();
      return;
    }
    final result = traceTerrace(_game.stage, _game.turns);
    setState(() {
      _phase = _Phase.flowing;
      _result = result;
      _hinted = _rotating = null;
      _feedback = 'Watch where the stream goes.';
    });
    _spin.stop();
    widget.onRelease?.call();
    if (_reduced) {
      _settle();
    } else {
      final depth = math.max(0, result.depth.reduce(math.max));
      _water.duration = Duration(milliseconds: (depth + 2) * 150 + 280);
      _water.forward(from: 0);
    }
  }

  void _settle() {
    final result = _result!;
    setState(() {
      _phase = result.solved ? _Phase.won : _Phase.spill;
      if (result.solved) {
        _game.clear();
        _feedback = _game.stageIndex == terraceStages.length - 1
            ? 'Your hillside garden is flowering. Revisit a terrace to see its stream.'
            : 'The water reaches every bed. The next terrace is open.';
      } else if (result.spills.isNotEmpty) {
        final cell = result.spills.first.cell;
        _feedback =
            'Water spills at row ${cell ~/ 4 + 1}, column ${cell % 4 + 1}. Turn a channel and try again.';
      } else {
        _feedback =
            '${result.fed.length} of ${_game.stage.goals.length} beds watered. Check the branch to the dry bed.';
      }
    });
    if (result.solved) {
      _save();
      widget.onBloom?.call();
      widget.onRoundCompleted?.call(true);
    } else {
      _syncPlayback();
    }
  }

  void _exit() {
    if (widget.onExit case final exit?) {
      exit();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: widget.onExit == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onExit?.call();
      },
      child: Scaffold(
        backgroundColor: _cream,
        body: SafeArea(
          child: !_ready
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : LayoutBuilder(
                  builder: (context, bounds) {
                    final wide =
                        bounds.maxWidth >= 580 &&
                        bounds.maxWidth > bounds.maxHeight * 1.2;
                    if (wide) {
                      return Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _stageHeader(),
                                      const SizedBox(height: 6),
                                      _board(),
                                      _foot(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _hero(compact: true),
                                      _console(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _hero(compact: false),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  14,
                                  10,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _stageHeader(),
                                    const SizedBox(height: 10),
                                    _board(),
                                    _console(),
                                    _foot(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _hero({required bool compact}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _teal,
        image: DecorationImage(
          image: AssetImage('$_assetDir/landscape.webp'),
          fit: BoxFit.cover,
          alignment: Alignment(0, -.05),
        ),
        border: Border(bottom: BorderSide(color: Color(0xffa18a55), width: 3)),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xed15372e), Color(0x99213d2f), Color(0x11213d2f)],
          ),
        ),
        child: Stack(
          children: [
            if (_game.cleared.any((v) => v))
              Positioned(
                right: 4,
                bottom: 3,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (final crop in {
                        for (final (i, cleared) in _game.cleared.indexed)
                          if (cleared) terraceStages[i].goals.last.crop,
                      })
                        Image.asset(
                          '$_assetDir/$crop.webp',
                          width: compact ? 29 : 39,
                          height: compact ? 40 : 53,
                          fit: BoxFit.contain,
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(8, 5, 8, compact ? 8 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    key: const ValueKey('terrace-back'),
                    tooltip: 'Back to home',
                    onPressed: _exit,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xfffff4d9),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GARDEN NINJA',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.0,
                            fontWeight: FontWeight.bold,
                            color: Color(0xfff5d49b),
                          ),
                        ),
                        Text(
                          'Terrace Garden',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: compact ? 27 : 36,
                            height: 1.1,
                            color: const Color(0xfffff4d9),
                          ),
                        ),
                      ],
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

  Future<void> _chooseLevel() async {
    if (!_ready || !_interactive || _phase == _Phase.flowing) return;
    _choosingLevel = true;
    _syncPlayback();
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _cream,
      showDragHandle: true,
      builder: (context) => _TerraceLevelPicker(progress: _game),
    );
    if (!mounted) return;
    _choosingLevel = false;
    if (picked != null && picked != _game.stageIndex) {
      _go(picked);
    } else {
      _syncPlayback();
    }
  }

  Widget _stageHeader() {
    final secs = (_remainingMs / 1000).ceil();
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final low = secs <= 10 && _phase != _Phase.won;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                key: const ValueKey('terrace-levels'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: _teal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(48, 44),
                ),
                onPressed: _phase == _Phase.flowing || widget.suspended
                    ? null
                    : _chooseLevel,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: Text(
                  'Level ${_game.stageIndex + 1} of ${terraceStages.length}',
                ),
              ),
            ),
            Semantics(
              label:
                  'Time remaining, ${secs ~/ 60} minutes ${secs % 60} seconds',
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: low
                      ? const Color(0xffffe2cf)
                      : const Color(0xffdce8d6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 18,
                        color: low ? const Color(0xff923915) : _teal,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        time,
                        key: const ValueKey('terrace-clock'),
                        style: TextStyle(
                          color: low ? const Color(0xff923915) : _ink,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          _game.stage.name,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 27,
            height: 1.12,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _board() {
    final stage = _game.stage;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          'Irrigation board, three rows and four columns. Spring enters from the left in row ${stage.sourceRow + 1}. '
          '${stage.goals.map((g) => '${g.name} on the right in row ${g.row + 1}').join('. ')}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: AspectRatio(
          aspectRatio: 620 / 326,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final unit = bounds.maxWidth / 620;
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, _) => CustomPaint(
                        painter: TerraceGardenPainter(
                          stage: stage,
                          turns: List.of(_game.turns),
                          flow: _result ?? _dry,
                          waterProgress: _phase == _Phase.flowing
                              ? _water.value
                              : _result == null
                              ? 0
                              : 1,
                          highlightedCell: _hinted,
                          art: _art,
                          showMargins: true,
                          rotatingCell: _rotating,
                          turnProgress: _spin.value,
                        ),
                      ),
                    ),
                  ),
                  for (final (i, tile) in stage.tiles.indexed)
                    if (tile.shape != TerraceShape.land)
                      Positioned(
                        left: (100 + (i % 4) * 100) * unit,
                        top: (13 + (i ~/ 4) * 100) * unit,
                        width: unit * 100,
                        height: unit * 100,
                        child: Semantics(
                          label:
                              '${tile.fixed ? 'Fixed' : 'Rotate'} ${tile.shape.name} channel, '
                              'row ${i ~/ 4 + 1}, column ${i % 4 + 1}, openings '
                              '${terracePorts(tile.shape, _game.turns[i]).map((d) => _directions[d]).join(' and ')}'
                              '${_hinted == i ? ', highlighted' : ''}',
                          child: tile.fixed
                              ? const SizedBox.expand()
                              : Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: ValueKey('terrace-cell-$i'),
                                    onTap: _canTurn ? () => _rotate(i) : null,
                                    focusColor: const Color(0x88fff4ac),
                                    highlightColor: const Color(0x44fff4ac),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _console() {
    final won = _phase == _Phase.won, pouring = _phase == _Phase.flowing;
    final expired = _phase == _Phase.expired;
    final last = _game.stageIndex == terraceStages.length - 1;
    final names = _game.stage.goals.map((goal) => goal.name).join(' and ');
    final objective = won
        ? (last
              ? 'All ${terraceStages.length} terraces are in bloom.'
              : '$names in bloom.')
        : expired
        ? 'Time’s up'
        : 'Water $names.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 14, 3, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            objective,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Semantics(
            liveRegion: true,
            child: Text(
              _feedback,
              key: const ValueKey('terrace-feedback'),
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!expired && (!won || !last))
                OutlinedButton(
                  key: const ValueKey('terrace-hint'),
                  onPressed: pouring
                      ? null
                      : won
                      ? _replay
                      : _hint,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    minimumSize: const Size(68, 48),
                    side: const BorderSide(color: Color(0xffaaa584)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(won ? 'Replay' : 'Hint'),
                ),
              FilledButton.icon(
                key: const ValueKey('terrace-release'),
                onPressed: pouring || widget.suspended ? null : _release,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: _cream,
                  minimumSize: const Size(130, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  won
                      ? (last ? Icons.replay_rounded : Icons.east_rounded)
                      : expired
                      ? Icons.replay_rounded
                      : Icons.water_drop_outlined,
                  size: 18,
                ),
                label: Text(
                  pouring
                      ? 'Water flowing…'
                      : won
                      ? (last ? 'Play this terrace again' : 'Next terrace')
                      : expired
                      ? 'Retry level'
                      : 'Release water',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foot() {
    final i = _game.stageIndex, n = _game.moves[i], best = _game.best[i];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xffc8cbb5))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Wrap(
            spacing: 14,
            runSpacing: 5,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Text(
                '●  Tap brass channels to turn',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              Text(
                '$n turn${n == 1 ? '' : 's'}${best == null ? '' : ' · Best $best'}',
                key: const ValueKey('terrace-moves'),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
