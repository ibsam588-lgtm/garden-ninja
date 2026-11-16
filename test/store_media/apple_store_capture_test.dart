// Run explicitly; this renders the shipped widgets, with real assets and fonts.
// flutter test test/store_media/apple_store_capture_test.dart --dart-define=STORE_SCREENSHOTS=true --dart-define=CAPTURE_APPLE_STORE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:garden_ninja/src/garden/harvest_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

const displays = <String, (int, int, double)>{
  // Local capture folder names, not undocumented App Store Connect API enums.
  'DUO_OUTER': (1398, 2034, 3),
  'DUO_INNER': (2007, 2853, 3),
  'APP_IPHONE_67': (1320, 2868, 3),
  'APP_IPHONE_61': (1206, 2622, 3),
  'APP_IPHONE_65': (1242, 2688, 3),
  'APP_IPHONE_58': (1125, 2436, 3),
  'APP_IPHONE_55': (1242, 2208, 3),
  'APP_IPHONE_47': (750, 1334, 2),
  'APP_IPHONE_40': (640, 1136, 2),
  'APP_IPAD_PRO_3GEN_129': (2064, 2752, 2),
  'APP_IPAD_PRO_3GEN_11': (1668, 2388, 2),
  'APP_IPAD_PRO_129': (2048, 2732, 2),
  'APP_IPAD_105': (1668, 2224, 2),
  'APP_IPAD_97': (1536, 2048, 2),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        if (call.method == 'getDuration' ||
            call.method == 'getCurrentPosition') {
          return 0;
        }
        return null;
      },
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  const enabled = bool.fromEnvironment('CAPTURE_APPLE_STORE');
  for (final entry in displays.entries) {
    testWidgets('capture ${entry.key}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final (width, height, ratio) = entry.value;
      tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'garden_ninja_garden_tutorial_v3': true,
      });
      await tester.runAsync(() async {
        final fontPath = Platform.isWindows
            ? 'C:/Windows/Fonts/arial.ttf'
            : '/System/Library/Fonts/Supplemental/Arial.ttf';
        final font = FontLoader('Arial')
          ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        final boldPath = Platform.isWindows
            ? 'C:/Windows/Fonts/arialbd.ttf'
            : '/System/Library/Fonts/Supplemental/Arial Bold.ttf';
        font.addFont(File(boldPath).readAsBytes().then(ByteData.sublistView));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load(), HarvestArt.load()]);
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const GardenNinjaApp()),
      );
      Future<void> ready() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          });
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> capture(String name) async {
        await ready();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: ratio);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/apple-store-captures/${entry.key}')
            ..createSync(recursive: true);
          File(
            '${dir.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('01-home');
      await tester.tap(find.byKey(const ValueKey('home-menu-Garden')));
      await capture('02-garden');
      await tester.tap(find.byKey(const ValueKey('harvest-start')));
      await tester.pump(const Duration(seconds: 8));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('harvest-crop-0'))),
      );
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('harvest-crop-1'))),
      );
      await capture('03-harvest');
      await gesture.up();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const GardenNinjaApp()),
      );
      await ready();
      await tester.tap(find.byKey(const ValueKey('primary-PLAY')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('target-1')));
      await capture('04-arcade');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: !enabled);
  }
}
