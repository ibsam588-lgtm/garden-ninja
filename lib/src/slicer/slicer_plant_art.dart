import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SlicerPlantKind {
  thorn('weed_thorn_sprout', 148, 16, 8, .7635, .5878, 1.35, 4.4, .059, 1),
  gobbler('weed_vine_gobbler', 148, 16, 8, .4189, .7838, 1.96, 1.2, .040, 1.2),
  bramble('weed_bramble_bulb', 148, 16, 8, .7635, .7838, 2.03, 1.4, .036, 2),
  seed('weed_seed_chomper', 120, 12, 6, .6667, .7833, 1.28, 5.5, .074, .76),
  leaf('weed_leaf', 120, 12, 6, .7167, .7833, 1.54, 3.5, .061, 1),
  spike('weed_spike', 120, 12, 6, .7500, .7833, 1.50, 4.8, .070, .88),
  purple('weed_vine', 120, 12, 6, .6500, .7833, 1.85, 1.6, .052, 1.3),
  daisy('flower_daisy', 112, 10, 5, .6875, .7857, 2.68, 0, .022, 1),
  shield('flower_shield', 120, 1, 1, .6500, .7833, 3.01, 0, .018, 1);

  const SlicerPlantKind(
    this.assetName,
    this.frameSize,
    this.frames,
    this.columns,
    this.widthRatio,
    this.heightRatio,
    this.period,
    this.lift,
    this.lean,
    this.mass,
  );

  static final _byAsset = {
    for (final kind in values)
      'assets/images/sprites/${kind.assetName}.png': kind,
  };

  static SlicerPlantKind? forAsset(String asset) => _byAsset[asset];

  final String assetName;
  final int frameSize;
  final int frames;
  final int columns;
  final double widthRatio;
  final double heightRatio;
  final double period;
  final double lift;
  final double lean;
  final double mass;

  bool get flower => this == daisy || this == shield;
  double get anchor => (frameSize * .899).round() / frameSize;
}

class SlicerPlantArt {
  SlicerPlantArt._(this._sprites);

  static Future<SlicerPlantArt>? _loaded;
  static SlicerPlantArt? _decoded;
  final Map<SlicerPlantKind, SlicerPlantSprite> _sprites;

  static Future<SlicerPlantArt> load() => _loaded ??= _loadSheets();
  static SlicerPlantArt? get decoded => _decoded;

  SlicerPlantSprite? sprite(SlicerPlantKind? kind) => _sprites[kind];

  static Future<SlicerPlantArt> _loadSheets() async {
    final sprites = await Future.wait(SlicerPlantKind.values.map(_loadSheet));
    return _decoded = SlicerPlantArt._({
      for (final sprite in sprites.whereType<SlicerPlantSprite>())
        sprite.kind: sprite,
    });
  }

  static Future<SlicerPlantSprite?> _loadSheet(SlicerPlantKind kind) async {
    try {
      final data = await rootBundle.load(
        'assets/images/sprites/slicer/${kind.assetName}.webp',
      );
      final codec = await ui.instantiateImageCodec(Uint8List.sublistView(data));
      try {
        final image = (await codec.getNextFrame()).image;
        if (image.width == kind.frameSize * kind.columns &&
            image.height == kind.frameSize * (kind.frames ~/ kind.columns)) {
          return SlicerPlantSprite._(kind, image);
        }
        image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (error) {
      // The original sprite remains available if an animation sheet fails.
      debugPrint('Could not load ${kind.assetName} animation: $error');
    }
    return null;
  }
}

class SlicerPlantSprite {
  SlicerPlantSprite._(this.kind, this._image)
    : _frames = List.generate(
        kind.frames,
        (index) => Rect.fromLTWH(
          (index % kind.columns * kind.frameSize).toDouble(),
          (index ~/ kind.columns * kind.frameSize).toDouble(),
          kind.frameSize.toDouble(),
          kind.frameSize.toDouble(),
        ),
      );

  final SlicerPlantKind kind;
  final ui.Image _image;
  final List<Rect> _frames;

  void draw(Canvas canvas, int frame, double extent, Paint paint) {
    canvas.drawImageRect(
      _image,
      _frames[frame],
      Rect.fromLTWH(-extent / 2, -extent * kind.anchor, extent, extent),
      paint,
    );
  }
}

const slicerFrostFilter = ColorFilter.matrix(<double>[
  .46,
  .33,
  .08,
  0,
  13,
  .18,
  .76,
  .15,
  0,
  26,
  .23,
  .71,
  .45,
  0,
  45,
  0,
  0,
  0,
  1,
  0,
]);

const _hitLight = ColorFilter.matrix(<double>[
  1.15,
  0,
  0,
  0,
  0,
  0,
  1.15,
  0,
  0,
  0,
  0,
  0,
  1.15,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

class SlicerPlantPose {
  const SlicerPlantPose._({
    required this.extent,
    required this.frame,
    required this.feet,
    required this.body,
    required this.ground,
    required this.lift,
    required this.angle,
    required this.scaleX,
    required this.scaleY,
    required this.opacity,
  });

  /// All offsets are relative to the gameplay target's center.
  final Offset feet;
  final Offset body;
  final double ground;
  final double extent;
  final double lift;
  final double angle;
  final double scaleX;
  final double scaleY;
  final double opacity;
  final int frame;

  static SlicerPlantPose sample({
    required SlicerPlantKind kind,
    required int id,
    required double diameter,
    required double clock,
    required double age,
    required double hitAge,
    required double hitAngle,
    required bool reducedMotion,
  }) {
    final extent = diameter / .86;
    final height = kind.heightRatio * extent;
    final ground = height * .46;
    if (reducedMotion) {
      return SlicerPlantPose._(
        extent: extent,
        frame: min(2, kind.frames - 1),
        feet: Offset(0, ground),
        body: Offset.zero,
        ground: ground,
        lift: 0,
        angle: 0,
        scaleX: 1,
        scaleY: 1,
        opacity: 1,
      );
    }

    final cycle = clock / kind.period + (id * .618) % 1;
    final phase = cycle * pi * 2;
    final entryTime = (age / .34).clamp(0.0, 1.0);
    final entry = Curves.easeOutCubic.transform(entryTime);
    final impact = (1 - hitAge / .46).clamp(0.0, 1.0);
    final reaction = sin((1 - impact) * 11) * impact / kind.mass;
    final direction = cos(hitAngle) >= 0 ? 1 : -1;
    final shift = sin(phase - .38);
    final scale = extent / 139;
    final lift = kind.lift * pow(max(0, sin(phase * 2 + .56)), 2) * scale;
    final feet = Offset(
      (shift * (kind.flower ? .7 : 2.6) + direction * reaction * 13) * scale,
      ground + (1 - entry) * 3 * scale - lift - reaction.abs() * 3.4 * scale,
    );
    final scaleX =
        (.92 + entry * .08) * (1 + shift * .019 + reaction.abs() * .09);
    final scaleY =
        (.91 + entry * .09) * (1 - shift * .028 - reaction.abs() * .07);
    return SlicerPlantPose._(
      extent: extent,
      frame: hitAge < .15
          ? min((kind.frames * .785).round(), kind.frames - 1)
          : (cycle * kind.frames).floor() % kind.frames,
      feet: feet,
      body: feet - Offset(0, ground * scaleY),
      ground: ground,
      lift: lift,
      angle: shift * kind.lean + direction * reaction * .19,
      scaleX: scaleX,
      scaleY: scaleY,
      opacity: .85 + entry * .15,
    );
  }
}

class SlicerPlantPainter extends CustomPainter {
  SlicerPlantPainter({
    required this.sprite,
    required this.pose,
    required this.hitAge,
    required this.cuts,
    required this.maxCuts,
    required this.frozen,
    required this.frost,
    required this.reducedMotion,
  });

  final SlicerPlantSprite sprite;
  final SlicerPlantPose pose;
  final double hitAge;
  final int cuts;
  final int maxCuts;
  final bool frozen;
  final double frost;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final kind = sprite.kind;
    final width = kind.widthRatio * pose.extent;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    _paintShadow(canvas, width);
    if (frozen && frost > 0) _paintFrost(canvas, width);
    if (kind.flower) {
      final halo = Rect.fromCircle(
        center: pose.body,
        radius: pose.ground * 1.29,
      );
      canvas.drawOval(
        halo,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x33A9F6C0), Color(0x00A9F6C0)],
            stops: [.48, 1],
          ).createShader(halo),
      );
    }

    canvas.save();
    canvas.translate(pose.feet.dx, pose.feet.dy);
    canvas.rotate(pose.angle);
    canvas.scale(pose.scaleX, pose.scaleY);
    sprite.draw(
      canvas,
      pose.frame,
      pose.extent,
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Colors.white.withValues(alpha: pose.opacity)
        ..colorFilter = frozen
            ? slicerFrostFilter
            : hitAge < .065 && !reducedMotion
            ? _hitLight
            : null,
    );
    if (kind == SlicerPlantKind.bramble && cuts < maxCuts) _paintCracks(canvas);
    canvas.restore();
    if (maxCuts > 1) _paintPips(canvas);
    canvas.restore();
  }

  void _paintShadow(Canvas canvas, double width) {
    canvas.save();
    canvas.translate(pose.feet.dx + pose.lift * .6, pose.ground + 1.4);
    canvas.transform(_shadowProjection);
    sprite.draw(
      canvas,
      pose.frame,
      pose.extent,
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.mode(
          const Color(0xFF242E17).withValues(alpha: .27 - pose.lift * .013),
          BlendMode.srcIn,
        ),
    );
    canvas.restore();

    final radius = width * .35 - pose.lift * .38;
    canvas.save();
    canvas.translate(pose.feet.dx, pose.ground + 1);
    canvas.scale(1, .31);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, radius, [
          const Color(0xFF131E0C).withValues(alpha: .42 - pose.lift * .022),
          const Color(0x00131E0C),
        ]),
    );
    canvas.restore();
  }

  static final _shadowProjection = Float64List.fromList([
    .78,
    .10,
    0,
    0,
    -.42,
    -.23,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  void _paintFrost(Canvas canvas, double width) {
    canvas.save();
    canvas.translate(pose.feet.dx, pose.ground);
    final base = Rect.fromCenter(
      center: const Offset(0, -1),
      width: width * 1.08,
      height: 15,
    );
    canvas.drawOval(
      base,
      Paint()..color = const Color(0xFF72C4E2).withValues(alpha: .17 * frost),
    );
    canvas.drawOval(
      base,
      Paint()
        ..color = const Color(0xFFD0F7FF).withValues(alpha: .52 * frost)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15,
    );
    const count = 7;
    for (var index = 0; index < count; index++) {
      final x = (index - 3) * width * .145;
      final y = 2 + cos(index * 2.63) * 5;
      final length = (5 + (index * 7) % 11) * frost;
      final tip = Offset(x + sin(index * 2.3) * 4, y - length);
      final path = Path()
        ..moveTo(x - 3.5, y)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(x + 3, y + 2)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset(x - 4, y), tip, [
            const Color(0xFF479CBD).withValues(alpha: .26 * frost),
            const Color(0xFFEFFFFF).withValues(alpha: .86 * frost),
          ]),
      );
    }
    canvas.restore();
  }

  void _paintCracks(Canvas canvas) {
    final scale = pose.extent / 153;
    canvas.save();
    canvas.translate(-17 * scale, -pose.ground - 26 * scale);
    canvas.scale(scale, scale);
    final path = Path()
      ..moveTo(-6, -10)
      ..lineTo(1, -2)
      ..lineTo(-2, 5)
      ..lineTo(7, 11)
      ..lineTo(3, 21)
      ..lineTo(9, 27)
      ..moveTo(0, -2)
      ..lineTo(10, 1)
      ..lineTo(15, 8);
    if (cuts <= 2) {
      path
        ..moveTo(7, 11)
        ..lineTo(16, 15)
        ..lineTo(17, 22);
    }
    final contact = (1 - hitAge / .43).clamp(0.0, 1.0);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xBC282916)
      ..strokeWidth = 3;
    canvas.drawPath(path, edge);
    canvas.drawPath(
      path,
      edge
        ..strokeWidth = .95 + contact * .68
        ..color = const Color(
          0xFFFFDD8B,
        ).withValues(alpha: .44 + contact * .48),
    );
    canvas.restore();
  }

  void _paintPips(Canvas canvas) {
    final left = -(maxCuts * 8 + 7) / 2 + pose.feet.dx;
    final top = pose.ground + 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, maxCuts * 8 + 7, 9),
        const Radius.circular(4.5),
      ),
      Paint()..color = const Color(0xDC1E2F18),
    );
    final paint = Paint();
    for (var index = 0; index < maxCuts; index++) {
      paint.color = index < cuts
          ? const Color(0xFFFFE19A)
          : const Color(0xFF796547);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + 4.2 + index * 8, top + 2.5, 6, 4),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SlicerPlantPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.sprite != sprite ||
      oldDelegate.cuts != cuts ||
      oldDelegate.maxCuts != maxCuts ||
      oldDelegate.hitAge != hitAge ||
      oldDelegate.frozen != frozen ||
      oldDelegate.frost != frost ||
      oldDelegate.reducedMotion != reducedMotion;
}

class SlicerCutFramePainter extends CustomPainter {
  const SlicerCutFramePainter({
    required this.sprite,
    required this.pose,
    required this.frozen,
  });

  final SlicerPlantSprite sprite;
  final SlicerPlantPose pose;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    final feet = pose.feet - pose.body;
    canvas.save();
    canvas.translate(size.width / 2 + feet.dx, size.height / 2 + feet.dy);
    canvas.rotate(pose.angle);
    canvas.scale(pose.scaleX, pose.scaleY);
    sprite.draw(
      canvas,
      pose.frame,
      pose.extent,
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = frozen ? slicerFrostFilter : null,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SlicerCutFramePainter oldDelegate) =>
      oldDelegate.sprite != sprite ||
      oldDelegate.pose != pose ||
      oldDelegate.frozen != frozen;
}
