// Explicitly render the actual purchase sheet for App Review, without a payment.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:garden_ninja/src/purchases/purchase_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../purchases_test.dart' show FakeStore;

void main() {
  testWidgets(
    'capture the Remove Ads review sheet',
    (tester) async {
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
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'garden_ninja_garden_tutorial_v3': true,
      });
      await tester.runAsync(() async {
        final root = Platform.isWindows
            ? 'C:/Windows/Fonts'
            : '/System/Library/Fonts/Supplemental';
        final font = FontLoader('Arial')
          ..addFont(
            File(
              '$root/${Platform.isWindows ? 'arial.ttf' : 'Arial.ttf'}',
            ).readAsBytes().then(ByteData.sublistView),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await Future.wait([font.load(), icons.load()]);
      });
      final gateway = FakeStore()
        ..product = const StoreProduct(id: removeAdsProductId, price: r'$2.99');
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GardenNinjaApp(purchaseGateway: gateway),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('open-purchases')));
      await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(r'Remove Ads · $2.99'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/purchase-review/remove-ads.png');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    skip: !const bool.fromEnvironment('CAPTURE_PURCHASE_REVIEW'),
  );
}
