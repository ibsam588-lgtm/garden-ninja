import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'harvest_art.dart';
import 'harvest_model.dart';

enum _Panel { none, plant, build, progress, pause, newTier, demo }

const _olive = Color(0xFF273020);
const _cream = Color(0xFFF4EDDF);
const _amber = Color(0xFFC3843C);

String _number(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

class HarvestGarden extends StatefulWidget {
  const HarvestGarden({
    super.key,
    required this.progress,
    required this.onExit,
    required this.onSave,
    this.onHarvest,
    this.suspended = false,
  });
  final HarvestProgress progress;
  final VoidCallback onExit;
  final VoidCallback onSave;
  final VoidCallback? onHarvest;
  final bool suspended;
  @override
  State<HarvestGarden> createState() => HarvestGardenState();
}

class HarvestGardenState extends State<HarvestGarden>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late HarvestRound _round;
  late Ticker _ticker;
  HarvestArt? _art;
  String? _artError;
  Duration? _lastFrame;
  double _frameAccumulator = 0;
  double _motion = 0;
  double _noticeUntil = 0;
  String? _notice;
  _Panel _panel = _Panel.none;
  GardenUpgrade _upgrade = GardenUpgrade.greenhouse;
  int _bed = 0;
  CropKind _crop = CropKind.strawberry;
  int? _pointerId;
  Offset? _pointer;
  Size _fieldSize = Size.zero;
  final List<GardenBurst> _bursts = [];
  int _lastReward = 0;
  bool _showResult = false;
  bool _reduceMotion = false;
  HarvestProgress get _progress => widget.progress;

  @override
  void initState() {
    super.initState();
    _round = HarvestRound(_progress);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick)..start();
    _loadArt();
  }

  Future<void> _loadArt() async {
    try {
      final art = await HarvestArt.load();
      if (mounted) {
        setState(() {
          _art = art;
          _artError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _artError =
              'Garden artwork could not load. Reopen the garden to retry.',
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant HarvestGarden oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suspended && !oldWidget.suspended) _pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pause();
      widget.onSave();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final previous = _lastFrame;
    _lastFrame = elapsed;
    if (previous == null) return;
    final dt = (elapsed - previous).inMicroseconds / 1000000;
    final wasRunning = _round.acceptsInput;
    if (!widget.suspended) _round.tick(dt);
    _motion += dt;
    _frameAccumulator += dt;
    if (wasRunning && _round.finished) {
      _finish();
      return;
    }
    if (_frameAccumulator < (_round.running ? 1 / 30 : 1 / 15)) return;
    _frameAccumulator = 0;
    _bursts.removeWhere((burst) => _motion - burst.born > .8);
    if (mounted) setState(() {});
  }

  void handleBack() {
    if (_panel == _Panel.pause) {
      _resume();
      return;
    }
    if (_panel != _Panel.none) {
      _closePanel();
      return;
    }
    if (_round.running) {
      _pause();
      return;
    }
    widget.onSave();
    widget.onExit();
  }

  void _notify(String text) {
    _notice = text;
    _noticeUntil = _motion + 3;
  }

  void _start() {
    if (_art == null || widget.suspended) return;
    setState(() {
      _round = HarvestRound(_progress)..start();
      _panel = _Panel.none;
      _lastReward = 0;
      _showResult = false;
      _pointerId = null;
      _pointer = null;
      _notify('Link matching ripe crops. Release to gather.');
    });
    widget.onSave();
  }

  void _pause() {
    if (!_round.running || _round.finished) return;
    setState(() {
      _round.pause();
      _panel = _Panel.pause;
      _pointer = null;
      _pointerId = null;
    });
  }

  void _resume() {
    if (widget.suspended) return;
    setState(() {
      _round.resume();
      _panel = _Panel.none;
    });
  }

  void _finish() {
    setState(() {
      _round.finish();
      _pointer = null;
      _pointerId = null;
      _lastReward = _round.earnings;
      _showResult = true;
      _upgrade = _progress.ownsUpgrade(GardenUpgrade.greenhouse)
          ? GardenUpgrade.terrace
          : GardenUpgrade.greenhouse;
      _panel = _Panel.build;
    });
    widget.onSave();
  }

  void _closePanel() {
    setState(() {
      _panel = _Panel.none;
      if (_round.finished) _round = HarvestRound(_progress);
      _showResult = false;
    });
  }

  void _selectBed(int bed) {
    if (bed < 0 || bed >= _progress.bedCount) return;
    setState(() {
      _bed = bed;
      _crop = _progress.crops[bed];
    });
  }

  void _open(_Panel panel) {
    if (_round.running) return;
    setState(() {
      _panel = panel;
      if (panel == _Panel.plant) _crop = _progress.crops[_bed];
      if (panel == _Panel.build) {
        _upgrade = _progress.ownsUpgrade(GardenUpgrade.greenhouse)
            ? GardenUpgrade.terrace
            : GardenUpgrade.greenhouse;
      }
    });
  }

  void _openUpgrade(GardenUpgrade upgrade) {
    if (_round.running) return;
    setState(() {
      _upgrade = upgrade;
      _panel = _Panel.build;
    });
  }

  void _sample(Offset from, Offset to) {
    final steps = max(1, ((to - from).distance / 5).ceil());
    for (var step = 1; step <= steps; step++) {
      final point = Offset.lerp(from, to, step / steps)!;
      final id = GardenGeometry.nearestCrop(point, _fieldSize, _round);
      if (id != null && _round.hit(id)) {
        if (!_reduceMotion) HapticFeedback.selectionClick();
      }
    }
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointerId != null || !_round.acceptsInput || _panel != _Panel.none) {
      return;
    }
    setState(() {
      _pointerId = event.pointer;
      _pointer = event.localPosition;
      _round.beginGesture();
      _sample(event.localPosition, event.localPosition);
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_pointerId != event.pointer || !_round.acceptsInput) return;
    setState(() {
      _sample(_pointer ?? event.localPosition, event.localPosition);
      _pointer = event.localPosition;
    });
  }

  void _release() {
    final points = _round.chain
        .map(
          (id) => GardenGeometry.plantRect(
            _round.crops.firstWhere((crop) => crop.id == id),
            _fieldSize,
            _progress.tier,
          ).center,
        )
        .toList();
    final result = _round.release();
    setState(() {
      for (final point in points) {
        _bursts.add(GardenBurst(point, _motion, result.count));
      }
      _pointer = null;
      _pointerId = null;
      if (result.orders > 0) {
        _lastReward = result.coins;
        _notify('Order complete · +${result.coins} coins');
      } else if (result.count > 1) {
        _notify('${result.count} crop chain');
      }
    });
    if (result.count > 0) {
      widget.onHarvest?.call();
      widget.onSave();
    }
  }

  void _semanticHarvest(int id) {
    if (!_round.acceptsInput) return;
    _round.beginGesture();
    _round.hit(id);
    _release();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _olive,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _fieldSize = constraints.biggest;
              return Stack(
                key: const ValueKey('harvest-garden'),
                fit: StackFit.expand,
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerUp: (event) {
                      if (_pointerId == event.pointer) _release();
                    },
                    onPointerCancel: (event) {
                      if (_pointerId == event.pointer) {
                        setState(() {
                          _round.cancelGesture();
                          _pointerId = null;
                          _pointer = null;
                        });
                      }
                    },
                    child: RepaintBoundary(
                      child: _art == null
                          ? Image.asset(
                              'assets/images/backgrounds/harvest_courtyard.png',
                              fit: BoxFit.fill,
                            )
                          : CustomPaint(
                              painter: HarvestScenePainter(
                                art: _art!,
                                round: _round,
                                motion: _motion,
                                bursts: _bursts,
                                reducedMotion: _reduceMotion,
                                pointer: _pointer,
                                selectedBed: _panel == _Panel.plant
                                    ? _bed
                                    : null,
                                preview: _panel == _Panel.build
                                    ? _upgrade
                                    : null,
                              ),
                            ),
                    ),
                  ),
                  if (_round.acceptsInput)
                    for (final crop in _round.crops)
                      Positioned.fromRect(
                        rect: GardenGeometry.plantHitRect(
                          crop,
                          _fieldSize,
                          _progress.tier,
                        ),
                        child: Semantics(
                          key: ValueKey('harvest-crop-${crop.id}'),
                          label:
                              '${crop.kind.label}, ${crop.isRipe(_round.elapsed) ? 'ripe' : 'growing'}',
                          button: true,
                          onTap: () => _semanticHarvest(crop.id),
                          child: const IgnorePointer(child: SizedBox.expand()),
                        ),
                      ),
                  if (!_round.running && _panel == _Panel.none) ...[
                    if (_progress.greenhouse > 0)
                      _buildingHotspot(GardenUpgrade.greenhouse),
                    if (_progress.terrace > 0)
                      _buildingHotspot(GardenUpgrade.terrace),
                  ],
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .19, .70, 1],
                          colors: [
                            Color(0x35000000),
                            Colors.transparent,
                            Colors.transparent,
                            Color(0x550D170D),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _header(),
                            const SizedBox(height: 8),
                            _order(),
                            if (!_round.running &&
                                !_showResult &&
                                _panel != _Panel.build) ...[
                              const SizedBox(height: 8),
                              _tierChip(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_round.chain.isNotEmpty && _pointer != null)
                    Positioned(
                      left: (_pointer!.dx - 70).clamp(
                        10.0,
                        max(10.0, _fieldSize.width - 155),
                      ),
                      top: (_pointer!.dy - 80).clamp(
                        145.0,
                        max(145.0, _fieldSize.height - 180),
                      ),
                      child: IgnorePointer(
                        child: _darkPanel(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${_round.chain.length} CHAIN',
                                style: _text(18, weight: FontWeight.w700),
                              ),
                              Text('Release to harvest', style: _text(11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_panel == _Panel.demo) _demoOverlay(),
                  if (_panel == _Panel.none)
                    SafeArea(
                      top: false,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _bottomControls(),
                        ),
                      ),
                    ),
                  if (_notice != null &&
                      _noticeUntil > _motion &&
                      _panel == _Panel.none &&
                      _round.chain.isEmpty)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: _round.running ? 84 : 195,
                      child: IgnorePointer(
                        child: Center(
                          child: _darkPanel(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              _notice!,
                              textAlign: TextAlign.center,
                              style: _text(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_art == null && _panel == _Panel.none)
                    Center(
                      child: _darkPanel(
                        child: Text(
                          _artError ?? 'Preparing your garden…',
                          textAlign: TextAlign.center,
                          style: _text(14),
                        ),
                      ),
                    ),
                  if (_panel != _Panel.none) _sheet(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      _darkPanel(
        padding: EdgeInsets.zero,
        child: IconButton(
          key: const ValueKey('harvest-back'),
          tooltip: _round.running ? 'Pause harvest' : 'Back',
          onPressed: handleBack,
          icon: const Icon(Icons.arrow_back_rounded, color: _cream),
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          padding: EdgeInsets.zero,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          _round.running ? 'Harvest' : 'My Garden',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _text(
            21,
            weight: FontWeight.w700,
            shadows: const [Shadow(blurRadius: 10, color: Colors.black)],
          ),
        ),
      ),
      _darkPanel(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_round.running)
              const Icon(Icons.timer_outlined, size: 21, color: _cream)
            else
              const _Coin(size: 23),
            const SizedBox(width: 7),
            Text(
              _round.running
                  ? '${(_round.secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_round.secondsLeft % 60).toString().padLeft(2, '0')}'
                  : _number(_progress.coins),
              key: ValueKey(_round.running ? 'harvest-timer' : 'harvest-coins'),
              style: _text(20, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _order() => _darkPanel(
    child: Row(
      children: [
        HarvestSprite(art: _art, index: _round.orderKind.sprite, size: 37),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _showResult ? 'HARVEST COMPLETE' : 'MARKET ORDER',
                style: _text(10, color: const Color(0xFFE3D9B8), spacing: 1.2),
              ),
              const SizedBox(height: 2),
              Text(
                _showResult
                    ? '${_round.orders} orders · best chain ${_round.bestChain}'
                    : '${_round.orderKind.label}  ${_round.collected}/${_round.orderTarget}',
                key: const ValueKey('harvest-order'),
                style: _text(14, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Container(height: 32, width: 1, color: _cream.withValues(alpha: .22)),
        const SizedBox(width: 10),
        const _Coin(size: 20),
        const SizedBox(width: 5),
        Text(
          '+${_showResult ? _lastReward : _round.orderReward}',
          style: _text(17, weight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _tierChip() => GestureDetector(
    key: const ValueKey('harvest-progress'),
    onTap: () => _open(_Panel.progress),
    child: Semantics(
      button: true,
      excludeSemantics: true,
      label:
          'Garden ${_progress.tier}, ${_progress.tierName}, ${(_progress.tierProgress * 100).round()} percent complete',
      onTap: () => _open(_Panel.progress),
      child: _darkPanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              _progress.tierComplete
                  ? Icons.workspace_premium_outlined
                  : Icons.terrain_outlined,
              color: const Color(0xFFECC185),
              size: 18,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Garden ${_progress.tier} · ${_progress.tierName}',
                style: _text(11),
              ),
            ),
            SizedBox(
              width: 50,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress.tierProgress,
                  minHeight: 4,
                  color: const Color(0xFFEDBC73),
                  backgroundColor: _cream.withValues(alpha: .18),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: _cream, size: 17),
          ],
        ),
      ),
    ),
  );

  Widget _buildingHotspot(GardenUpgrade upgrade) {
    final greenhouse = upgrade == GardenUpgrade.greenhouse;
    final level = greenhouse ? _progress.greenhouse : _progress.terrace;
    final artRect = greenhouse
        ? GardenGeometry.greenhouseRect(_fieldSize, level: level)
        : GardenGeometry.terraceRect(_fieldSize, level: level);
    return Positioned.fromRect(
      rect: artRect.inflate(10),
      child: Semantics(
        key: ValueKey('harvest-building-${upgrade.name}'),
        button: true,
        label:
            '${greenhouse ? 'Greenhouse' : 'Terrace'}, level $level. Tap to upgrade.',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _openUpgrade(upgrade),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _olive.withValues(alpha: .88),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE7BB77)),
              ),
              child: Text(
                '${greenhouse ? 'Greenhouse' : 'Terrace'} · L$level',
                style: _text(10, weight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoOverlay() {
    final demoCrops = _round.crops.take(4).toList();
    final points = demoCrops
        .map(
          (crop) =>
              GardenGeometry.plantRect(crop, _fieldSize, _progress.tier).center,
        )
        .toList();
    final cycle = (_motion % 5.5) / 5.5;
    final progress = ((cycle - .08) / .72).clamp(0.0, 1.0);
    final scaled = progress * (points.length - 1);
    final segment = scaled.floor().clamp(0, points.length - 2);
    final point = Offset.lerp(
      points[segment],
      points[segment + 1],
      scaled - segment,
    )!;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DemoTrailPainter(points: points, progress: progress),
            ),
          ),
          Positioned(
            left: point.dx - 24,
            top: point.dy - 24,
            child: Transform.rotate(
              angle: -.20 + sin(_motion * 4) * .05,
              child: Container(
                key: const ValueKey('harvest-demo-hand'),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cream.withValues(alpha: .94),
                  border: Border.all(color: _amber, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 10),
                  ],
                ),
                child: const Icon(
                  Icons.touch_app_rounded,
                  color: _olive,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    if (_round.running) {
      return _darkPanel(
        child: Row(
          children: [
            const Icon(
              Icons.gesture_rounded,
              size: 19,
              color: Color(0xFFE4B874),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Link ripe crops. Avoid green fruit.',
                textAlign: TextAlign.center,
                style: _text(12),
              ),
            ),
            IconButton(
              key: const ValueKey('harvest-pause'),
              tooltip: 'Pause harvest',
              onPressed: _pause,
              icon: const Icon(Icons.pause, color: _cream, size: 19),
              constraints: const BoxConstraints.tightFor(width: 32, height: 30),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _darkPanel(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _progress.tierComplete
                      ? (_progress.finalTier
                            ? 'Grand Estate complete · Keep growing'
                            : 'Next garden ready to unlock')
                      : 'Next upgrade: ${_number(_progress.upgradeCost)} coins',
                  textAlign: TextAlign.center,
                  style: _text(12),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('harvest-demo'),
                onTap: () => _open(_Panel.demo),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_circle_outline,
                        size: 17,
                        color: _cream,
                      ),
                      const SizedBox(width: 4),
                      Text('Demo', style: _text(11, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _action(
          'Start harvest',
          _art == null ? null : _start,
          key: 'harvest-start',
          amber: true,
          subtitle: '60-second challenge',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _action(
                'Plant',
                () => _open(_Panel.plant),
                key: 'harvest-plant',
                icon: Icons.spa_outlined,
                compact: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _action(
                'Build',
                () => _open(_Panel.build),
                key: 'harvest-build',
                icon: Icons.handyman_outlined,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheet() {
    final isPause = _panel == _Panel.pause;
    return Stack(
      children: [
        if (isPause ||
            _panel == _Panel.progress ||
            _panel == _Panel.newTier ||
            _panel == _Panel.demo)
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: .32)),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: ValueKey('harvest-sheet-${_panel.name}'),
            constraints: BoxConstraints(
              maxHeight:
                  _fieldSize.height *
                  (_panel == _Panel.progress
                      ? .74
                      : _panel == _Panel.demo
                      ? .70
                      : _panel == _Panel.plant
                      ? .70
                      : isPause
                      ? .52
                      : .61),
            ),
            decoration: const BoxDecoration(
              color: _cream,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 24,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: switch (_panel) {
                  _Panel.plant => _plantSheet(),
                  _Panel.build => _buildSheet(),
                  _Panel.progress => _progressSheet(),
                  _Panel.pause => _pauseSheet(),
                  _Panel.newTier => _newTierSheet(),
                  _Panel.demo => _demoSheet(),
                  _Panel.none => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sheetTitle(String title, {String? subtitle}) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: _text(20, color: _olive, weight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const ValueKey('harvest-sheet-close'),
            tooltip: 'Close',
            onPressed: _panel == _Panel.pause ? _resume : _closePanel,
            icon: const Icon(Icons.close, color: _olive, size: 20),
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              subtitle,
              style: _text(12, color: const Color(0xFF62634F)),
            ),
          ),
        ),
      const SizedBox(height: 6),
    ],
  );

  Widget _buildSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetTitle(
        'Choose your next upgrade',
        subtitle: _showResult
            ? 'Earned ${_round.earnings} coins · ${_round.orders} orders completed'
            : 'Garden ${_progress.tier} · Every level changes the building',
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _upgradeCard(GardenUpgrade.greenhouse)),
          const SizedBox(width: 10),
          Expanded(child: _upgradeCard(GardenUpgrade.terrace)),
        ],
      ),
      const SizedBox(height: 12),
      _action(
        _progress.ownsUpgrade(_upgrade)
            ? 'Upgraded for this garden'
            : _progress.coins < _progress.upgradeCost
            ? 'Need ${_number(_progress.upgradeCost - _progress.coins)} more coins'
            : '${_progress.tier == 1 ? 'Build' : 'Upgrade'} ${_upgrade.name}',
        !_progress.ownsUpgrade(_upgrade) &&
                _progress.coins >= _progress.upgradeCost
            ? () {
                if (_progress.buyUpgrade(_upgrade)) {
                  setState(() {
                    _notify(
                      '${_upgrade == GardenUpgrade.greenhouse ? 'Greenhouse' : 'Terrace'} complete',
                    );
                    _round = HarvestRound(_progress);
                    _panel = _Panel.none;
                    _showResult = false;
                  });
                  widget.onSave();
                }
              }
            : null,
        key: 'harvest-buy-upgrade',
      ),
      const SizedBox(height: 5),
      TextButton(
        onPressed: () => setState(() => _panel = _Panel.progress),
        child: const Text(
          'See garden progression',
          style: TextStyle(color: _olive),
        ),
      ),
    ],
  );

  Widget _upgradeCard(GardenUpgrade upgrade) {
    final selected = _upgrade == upgrade;
    final greenhouse = upgrade == GardenUpgrade.greenhouse;
    final owned = _progress.ownsUpgrade(upgrade);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey('harvest-upgrade-${upgrade.name}'),
        onTap: () => setState(() => _upgrade = upgrade),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF9F3E8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _amber : const Color(0xFFCCC4B2),
              width: selected ? 2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    height: 104,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFD4D1B9), Color(0xFFE7DBC4)],
                      ),
                    ),
                    child: Center(
                      child: Transform.scale(
                        scale: _reduceMotion
                            ? 1
                            : 1 +
                                  sin(_motion * 1.5 + (greenhouse ? 0 : 1)) *
                                      .012,
                        child: HarvestSprite(
                          art: _art,
                          index: owned
                              ? (greenhouse
                                    ? _progress.greenhouse
                                    : _progress.terrace)
                              : _progress.tier,
                          sheet: greenhouse
                              ? HarvestSpriteSheet.greenhouse
                              : HarvestSpriteSheet.terrace,
                          size: 120,
                        ),
                      ),
                    ),
                  ),
                  if (selected || owned)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: owned ? _olive : _amber,
                          shape: BoxShape.circle,
                          border: Border.all(color: _cream, width: 1.5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(Icons.check, size: 17, color: _cream),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  children: [
                    Text(
                      greenhouse ? 'Greenhouse' : 'Terrace',
                      style: _text(17, color: _olive, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      greenhouse
                          ? _greenhouseBenefit(owned)
                          : (_progress.terrace == 0
                                ? 'Add 2 planting beds'
                                : 'Faster crop regrowth'),
                      textAlign: TextAlign.center,
                      style: _text(11, color: _olive),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!owned) const _Coin(size: 17),
                        if (!owned) const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            owned
                                ? 'Level ${_progress.tier} complete'
                                : '${_number(_progress.upgradeCost)} coins',
                            style: _text(
                              12,
                              color: _olive,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plantSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetTitle(
        'Plant your garden',
        subtitle: 'Group matching crops for longer harvest chains.',
      ),
      Row(
        children: [
          Text(
            'BED',
            style: _text(
              10,
              color: _olive,
              weight: FontWeight.w700,
              spacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          for (var bed = 0; bed < _progress.bedCount; bed++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  key: ValueKey('harvest-bed-$bed'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _selectBed(bed),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _bed == bed ? _olive : const Color(0xFFE6DECE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${bed + 1}',
                      style: _text(14, color: _bed == bed ? _cream : _olive),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _bedMap(),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 12) / 3;
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final crop in CropKind.values)
                SizedBox(width: width, child: _cropCard(crop)),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      _action('Plant ${_crop.label.toLowerCase()}', () {
        if (_progress.plant(_bed, _crop)) {
          setState(() {
            _round = HarvestRound(_progress);
            _panel = _Panel.none;
            _notify(
              'Bed ${_bed + 1} planted with ${_crop.label.toLowerCase()}',
            );
          });
          widget.onSave();
        }
      }, key: 'harvest-plant-confirm'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              'Bed ${_bed + 1} · Level ${_progress.beds[_bed]}/2\n'
              '${_progress.beds[_bed] == 2 ? 'Two crops per harvest' : 'Upgrade for double yield'}',
              style: _text(11, color: _olive),
            ),
          ),
          TextButton(
            key: const ValueKey('harvest-improve-bed'),
            onPressed:
                _progress.beds[_bed] < 2 && _progress.coins >= _progress.bedCost
                ? () {
                    if (_progress.improveBed(_bed)) {
                      setState(() {});
                      widget.onSave();
                    }
                  }
                : null,
            child: Text(
              _progress.beds[_bed] >= 2
                  ? 'Fully upgraded'
                  : 'Upgrade · ${_progress.bedCost}',
              style: TextStyle(
                color:
                    _progress.beds[_bed] < 2 &&
                        _progress.coins >= _progress.bedCost
                    ? _olive
                    : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _bedMap() {
    const positions = <Offset>[
      Offset(.38, .18),
      Offset(.13, .50),
      Offset(.47, .58),
      Offset(.76, .48),
      Offset(.37, .85),
      Offset(.70, .84),
    ];
    return Semantics(
      label: 'Bed ${_bed + 1} selected',
      liveRegion: true,
      child: Container(
        key: const ValueKey('harvest-bed-map'),
        height: 116,
        decoration: BoxDecoration(
          color: const Color(0xFFE4E4C9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF89935F), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 10,
                  top: 7,
                  child: Text(
                    'BED ${_bed + 1} SELECTED',
                    key: ValueKey('harvest-bed-selected-$_bed'),
                    style: _text(
                      11,
                      color: _olive,
                      weight: FontWeight.w800,
                      spacing: .7,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 7,
                  child: Text(
                    _progress.crops[_bed].label,
                    style: _text(
                      10,
                      color: const Color(0xFF616844),
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var bed = 0; bed < _progress.bedCount; bed++)
                  Positioned(
                    left: (positions[bed].dx * constraints.maxWidth - 23).clamp(
                      4.0,
                      constraints.maxWidth - 50,
                    ),
                    top: 25 + positions[bed].dy * 66,
                    child: Semantics(
                      button: true,
                      selected: _bed == bed,
                      label: 'Select bed ${bed + 1}',
                      child: InkWell(
                        key: ValueKey('harvest-bed-map-$bed'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _selectBed(bed),
                        child: Container(
                          width: 46,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _bed == bed
                                ? const Color(0xFFFFC55B)
                                : const Color(0xFF6F793E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _bed == bed
                                  ? const Color(0xFFFFF1B0)
                                  : const Color(0xFF414B27),
                              width: _bed == bed ? 3 : 1.5,
                            ),
                            boxShadow: _bed == bed
                                ? const [
                                    BoxShadow(
                                      color: Color(0x99FFB52F),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '${bed + 1}',
                            style: _text(
                              13,
                              color: _bed == bed ? _olive : _cream,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _progressSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetTitle(
        'Garden progression',
        subtitle: 'Build, improve your beds, then begin a new garden.',
      ),
      Row(
        children: [
          for (var i = 1; i <= gardenTierNames.length; i++)
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _progress.tier
                          ? _amber
                          : i < _progress.tier
                          ? _olive
                          : const Color(0xFFDED6C6),
                    ),
                    child: i < _progress.tier
                        ? const Icon(Icons.check, color: _cream, size: 18)
                        : Text(
                            '$i',
                            style: _text(
                              14,
                              color: i == _progress.tier ? _cream : _olive,
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Garden ${_progress.tier} · ${_progress.tierName}',
          style: _text(18, color: _olive, weight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: _progress.tierProgress,
          minHeight: 7,
          color: _amber,
          backgroundColor: const Color(0xFFDDD5C6),
        ),
      ),
      const SizedBox(height: 12),
      _requirement(
        'Greenhouse level ${_progress.tier}',
        _progress.greenhouse >= _progress.tier,
        () => setState(() {
          _panel = _Panel.build;
          _upgrade = GardenUpgrade.greenhouse;
        }),
      ),
      _requirement(
        'Terrace level ${_progress.tier}',
        _progress.terrace >= _progress.tier,
        () => setState(() {
          _panel = _Panel.build;
          _upgrade = GardenUpgrade.terrace;
        }),
      ),
      _requirement(
        'Improve 4 main beds  ·  ${_progress.upgradedBeds}/4',
        _progress.upgradedBeds == 4,
        () {
          _bed = _progress.beds
              .take(4)
              .toList()
              .indexWhere((level) => level < 2);
          if (_bed < 0) _bed = 0;
          _crop = _progress.crops[_bed];
          setState(() => _panel = _Panel.plant);
        },
      ),
      _requirement(
        'Complete market orders  ·  ${min(_progress.tierOrders, _progress.targetOrders)}/${_progress.targetOrders}',
        _progress.tierOrders >= _progress.targetOrders,
        _closePanel,
      ),
      const SizedBox(height: 12),
      Text(
        _progress.finalTier
            ? 'Complete the Grand Estate and keep improving your best harvest.'
            : 'Next: ${gardenTierNames[_progress.tier]}. Start with fresh beds; keep your coins, landmarks and rare crops.',
        style: _text(12, color: const Color(0xFF64604F)),
      ),
      const SizedBox(height: 12),
      _action(
        _progress.finalTier
            ? (_progress.tierComplete
                  ? 'Grand Estate complete'
                  : 'Complete this garden')
            : !_progress.tierComplete
            ? 'Finish the upgrades above'
            : _progress.coins < _progress.advanceCost
            ? 'Need ${_progress.advanceCost - _progress.coins} more coins'
            : 'Begin next garden · ${_progress.advanceCost}',
        _progress.tierComplete &&
                !_progress.finalTier &&
                _progress.coins >= _progress.advanceCost
            ? () {
                if (_progress.advanceTier()) {
                  setState(() {
                    _round = HarvestRound(_progress);
                    _bed = 0;
                    _panel = _Panel.newTier;
                  });
                  widget.onSave();
                }
              }
            : null,
        key: 'harvest-advance-tier',
        amber: true,
      ),
    ],
  );

  Widget _requirement(String text, bool complete, VoidCallback onTap) =>
      InkWell(
        onTap: complete ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(
                complete ? Icons.check_circle : Icons.radio_button_unchecked,
                color: complete
                    ? const Color(0xFF537044)
                    : const Color(0xFFA79A83),
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(text, style: _text(13, color: _olive)),
              ),
              if (!complete)
                const Icon(Icons.chevron_right, size: 18, color: _olive),
            ],
          ),
        ),
      );

  Widget _pauseSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetTitle(
        'Harvest paused',
        subtitle:
            '${_round.secondsLeft} seconds left · ${_round.earnings} coins earned',
      ),
      _action('Keep harvesting', _resume, key: 'harvest-resume', amber: true),
      const SizedBox(height: 10),
      _action('Finish harvest', _finish, key: 'harvest-finish'),
      const SizedBox(height: 8),
      Text(
        'Your completed orders and coins are already saved.',
        style: _text(11, color: _olive),
      ),
    ],
  );

  Widget _newTierSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.terrain_outlined, size: 44, color: _amber),
      const SizedBox(height: 8),
      Text(
        'GARDEN ${_progress.tier}',
        style: _text(12, color: _olive, spacing: 2),
      ),
      const SizedBox(height: 7),
      Text(
        _progress.tierName,
        style: _text(27, color: _olive, weight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Text(
        'Fresh planting beds. Bigger orders.\n${_progress.newestCrop.label} are ready to plant; your upgraded landmarks carry forward.',
        textAlign: TextAlign.center,
        style: _text(13, color: _olive),
      ),
      const SizedBox(height: 20),
      _action(
        'Start planting',
        () => setState(() {
          _panel = _Panel.plant;
          _crop = _progress.crops[0];
        }),
        key: 'harvest-new-tier-plant',
        amber: true,
      ),
    ],
  );

  Widget _demoSheet() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetTitle(
        'How harvesting works',
        subtitle: 'Watch the hand connect nearby matching crops.',
      ),
      Row(
        children: [
          _demoStep('1', 'Touch a ripe crop'),
          const Icon(Icons.chevron_right, color: _amber),
          _demoStep('2', 'Drag through matches'),
          const Icon(Icons.chevron_right, color: _amber),
          _demoStep('3', 'Release to collect'),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        'Large touch areas make every crop easier to reach. Green fruit and a different crop stop the chain.',
        textAlign: TextAlign.center,
        style: _text(12, color: _olive),
      ),
      const SizedBox(height: 14),
      _action(
        'Try a guided harvest',
        _start,
        key: 'harvest-demo-start',
        amber: true,
      ),
    ],
  );

  Widget _cropCard(CropKind crop) {
    final unlocked = _progress.isCropUnlocked(crop);
    return Semantics(
      button: true,
      enabled: unlocked,
      selected: _crop == crop,
      label: unlocked
          ? crop.label
          : '${crop.label}, unlock with greenhouse level ${crop.greenhouseLevel}',
      child: GestureDetector(
        key: ValueKey('harvest-plant-${crop.name}'),
        onTap: unlocked ? () => setState(() => _crop = crop) : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: unlocked ? 1 : .45,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF6ED),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _crop == crop ? _amber : const Color(0xFFD5CBB7),
                width: _crop == crop ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Transform.scale(
                  scale: _reduceMotion
                      ? 1
                      : 1 + sin(_motion * 1.7 + crop.index) * .018,
                  child: HarvestSprite(art: _art, index: crop.sprite, size: 54),
                ),
                Text(
                  crop.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(10, color: _olive, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked ? 'Ready' : 'Greenhouse L${crop.greenhouseLevel}',
                  style: _text(8.5, color: const Color(0xFF726B58)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoStep(String number, String label) => Expanded(
    child: Column(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _amber,
          ),
          child: Text(number, style: _text(13, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: _text(10, color: _olive, weight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _darkPanel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(11),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xEC3A422F), Color(0xF51E271B)],
      ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF74765A), width: .8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  Widget _action(
    String label,
    VoidCallback? onTap, {
    required String key,
    bool amber = false,
    bool compact = false,
    String? subtitle,
    IconData? icon,
  }) => Semantics(
    button: true,
    enabled: onTap != null,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Opacity(
          opacity: onTap == null ? .53 : 1,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: amber
                    ? const Color(0xFFE2AE70)
                    : const Color(0xFF7A7E5D),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: amber
                    ? const [Color(0xFFBD834A), Color(0xFF855020)]
                    : const [Color(0xFF404B33), Color(0xFF202C1B)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 46 : 51),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: subtitle != null ? 9 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: _cream, size: 21),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: _text(
                              compact
                                  ? 14
                                  : subtitle != null
                                  ? 21
                                  : 16,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: _text(12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String _greenhouseBenefit(bool owned) {
    final level = owned ? _progress.greenhouse : _progress.tier;
    final unlocked = CropKind.values
        .where((crop) => crop.greenhouseLevel == level)
        .firstOrNull;
    if (unlocked != null) return 'Unlock ${unlocked.label.toLowerCase()}';
    return 'Bigger rare-crop rewards';
  }

  TextStyle _text(
    double size, {
    Color color = _cream,
    FontWeight weight = FontWeight.w400,
    double? spacing,
    List<Shadow>? shadows,
  }) => TextStyle(
    fontFamily: 'Arial',
    fontSize: size,
    height: 1.17,
    color: color,
    fontWeight: weight,
    letterSpacing: spacing,
    shadows: shadows,
  );
}

class _DemoTrailPainter extends CustomPainter {
  const _DemoTrailPainter({required this.points, required this.progress});
  final List<Offset> points;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    final scaled = progress * (points.length - 1);
    final completeSegments = scaled.floor();
    for (var i = 1; i <= completeSegments && i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    if (completeSegments < points.length - 1) {
      final partial = scaled - completeSegments;
      final point = Offset.lerp(
        points[completeSegments],
        points[completeSegments + 1],
        partial,
      )!;
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x66FFB938)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFE8A7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DemoTrailPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.points != points;
}

class _Coin extends StatelessWidget {
  const _Coin({this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFECB0), Color(0xFFE6AA31), Color(0xFFAC6A1A)],
      ),
      border: Border.all(color: const Color(0xFFFFE2A0), width: 1.2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Container(
      width: size * .67,
      height: size * .67,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFAE772A), width: .8),
      ),
    ),
  );
}
