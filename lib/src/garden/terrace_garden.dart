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

enum _Phase { edit, flowing, spill, won }

class TerraceGardenScreen extends StatefulWidget {
  const TerraceGardenScreen({
    super.key,
    this.onExit,
    this.onRotate,
    this.onRelease,
    this.onBloom,
  });
  final VoidCallback? onExit, onRotate, onRelease, onBloom;

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
  bool get _canTurn =>
      _ready && (_phase == _Phase.edit || _phase == _Phase.spill);
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
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
    _phase = won ? _Phase.won : _Phase.edit;
    _result = won ? traceTerrace(_game.stage, _game.turns) : null;
    _feedback = won
        ? 'The connected beds will stay in bloom.'
        : 'Follow the channel from the spring on the left.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase != _Phase.flowing) return;
    if (state == AppLifecycleState.resumed) {
      if (!_water.isAnimating) _water.forward();
    } else {
      _water.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _water.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _rotate(int cell) {
    if (!_canTurn || _game.stage.tiles[cell].fixed) return;
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
    if (!_canTurn) return;
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
    setState(() {
      _game.stageIndex = index;
      _restorePhase();
    });
    _save();
  }

  void _replay() {
    setState(() {
      _game.replay();
      _restorePhase();
    });
    _save();
  }

  void _release() {
    if (!_ready || _phase == _Phase.flowing) return;
    if (_phase == _Phase.won) {
      if (_game.stageIndex == terraceStages.length - 1) {
        _replay();
      } else {
        _go(_game.stageIndex + 1);
      }
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
                        bounds.maxWidth >= 580 && bounds.maxHeight < 480;
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
                      for (final (i, cleared) in _game.cleared.indexed)
                        if (cleared)
                          Image.asset(
                            '$_assetDir/${terraceStages[i].goals.last.crop}.webp',
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

  Widget _stageHeader() {
    return LayoutBuilder(
      builder: (context, bounds) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TERRACE ${_game.stageIndex + 1} OF ${terraceStages.length}',
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
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
        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, stage) in terraceStages.indexed)
              Semantics(
                label:
                    'Terrace ${i + 1}, ${stage.name}${_game.cleared[i]
                        ? ', in bloom'
                        : i > _game.unlocked
                        ? ', locked'
                        : ''}',
                selected: _game.stageIndex == i,
                button: true,
                child: IconButton(
                  key: ValueKey('terrace-stage-$i'),
                  onPressed: i <= _game.unlocked && _phase != _Phase.flowing
                      ? () => _go(i)
                      : null,
                  icon: ExcludeSemantics(
                    child: Container(
                      alignment: Alignment.center,
                      width: 29,
                      height: 29,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _game.stageIndex == i
                            ? _teal
                            : _game.cleared[i]
                            ? const Color(0xffd2debb)
                            : const Color(0xffe9e7d3),
                        border: Border.all(color: const Color(0xff9caa8f)),
                      ),
                      child: _game.cleared[i]
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: _game.stageIndex == i ? _cream : _ink,
                            )
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                color: _game.stageIndex == i ? _cream : _muted,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
        if (bounds.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(20) > 28) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, buttons],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            buttons,
          ],
        );
      },
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
    final last = _game.stageIndex == terraceStages.length - 1;
    final names = _game.stage.goals.map((goal) => goal.name).join(' and ');
    final objective = won
        ? (last ? 'All three terraces are in bloom.' : '$names in bloom.')
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
              if (!won || !last)
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
                onPressed: pouring ? null : _release,
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
                      : Icons.water_drop_outlined,
                  size: 18,
                ),
                label: Text(
                  pouring
                      ? 'Water flowing…'
                      : won
                      ? (last ? 'Play this terrace again' : 'Next terrace')
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
