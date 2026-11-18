import 'dart:math';
import 'dart:ui';

enum PlanterCrop {
  bell(125, .39, .69, Color(0xFF465D39), Color(0xFF77BADC)),
  daisy(133, .31, .685, Color(0xFF7B8B40), Color(0xFFF6E6C5)),
  blossom(130, .31, .62, Color(0xFF8B9347), Color(0xFFE9A2A1));

  const PlanterCrop(
    this.sourceWidth,
    this.firstCut,
    this.secondCut,
    this.stemColor,
    this.petalColor,
  );

  static const sourceHeight = 152;
  static const assetDirectory = 'assets/images/sprites/slicer';

  final int sourceWidth;
  final double firstCut;
  final double secondCut;
  final Color stemColor;
  final Color petalColor;

  String get asset => '$assetDirectory/planter_$name.webp';
  double get widthRatio => sourceWidth / sourceHeight;
  double get edgeDirection => this == daisy ? -1 : 1;
}

typedef PlanterChewFrame = ({int index, double gape});

/// Bite poses and contact times shared by the animation and each crop cut.
class PlanterChew {
  PlanterChew({
    required PlanterCrop crop,
    required Rect flower,
    required double existingDamage,
    required this.direction,
  }) : _center = flower.center,
       cuts = [
         existingDamage + (1 - existingDamage) * crop.firstCut,
         existingDamage + (1 - existingDamage) * crop.secondCut,
         1,
       ] {
    final first = flower.top + cuts[0] * flower.height - 4;
    final second = flower.top + cuts[1] * flower.height - 3;
    _mouthHeights = [
      waitingMouth(flower).dy,
      first - 9,
      first,
      first - 14,
      second,
      second - 14,
      flower.top + flower.height * .94,
    ];
  }

  static const contactTimes = [.40, .68, 1.0];
  static const recovery = .54;
  static const fragmentDuration = .24;
  static const frameSize = 124;
  static const columns = 8;

  // Each value describes the jaw opening in the corresponding approved frame.
  static const _gapes = [
    .470,
    .442,
    .387,
    .344,
    .377,
    .541,
    .757,
    .939,
    .999,
    .971,
    .936,
    .809,
    .271,
    .028,
    .088,
    .204,
    .616,
    .880,
    .854,
    .814,
    .670,
    .201,
    .016,
    .074,
    .150,
    .437,
    .781,
    .991,
    .971,
    .895,
    .849,
    .389,
    .005,
  ];
  static final frameCount = _gapes.length;

  static final _motionTimes = [
    0.0,
    .25,
    contactTimes[0],
    .52,
    contactTimes[1],
    .82,
    contactTimes[2],
  ];

  static Offset waitingMouth(Rect flower) =>
      flower.center - const Offset(0, 31);

  static PlanterChewFrame frameAt(double progress) {
    final index = (progress.clamp(0.0, 1.0) * (frameCount - 1)).round();
    return (index: index, gape: _gapes[index]);
  }

  final double direction;
  final List<double> cuts;
  final Offset _center;
  late final List<double> _mouthHeights;

  Offset mouthAt(double progress, {required bool reducedMotion}) {
    var beat = 1;
    while (beat < _motionTimes.length - 1 && progress > _motionTimes[beat]) {
      beat++;
    }
    final start = _motionTimes[beat - 1];
    final t = ((progress - start) / (_motionTimes[beat] - start)).clamp(
      0.0,
      1.0,
    );
    final y = lerpDouble(
      _mouthHeights[beat - 1],
      _mouthHeights[beat],
      t * t * (3 - 2 * t),
    )!;
    final lean = reducedMotion
        ? 0.0
        : direction * sin(progress * pi) * (4 + frameAt(progress).gape * 4);
    return Offset(_center.dx + lean, y);
  }
}
