import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'terrace_model.dart';

/// The terrace illustrations are the same WebPs used in the playable design.
class TerraceGardenArt {
  TerraceGardenArt._(this._images);

  final Map<String, ui.Image> _images;
  final _terrain = <TerraceStage, ui.Picture>{};
  static Future<TerraceGardenArt>? _loading;

  static Future<TerraceGardenArt> load() =>
      _loading ??= _load().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<TerraceGardenArt> _load() async {
    const keys = ['bud', 'spring', 'bell', 'daisy', 'blossom', 'stone', 'soil'];
    final images = await Future.wait(
      keys.map((key) async {
        final data = await rootBundle.load('assets/images/terrace/$key.webp');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        try {
          return MapEntry(key, (await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      }),
      cleanUp: (entry) => entry.value.dispose(),
    );
    return TerraceGardenArt._(Map.fromEntries(images));
  }
}

const _gridLeft = 100.0, _gridTop = 13.0, _cell = 100.0;
const _board = Size(620, 326);
const _directions = [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)];

Offset _center(int cell) => Offset(
  _gridLeft + (cell % 4 + .5) * _cell,
  _gridTop + (cell ~/ 4 + .5) * _cell,
);

Paint _fill(int argb) => Paint()..color = Color(argb);

void _oval(Canvas c, Offset center, double rx, double ry, int color) {
  c.drawOval(
    Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
    _fill(color),
  );
}

void _stroke(Canvas canvas, Path path, double width, int argb) {
  canvas.drawPath(
    path,
    _fill(argb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round,
  );
}

void _artAt(Canvas c, ui.Image? image, Offset base, double w, double h) {
  if (image == null) return;
  final scale = math.min(w / image.width, h / image.height);
  final width = image.width * scale;
  final height = image.height * scale;
  c.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(base.dx - width / 2, base.dy - height, width, height),
    Paint()..filterQuality = FilterQuality.medium,
  );
}

void _texture(Canvas c, ui.Image? image, Rect area, double opacity) {
  if (image == null) return;
  c.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    area,
    Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..filterQuality = FilterQuality.medium,
  );
}

final _channelPaths = {
  TerraceShape.straight: Path()
    ..moveTo(0, -50.5)
    ..lineTo(0, 50.5),
  TerraceShape.elbow: Path()
    ..moveTo(0, -50.5)
    ..lineTo(0, -25)
    ..quadraticBezierTo(0, 0, 25, 0)
    ..lineTo(50.5, 0),
  TerraceShape.tee: Path()
    ..moveTo(0, -50.5)
    ..lineTo(0, 50.5)
    ..moveTo(0, 0)
    ..lineTo(50.5, 0),
};

class TerraceGardenPainter extends CustomPainter {
  const TerraceGardenPainter({
    required this.stage,
    required this.turns,
    required this.flow,
    required this.waterProgress,
    required this.highlightedCell,
    this.art,
    this.showMargins = false,
    this.rotatingCell,
    this.turnProgress = 1,
  });

  final TerraceStage stage;
  final List<int> turns;
  final TerraceFlow flow;
  final double waterProgress;
  final int? highlightedCell;
  final TerraceGardenArt? art;
  final bool showMargins;
  final int? rotatingCell;
  final double turnProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final view = showMargins ? _board : const Size(400, 300);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / view.width, size.height / view.height);
    if (!showMargins) canvas.translate(-_gridLeft, -_gridTop);

    final images = art;
    if (images == null) {
      _terrain(canvas);
    } else {
      // The grain, grass and stonework stay still while water and rotors move.
      final picture = images._terrain.putIfAbsent(stage, () {
        final recorder = ui.PictureRecorder();
        _terrain(Canvas(recorder));
        return recorder.endRecording();
      });
      canvas.drawPicture(picture);
    }
    for (var i = 0; i < stage.tiles.length; i++) {
      if (stage.tiles[i].shape != TerraceShape.land) _trough(canvas, i);
    }
    final depth = flow.depth.fold<int>(0, math.max);
    final time = waterProgress.clamp(0.0, 1.0) * (depth + 2);
    if (time > 0) _water(canvas, time);
    if (showMargins) _goals(canvas, time, size.width);
    if (flow.solved && waterProgress > .82) _fieldFlowers(canvas);
    canvas.restore();
  }

  void _terrain(Canvas canvas) {
    final seed = stage.tiles.fold(
      stage.sourceRow + 1136,
      (v, tile) => (v * 31 + tile.shape.index * 5 + tile.turn) & 0x7fffffff,
    );
    final rand = math.Random(seed);
    final rich = art != null;
    canvas.drawRect(
      Offset.zero & _board,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(620, 326),
          const [Color(0xff9da775), Color(0xff8f9c63), Color(0xff6e8654)],
          const [0, .51, 1],
        ),
    );
    for (var i = 0; i < (rich ? 86 : 8); i++) {
      final point = Offset(rand.nextDouble() * 620, rand.nextDouble() * 326);
      final radius = 9 + rand.nextDouble() * 38;
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(point, radius, [
            Color(i.isEven ? 0x30e7d98f : 0x33274c2c),
            const Color(0x00758b50),
          ]),
      );
    }
    for (var i = 0; i < (rich ? 1050 : 30); i++) {
      final point = Offset(rand.nextDouble() * 620, rand.nextDouble() * 326);
      canvas.drawLine(
        point,
        point + Offset(1 + rand.nextDouble() * 2, -1 - rand.nextDouble() * 2),
        _fill(i.isEven ? 0x33315a35 : 0x65d6d99c)
          ..strokeWidth = .7 + rand.nextDouble(),
      );
    }
    for (var i = 0; i < stage.tiles.length; i++) {
      final tile = stage.tiles[i];
      final p = _center(i);
      if (tile.shape == TerraceShape.land) {
        if (rand.nextDouble() > .45) {
          _oval(canvas, p + const Offset(0, 7), 31, 13, 0x3655713c);
          for (var j = 0; j < 3; j++) {
            final scale = 19 + rand.nextDouble() * 10;
            _artAt(
              canvas,
              art?._images['bud'],
              p +
                  Offset(
                    (j - 1) * 15 + rand.nextDouble() * 5,
                    3 + rand.nextDouble() * 8,
                  ),
              scale * 1.3,
              scale,
            );
          }
          _herb(canvas, p + const Offset(19, 8), 8, rand);
        } else {
          _rock(
            canvas,
            p + const Offset(-6, 4),
            17 + rand.nextDouble() * 5,
            rand,
          );
          _rock(
            canvas,
            p + const Offset(14, 8),
            8 + rand.nextDouble() * 4,
            rand,
          );
          _herb(canvas, p + const Offset(-18, 9), 9, rand);
          _herb(canvas, p + const Offset(5, -9), 6, rand);
        }
      } else {
        _tileStone(canvas, p, tile.fixed, rand);
      }
    }
    final sy = _center(stage.sourceRow * 4).dy;
    _oval(canvas, Offset(46, sy + 17), 43, 13, 0x683d563b);
    final inlet = Path()
      ..moveTo(57, sy)
      ..lineTo(_gridLeft + 1, sy);
    _stroke(canvas, inlet, 23, 0xff80785a);
    _stroke(canvas, inlet, 15, 0xff4ba9ab);
    canvas.drawLine(
      Offset(67, sy - 4),
      Offset(_gridLeft, sy - 4),
      _fill(0xffcbebe0)..strokeWidth = 2,
    );
    _artAt(canvas, art?._images['spring'], Offset(42, sy + 23), 79, 74);
    canvas.drawPath(
      Path()
        ..moveTo(85, sy - 4)
        ..lineTo(92, sy)
        ..lineTo(85, sy + 4)
        ..close(),
      _fill(0xffe0fff2),
    );
    for (final goal in stage.goals) {
      final y = _center(goal.row * 4 + 3).dy;
      final path = Path()
        ..moveTo(497, y)
        ..lineTo(560, y);
      _stroke(canvas, path, 26, 0xffa99f7d);
      _stroke(canvas, path, 15, 0xff695c43);
      _stoneBed(canvas, Offset(560, y + 5), rand);
      _herb(canvas, Offset(586, y + 12), 6, rand);
    }
  }

  void _tileStone(Canvas c, Offset p, bool fixed, math.Random rand) {
    c.save();
    c.translate(p.dx, p.dy);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-48, -48, 96, 94),
      const Radius.circular(9),
    );
    c.drawRRect(body.shift(const Offset(0, 4)), _fill(0xff4c5239));
    c.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(-40, -48),
          const Offset(44, 44),
          const [Color(0xffe0d6b1), Color(0xffc3bc97), Color(0xffa19e7b)],
          const [0, .42, 1],
        ),
    );
    c.save();
    c.clipRRect(body);
    _texture(
      c,
      art?._images['stone'],
      const Rect.fromLTWH(-50, -50, 100, 100),
      .40,
    );
    for (var i = 0; i < (art == null ? 3 : 65); i++) {
      final at = Offset(
        rand.nextDouble() * 98 - 49,
        rand.nextDouble() * 98 - 49,
      );
      _oval(
        c,
        at,
        .5 + rand.nextDouble() * 1.3,
        .3 + rand.nextDouble() * .85,
        i.isEven ? 0x52776e53 : 0x77e3dabc,
      );
    }
    c.restore();
    if (fixed) {
      _stroke(
        c,
        Path()
          ..moveTo(-39, -44)
          ..lineTo(-9, -44)
          ..moveTo(-44, -35)
          ..lineTo(-44, -13),
        1.3,
        0x90e7dfb7,
      );
    } else {
      c.drawCircle(Offset.zero, 45, _fill(0xff6e603a));
      c.drawCircle(const Offset(-.6, -1.5), 44, _fill(0xffc29c5a));
      c.drawCircle(const Offset(-1, -2), 40.5, _fill(0xffe4c88b));
      c.drawCircle(const Offset(-1, -1.2), 38, _fill(0xffb3a981));
      for (var j = 0; j < 4; j++) {
        final angle = math.pi / 4 + j * math.pi / 2;
        final at = Offset(math.cos(angle) * 41, math.sin(angle) * 41 - 1);
        c.drawCircle(at, 1.8, _fill(0xff785f39));
        c.drawCircle(at - const Offset(.4, .4), .8, _fill(0xfff7e1b1));
      }
    }
    c.restore();
  }

  void _herb(Canvas c, Offset p, double size, math.Random r) {
    const shades = [0xff3d5735, 0xff4e713d, 0xff76904b, 0xff97aa62];
    for (var i = 0; i < 6; i++) {
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(i * math.pi / 3 + r.nextDouble() * .3);
      final k = size * (.58 + r.nextDouble() * .44);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(k * .5, -k * .55, k, 0)
        ..quadraticBezierTo(k * .42, k * .3, 0, 0)
        ..close();
      c.drawPath(leaf, _fill(shades[(i + r.nextInt(2)) % 4]));
      c.restore();
    }
    _oval(c, p, 1.5, 1.2, 0xffc0bf73);
  }

  void _rock(Canvas c, Offset p, double radius, math.Random r) {
    _oval(c, p + Offset(1.5, radius * .39), radius, radius * .48, 0x492e3c29);
    final points = <Offset>[];
    final angle = r.nextDouble() * math.pi * 2;
    for (var j = 0; j < 7; j++) {
      final a = j * math.pi * 2 / 7 + angle,
          k = radius * (.78 + r.nextDouble() * .26);
      points.add(p + Offset(math.cos(a) * k, math.sin(a) * k * .67));
    }
    c.drawPath(
      Path()..addPolygon(points, true),
      Paint()
        ..shader = ui.Gradient.linear(
          p - Offset(radius, radius * .7),
          p + Offset(radius, radius * .8),
          const [Color(0xffc1c29e), Color(0xff959780), Color(0xff68715c)],
          const [0, .5, 1],
        ),
    );
  }

  void _stoneBed(Canvas c, Offset p, math.Random r) {
    c.save();
    c.translate(p.dx, p.dy);
    _oval(c, const Offset(2, 17), 48, 15, 0x48283e28);
    _oval(c, const Offset(0, 4), 45.5, 23.5, 0xff675c43);
    c.drawOval(
      const Rect.fromLTWH(-45.5, -23.5, 91, 47),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, -25),
          const Offset(0, 25),
          const [Color(0xffddd1a7), Color(0xffae9d70), Color(0xff8b7e58)],
          const [0, .6, 1],
        ),
    );
    const dirt = Rect.fromLTWH(-39.5, -18.3, 79, 34.6);
    c.save();
    c.clipPath(Path()..addOval(dirt));
    c.drawRect(dirt, _fill(0xff6a4934));
    _texture(c, art?._images['soil'], dirt, .8);
    for (var j = 0; j < 20; j++) {
      _oval(
        c,
        Offset((r.nextDouble() - .5) * 84, (r.nextDouble() - .5) * 43),
        1.5 + r.nextDouble() * 2,
        .65 + r.nextDouble(),
        0x50342b1f,
      );
    }
    c.restore();
    for (var j = 0; j < 9; j++) {
      final v = j * math.pi * 2 / 9, dx = math.cos(v), dy = math.sin(v);
      c.drawLine(
        Offset(dx * 40, dy * 17 - 1),
        Offset(dx * 44.6, dy * 23),
        _fill(0x99786b4d)..strokeWidth = .9,
      );
    }
    c.restore();
  }

  void _trough(Canvas c, int i) {
    final tile = stage.tiles[i],
        p = _center(i),
        path = _channelPaths[tile.shape]!;
    var orientation = turns[i].toDouble();
    if (i == rotatingCell && turnProgress < 1) {
      orientation -= math.pow(1 - turnProgress.clamp(0.0, 1.0), 3).toDouble();
    }
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(orientation * math.pi / 2);
    _stroke(c, path, 33, 0xff5b6249);
    _stroke(c, path, 30, tile.fixed ? 0xffd6cbaa : 0xffdfc386);
    _stroke(c, path, 23, tile.fixed ? 0xff918567 : 0xff9a794f);
    _stroke(c, path, 18, 0xff66583f);
    _stroke(c, path, 14, 0xff806c4c);
    _dashes(c, path, 0, const [1.4, 8, 2, 12], 1, 0xa8b79b71);
    c.restore();
    if (tile.fixed) return;
    final at = p + const Offset(31, -31);
    c.drawCircle(at, 9, _fill(0xff9e793c));
    c.drawCircle(at - const Offset(.4, .6), 7.7, _fill(0xffe0c788));
    c.drawArc(
      Rect.fromCircle(center: at, radius: 4),
      .36 * math.pi,
      1.50 * math.pi,
      false,
      _fill(0xff70562e)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45,
    );
    c.drawPath(
      Path()..addPolygon([
        at + const Offset(2.2, -4.4),
        at + const Offset(5.2, -1.4),
        at + const Offset(1, -1.5),
      ], true),
      _fill(0xff70562e),
    );
    if (i == highlightedCell) {
      final border = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: 94, height: 94),
        const Radius.circular(10),
      );
      c.drawRRect(
        border,
        _fill(0xff345940)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      c.drawRRect(
        border,
        _fill(0xffffd86c)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.7,
      );
    }
  }

  List<int> _ports(int i) {
    final tile = stage.tiles[i];
    return terracePorts(tile.shape, tile.fixed ? tile.turn : turns[i]);
  }

  int? _inlet(int i) {
    final depth = flow.depth[i];
    if (depth == 0) return 3;
    for (final d in _ports(i)) {
      final v = _directions[d];
      final x = i % 4 + v.dx.toInt(), y = i ~/ 4 + v.dy.toInt();
      if (x < 0 || x >= 4 || y < 0 || y >= 3) continue;
      final next = y * 4 + x;
      if (flow.depth[next] == depth - 1 && _ports(next).contains((d + 2) % 4)) {
        return d;
      }
    }
    return null;
  }

  Path _route(int i, int inlet, int outlet) {
    final p = _center(i), into = _directions[inlet], away = _directions[outlet];
    final path = Path()
      ..moveTo(p.dx + into.dx * 50, p.dy + into.dy * 50)
      ..lineTo(p.dx + into.dx * 25, p.dy + into.dy * 25);
    if (stage.tiles[i].shape == TerraceShape.elbow) {
      path.quadraticBezierTo(
        p.dx,
        p.dy,
        p.dx + away.dx * 25,
        p.dy + away.dy * 25,
      );
    } else {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(p.dx + away.dx * 50, p.dy + away.dy * 50);
    return path;
  }

  void _stream(Canvas c, Path path, double fraction, double time) {
    if (fraction <= 0) return;
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * fraction.clamp(0, 1));
    _stroke(c, visible, 17, 0xff317979);
    _stroke(c, visible, 13, 0xff5bb9bb);
    _stroke(c, visible, 8, 0xff8acfc8);
    _dashes(c, visible, time * 2.9, const [1, 13, 5, 20], 2, 0xffd8fff0);
  }

  void _water(Canvas c, double time) {
    for (final cell in flow.wet) {
      final f = (time - flow.depth[cell]).clamp(0.0, 1.0);
      if (f == 0) continue;
      final inlet = _inlet(cell);
      if (inlet == null) continue;
      for (final outlet in _ports(cell)) {
        if (outlet != inlet) _stream(c, _route(cell, inlet, outlet), f, time);
      }
    }
    for (final leak in flow.spills) {
      final f = (time - math.max(0, flow.depth[leak.cell]) - 1).clamp(0.0, 1.0);
      if (f == 0) continue;
      final d = _directions[leak.dir];
      final pos = _center(leak.cell) + d * 61;
      final at = Offset(pos.dx.clamp(9.0, 611.0), pos.dy.clamp(6.0, 320.0));
      c.save();
      c.translate(at.dx, at.dy);
      c.rotate(d.dy * .5);
      _oval(c, Offset.zero, 13 * f, 7 * f, 0xab6d6446);
      _oval(c, Offset.zero, 10 * f, 4.5 * f, 0xff6bb0a4);
      for (var j = 0; j < 4; j++) {
        _oval(
          c,
          Offset((j - 1.5) * 4, (-4 - math.sin(j * 1.9 + .3).abs() * 5) * f),
          1.4 * f,
          2.3 * f,
          0xffd1f6e1,
        );
      }
      c.restore();
    }
  }

  void _goals(Canvas c, double time, double screenWidth) {
    final labelScale = (_board.width / screenWidth).clamp(1.0, 2.1);
    _label(
      c,
      Offset(49, _center(stage.sourceRow * 4).dy + 38),
      'Spring',
      labelScale,
    );
    for (final goal in stage.goals) {
      final i = goal.row * 4 + 3, y = _center(i).dy;
      final f = flow.fed.contains(goal.row)
          ? (time - flow.depth[i] - 1).clamp(0.0, 1.0)
          : 0.0;
      if (f > 0) {
        _stream(
          c,
          Path()
            ..moveTo(500, y)
            ..lineTo(531, y)
            ..lineTo(552, y + 3),
          f,
          time,
        );
        _oval(c, Offset(561, y + 4), 32 * f, 8, 0x533a4939);
      }
      final grown = f > .8;
      final scale = grown ? .8 + .2 * ((f - .8) * 5).clamp(0.0, 1.0) : 1.0;
      _artAt(
        c,
        art?._images[grown ? goal.crop : 'bud'],
        Offset(560, y + 6),
        (grown ? 72.0 : 43.0) * scale,
        (grown ? 65.0 : 37.0) * scale,
      );
      if (grown && waterProgress < 1) {
        for (var k = 0; k < 4; k++) {
          final a = k * math.pi / 2 + time * .5;
          _oval(
            c,
            Offset(560 + math.cos(a) * 24, y - 20 + math.sin(a) * 15),
            1.4,
            1.4,
            0xfffff0a1,
          );
        }
      }
      _label(c, Offset(560, y + 37), goal.name, labelScale);
    }
  }

  void _fieldFlowers(Canvas c) {
    for (var i = 0; i < stage.tiles.length; i++) {
      if (stage.tiles[i].shape != TerraceShape.land) continue;
      final r = math.Random(437 + i * 117 + stage.sourceRow), p = _center(i);
      final type = stage.goals[i % stage.goals.length].crop;
      for (var k = 0; k < 3; k++) {
        final scale = 16 + r.nextDouble() * 15;
        _artAt(
          c,
          art?._images[type],
          p + Offset(13 * k - 13 + r.nextDouble() * 7, 8 + r.nextDouble() * 6),
          scale,
          scale,
        );
      }
    }
  }

  void _label(Canvas c, Offset at, String text, double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xfffff3c7),
          fontSize: 10.5 * scale,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width + 12, height = 15 * scale;
    final center = Offset(
      at.dx.clamp(width / 2 + 3, _board.width - width / 2 - 3),
      at.dy.clamp(height / 2 + 2, _board.height - height / 2 - 2),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: width, height: height),
        const Radius.circular(5),
      ),
      _fill(0xed294b38),
    );
    painter.paint(c, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  void _dashes(
    Canvas c,
    Path path,
    double phase,
    List<double> pattern,
    double width,
    int color,
  ) {
    final ink = Path();
    final cycle = pattern.fold<double>(0, (a, b) => a + b);
    for (final metric in path.computeMetrics()) {
      var at = (phase % cycle) - cycle;
      var k = 0;
      while (at < metric.length) {
        final end = at + pattern[k % pattern.length];
        if (k.isEven && end > 0) {
          ink.addPath(
            metric.extractPath(math.max(0, at), math.min(end, metric.length)),
            Offset.zero,
          );
        }
        k++;
        at = end;
      }
    }
    _stroke(c, ink, width, color);
  }

  @override
  bool shouldRepaint(TerraceGardenPainter old) =>
      old.stage != stage ||
      old.turns != turns ||
      old.flow != flow ||
      old.waterProgress != waterProgress ||
      old.highlightedCell != highlightedCell ||
      old.art != art ||
      old.showMargins != showMargins ||
      old.rotatingCell != rotatingCell ||
      old.turnProgress != turnProgress;
}
