import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'harvest_model.dart';

class HarvestArt {
  HarvestArt(this.courtyard, this.atlas, this.cropAtlas, this.buildingAtlas);
  final ui.Image courtyard;
  final ui.Image atlas;
  final ui.Image cropAtlas;
  final ui.Image buildingAtlas;
  static Future<HarvestArt>? _cached;
  static Future<HarvestArt> load() =>
      _cached ??= _load().catchError((Object error, StackTrace stack) {
        _cached = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<ui.Image> _image(String asset) async {
    final bytes = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<HarvestArt> _load() async {
    final images = await Future.wait([
      _image('assets/images/backgrounds/harvest_courtyard.png'),
      _image('assets/images/sprites/harvest_atlas.png'),
      _image('assets/images/sprites/harvest_crop_levels.png'),
      _image('assets/images/sprites/harvest_building_levels.png'),
    ]);
    final atlas = await _removeChroma(images[1]);
    final cropAtlas = await _removeChroma(images[2]);
    final buildingAtlas = await _removeChroma(images[3]);
    return HarvestArt(images[0], atlas, cropAtlas, buildingAtlas);
  }

  static Future<ui.Image> _removeChroma(ui.Image source) async {
    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not load garden artwork');
    final rgba = Uint8List.fromList(data.buffer.asUint8List());
    // The source atlas uses a flat chroma key. Composite once at load time;
    // there is no per-frame pixel processing and no platform shader dependency.
    for (var i = 0; i < rgba.length; i += 4) {
      final key = ((min(rgba[i], rgba[i + 2]) - rgba[i + 1] - 35) / 60).clamp(
        0.0,
        1.0,
      );
      rgba[i + 3] = (rgba[i + 3] * (1 - key)).round();
      // ImageDescriptor consumes premultiplied pixels. Zero the transparent
      // chroma key's RGB as well, preventing magenta fringes when filtered.
      for (var channel = 0; channel < 3; channel++) {
        rgba[i + channel] = (rgba[i + channel] * (1 - key)).round();
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: source.width,
      height: source.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    source.dispose();
    return image;
  }

  Rect spriteSource(int sprite) {
    final w = atlas.width / 3;
    final h = atlas.height / 2;
    return Rect.fromLTWH(
      (sprite % 3) * w + 8,
      (sprite ~/ 3) * h + 8,
      w - 16,
      h - 16,
    );
  }

  void sprite(
    Canvas canvas,
    int index,
    Rect destination, {
    double opacity = 1,
  }) {
    canvas.drawImageRect(
      atlas,
      spriteSource(index),
      destination,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..filterQuality = FilterQuality.medium,
    );
  }

  Rect _sheetSource(ui.Image sheet, int sprite, int columns, int rows) {
    final w = sheet.width / columns;
    final h = sheet.height / rows;
    return Rect.fromLTWH(
      (sprite % columns) * w + 8,
      (sprite ~/ columns) * h + 8,
      w - 16,
      h - 16,
    );
  }

  void _drawSheetSprite(
    Canvas canvas,
    ui.Image sheet,
    Rect source,
    Rect destination, {
    double opacity = 1,
  }) {
    canvas.drawImageRect(
      sheet,
      source,
      destination,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..filterQuality = FilterQuality.medium,
    );
  }

  void cropSprite(
    Canvas canvas,
    int index,
    Rect destination, {
    double opacity = 1,
  }) => _drawSheetSprite(
    canvas,
    cropAtlas,
    _sheetSource(cropAtlas, index, 3, 2),
    destination,
    opacity: opacity,
  );

  void buildingSprite(
    Canvas canvas,
    GardenUpgrade upgrade,
    int level,
    Rect destination, {
    double opacity = 1,
  }) {
    final index =
        (upgrade == GardenUpgrade.greenhouse ? 0 : 6) + (level.clamp(1, 6) - 1);
    _drawSheetSprite(
      canvas,
      buildingAtlas,
      _sheetSource(buildingAtlas, index, 3, 4),
      destination,
      opacity: opacity,
    );
  }
}

/// Coordinates are in the courtyard art's normalized space. UI layout and
/// pointer testing use this same mapping so targets remain aligned on resize.
class GardenGeometry {
  static const bedCenters = [
    Offset(.372, .401),
    Offset(.177, .477),
    Offset(.496, .568),
    Offset(.714, .480),
    Offset(.530, .734),
    Offset(.650, .692),
  ];
  static const _slots = [
    Offset(-.062, -.017),
    Offset(.007, -.012),
    Offset(.075, .002),
    Offset(-.037, .018),
    Offset(.033, .031),
  ];

  static Offset cropPosition(HarvestCrop crop, Size size, int tier) {
    final center = bedCenters[crop.bed];
    final slot = _slots[(crop.slot + (tier - 1) % 5) % 5];
    final factor = crop.bed >= 4
        ? .75
        : crop.bed == 2
        ? 1.18
        : 1.0;
    return Offset(
      (center.dx + slot.dx * factor) * size.width,
      (center.dy + slot.dy * factor) * size.height,
    );
  }

  static double plantWidth(HarvestCrop crop, Size size) =>
      size.width *
      (crop.bed >= 4
          ? .115
          : crop.bed == 2
          ? .155
          : .14);

  static Rect plantRect(HarvestCrop crop, Size size, int tier) {
    final point = cropPosition(crop, size, tier);
    final width = plantWidth(crop, size);
    return Rect.fromCenter(
      center: point.translate(0, -width * .24),
      width: width,
      height: width,
    );
  }

  static Rect plantHitRect(HarvestCrop crop, Size size, int tier) {
    final art = plantRect(crop, size, tier);
    final width = max(48.0, art.width * 1.42);
    return Rect.fromCenter(
      center: art.center,
      width: width,
      height: max(48.0, art.height * 1.32),
    );
  }

  static Rect greenhouseRect(Size size, {int level = 1}) {
    final width = size.width * (.39 + (level - 1).clamp(0, 5) * .018);
    return Rect.fromCenter(
      center: Offset(.72 * size.width, .285 * size.height),
      width: width,
      height: width,
    );
  }

  static Rect terraceRect(Size size, {int level = 1}) {
    final width = size.width * (.43 + (level - 1).clamp(0, 5) * .012);
    return Rect.fromCenter(
      center: Offset(.61 * size.width, .725 * size.height),
      width: width,
      height: width,
    );
  }

  static int? nearestCrop(Offset point, Size size, HarvestRound round) {
    double nearest = double.infinity;
    int? result;
    for (final crop in round.crops) {
      final center = plantRect(crop, size, round.progress.tier).center;
      final radius = max(25.0, plantWidth(crop, size) * .62);
      final distance = (center - point).distance;
      if (distance <= radius && distance < nearest) {
        nearest = distance;
        result = crop.id;
      }
    }
    return result;
  }

  static int nearestBed(Offset point, Size size, int count) {
    return List.generate(count, (i) => i).reduce((a, b) {
      Offset center(int i) =>
          Offset(bedCenters[i].dx * size.width, bedCenters[i].dy * size.height);
      return (point - center(a)).distance < (point - center(b)).distance
          ? a
          : b;
    });
  }
}

class GardenBurst {
  GardenBurst(this.position, this.born, this.count);
  final Offset position;
  final double born;
  final int count;
}

class HarvestScenePainter extends CustomPainter {
  HarvestScenePainter({
    required this.art,
    required this.round,
    required this.motion,
    required this.bursts,
    required this.reducedMotion,
    this.preview,
    this.selectedBed,
    this.pointer,
    this.paintTrail = true,
  });
  final HarvestArt art;
  final HarvestRound round;
  final double motion;
  final List<GardenBurst> bursts;
  final bool reducedMotion;
  final GardenUpgrade? preview;
  final int? selectedBed;
  final Offset? pointer;
  final bool paintTrail;

  @override
  void paint(Canvas canvas, Size size) {
    final p = round.progress;
    canvas.drawImageRect(
      art.courtyard,
      Rect.fromLTWH(
        0,
        0,
        art.courtyard.width.toDouble(),
        art.courtyard.height.toDouble(),
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final tint = switch (p.tier) {
      2 => const Color(0xFFF2D884),
      3 => const Color(0xFFD78343),
      4 => const Color(0xFF779B84),
      5 => const Color(0xFFBACFDA),
      6 => const Color(0xFFEED5A1),
      _ => Colors.transparent,
    };
    if (p.tier > 1) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = tint.withValues(alpha: .13)
          ..blendMode = BlendMode.softLight,
      );
    }

    if (!reducedMotion) {
      for (var i = 0; i < 9; i++) {
        final phase = motion * (.16 + i * .008) + i * 1.73;
        final x = ((i * .137 + phase * .025) % 1) * size.width;
        final y = (.22 + ((i * .091 + phase * .018) % .58)) * size.height;
        final alpha = .18 + sin(phase * 2.2).abs() * .18;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(phase);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 5, height: 2.4),
          Paint()..color = const Color(0xFFFFE6A6).withValues(alpha: alpha),
        );
        canvas.restore();
      }
    }

    if (p.terrace > 0 || preview == GardenUpgrade.terrace) {
      final level = preview == GardenUpgrade.terrace
          ? max(1, p.tier)
          : max(1, p.terrace);
      final rect = GardenGeometry.terraceRect(size, level: level);
      canvas.save();
      if (!reducedMotion) {
        final pulse = 1 + sin(motion * 1.45) * .006;
        canvas.translate(rect.bottomCenter.dx, rect.bottomCenter.dy);
        canvas.scale(pulse);
        canvas.translate(-rect.bottomCenter.dx, -rect.bottomCenter.dy);
      }
      art.buildingSprite(
        canvas,
        GardenUpgrade.terrace,
        level,
        rect,
        opacity: p.terrace > 0 ? 1 : .76,
      );
      canvas.restore();
    }
    if (p.greenhouse > 0 || preview == GardenUpgrade.greenhouse) {
      final level = preview == GardenUpgrade.greenhouse
          ? max(1, p.tier)
          : max(1, p.greenhouse);
      final rect = GardenGeometry.greenhouseRect(size, level: level);
      if (preview == GardenUpgrade.greenhouse) {
        canvas.drawOval(
          Rect.fromCenter(
            center: rect.bottomCenter.translate(0, -7),
            width: rect.width,
            height: rect.height * .25,
          ),
          Paint()
            ..color = const Color(0xFFFFC65D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.save();
      if (!reducedMotion) {
        final pulse = 1 + sin(motion * 1.2 + .7) * .008;
        canvas.translate(rect.bottomCenter.dx, rect.bottomCenter.dy);
        canvas.scale(pulse);
        canvas.translate(-rect.bottomCenter.dx, -rect.bottomCenter.dy);
      }
      art.buildingSprite(
        canvas,
        GardenUpgrade.greenhouse,
        level,
        rect,
        opacity: p.greenhouse > 0 ? 1 : .82,
      );
      canvas.restore();
      if (!reducedMotion) {
        final glint = (motion * .22) % 1;
        final x = rect.left + rect.width * (.25 + glint * .5);
        canvas.drawLine(
          Offset(x, rect.top + rect.height * .22),
          Offset(x + rect.width * .08, rect.top + rect.height * .48),
          Paint()
            ..color = Colors.white.withValues(alpha: .20)
            ..strokeWidth = 2,
        );
      }
    }

    if (selectedBed != null) {
      final center = GardenGeometry.bedCenters[selectedBed!];
      final selectedCenter = Offset(
        center.dx * size.width,
        center.dy * size.height,
      );
      final pulse = reducedMotion ? 0.0 : (sin(motion * 4) + 1) / 2;
      final highlight = Rect.fromCenter(
        center: selectedCenter,
        width: size.width * .31,
        height: size.height * .082,
      );
      canvas.drawOval(
        highlight.inflate(5 + pulse * 4),
        Paint()
          ..color = const Color(0xFFFFB42D).withValues(alpha: .20 + pulse * .10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawOval(
        highlight,
        Paint()..color = const Color(0xFFFFC55B).withValues(alpha: .42),
      );
      canvas.drawOval(
        highlight,
        Paint()
          ..color = const Color(0xFFFFF1B0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
      final label = TextPainter(
        text: TextSpan(
          text: 'BED ${selectedBed! + 1}',
          style: const TextStyle(
            color: Color(0xFF273020),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
            backgroundColor: Color(0xFFFFD36E),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          selectedCenter.dx - label.width / 2,
          highlight.top - label.height - 5,
        ),
      );
    }

    final crops = round.crops.toList()
      ..sort(
        (a, b) => GardenGeometry.cropPosition(
          a,
          size,
          p.tier,
        ).dy.compareTo(GardenGeometry.cropPosition(b, size, p.tier).dy),
      );
    for (final crop in crops) {
      final ripe = !round.running || crop.isRipe(round.elapsed);
      final rect = GardenGeometry.plantRect(crop, size, p.tier);
      final sway = reducedMotion ? 0.0 : sin(motion * 1.9 + crop.id) * .017;
      final bob = reducedMotion ? 0.0 : sin(motion * 2.3 + crop.id * .7) * 1.6;
      canvas.save();
      canvas.translate(rect.center.dx, rect.bottom + bob);
      canvas.rotate(sway);
      final cropScale = reducedMotion
          ? 1.0
          : 1 + sin(motion * 1.4 + crop.id) * .012;
      canvas.scale(cropScale);
      canvas.translate(-rect.center.dx, -rect.bottom);
      if (ripe) {
        art.cropSprite(canvas, crop.kind.sprite, rect);
      } else {
        art.sprite(canvas, 1, rect, opacity: .82);
      }
      canvas.restore();
      if (round.acceptsInput &&
          ripe &&
          crop.kind == round.orderKind &&
          !round.chain.contains(crop.id)) {
        final pulse = reducedMotion
            ? .6
            : .55 + sin(motion * 2 + crop.id) * .18;
        canvas.drawCircle(
          rect.center.translate(0, rect.height * .20),
          2,
          Paint()..color = const Color(0xFFFFE0A0).withValues(alpha: pulse),
        );
      }
      if (round.running && !ripe) {
        canvas.drawCircle(
          rect.center,
          3,
          Paint()..color = const Color(0xFFA0BE71),
        );
      }
    }

    if (paintTrail && round.chain.isNotEmpty) {
      final points = round.chain
          .map(
            (id) => GardenGeometry.plantRect(
              round.crops.firstWhere((c) => c.id == id),
              size,
              p.tier,
            ).center,
          )
          .toList();
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (pointer != null) path.lineTo(pointer!.dx, pointer!.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFB938).withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFF0AE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final point in points) {
        canvas.drawCircle(
          point,
          17,
          Paint()
            ..color = const Color(0xFFFFC557)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(
          point,
          20,
          Paint()
            ..color = const Color(0xFFFFE8AE).withValues(alpha: .4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    if (!reducedMotion) {
      for (final burst in bursts) {
        final age = motion - burst.born;
        if (age < 0 || age > .7) continue;
        for (var i = 0; i < 12; i++) {
          final angle = i * pi / 6;
          final point =
              burst.position + Offset(cos(angle), sin(angle)) * (9 + age * 65);
          canvas.drawCircle(
            point,
            (1 - age / .7) * (i.isEven ? 2.5 : 1.6),
            Paint()
              ..color =
                  (i.isEven ? const Color(0xFFFFD175) : const Color(0xFFB9CF88))
                      .withValues(alpha: 1 - age / .7),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant HarvestScenePainter oldDelegate) => true;
}

enum HarvestSpriteSheet { legacy, crops, greenhouse, terrace }

class HarvestSprite extends StatelessWidget {
  const HarvestSprite({
    super.key,
    required this.art,
    required this.index,
    this.size = 40,
    this.sheet = HarvestSpriteSheet.crops,
  });
  final HarvestArt? art;
  final int index;
  final double size;
  final HarvestSpriteSheet sheet;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: art == null
        ? const SizedBox.shrink()
        : CustomPaint(painter: _SpritePainter(art!, index, sheet)),
  );
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.art, this.index, this.sheet);
  final HarvestArt art;
  final int index;
  final HarvestSpriteSheet sheet;
  @override
  void paint(Canvas canvas, Size size) {
    switch (sheet) {
      case HarvestSpriteSheet.legacy:
        art.sprite(canvas, index, Offset.zero & size);
      case HarvestSpriteSheet.crops:
        art.cropSprite(canvas, index, Offset.zero & size);
      case HarvestSpriteSheet.greenhouse:
        art.buildingSprite(
          canvas,
          GardenUpgrade.greenhouse,
          index,
          Offset.zero & size,
        );
      case HarvestSpriteSheet.terrace:
        art.buildingSprite(
          canvas,
          GardenUpgrade.terrace,
          index,
          Offset.zero & size,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter oldDelegate) =>
      art != oldDelegate.art ||
      index != oldDelegate.index ||
      sheet != oldDelegate.sheet;
}
