import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:garden_ninja/src/app.dart';
import 'package:garden_ninja/src/updates/ios_store_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> response({
  bool production = true,
  String installed = '1.1.7',
  String available = '1.1.8',
  String minimumOS = '15.0',
  String currentOS = '15.0',
  String bundle = 'com.corsairlabs.gardenNinja',
  int id = 6834694197,
}) => {
  'production': production,
  'installedVersion': installed,
  'systemVersion': currentOS,
  'listing': {
    'version': available,
    'minimumOsVersion': minimumOS,
    'bundleId': bundle,
    'trackId': id,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const appId = '6834694197';
  test('only a newer public version for the same app requires an update', () {
    expect(IosStoreUpdate.fromResponse(response(), appId)?.version, '1.1.8');
    expect(
      IosStoreUpdate.fromResponse(response(available: '1.1.7'), appId),
      isNull,
    );
    expect(
      IosStoreUpdate.fromResponse(response(available: '1.1.6'), appId),
      isNull,
    );
    expect(
      IosStoreUpdate.fromResponse(response(bundle: 'different.app'), appId),
      isNull,
    );
    expect(IosStoreUpdate.fromResponse(response(id: 123), appId), isNull);
  });
  test(
    'TestFlight, unavailable listings and unsupported OS upgrades stay playable',
    () {
      expect(
        IosStoreUpdate.fromResponse(response(production: false), appId),
        isNull,
      );
      expect(IosStoreUpdate.fromResponse(null, appId), isNull);
      expect(
        IosStoreUpdate.fromResponse({
          'production': true,
          'listing': null,
        }, appId),
        isNull,
      );
      expect(
        IosStoreUpdate.fromResponse(
          response(minimumOS: '16.0', currentOS: '15.8'),
          appId,
        ),
        isNull,
      );
      expect(
        IosStoreUpdate.fromResponse(
          response(available: 'not a version'),
          appId,
        ),
        isNull,
      );
    },
  );
  test('version comparison uses numbers and normalized components', () {
    expect(compareStoreVersions('1.10.0', '1.9.9'), 1);
    expect(compareStoreVersions('1.1', '1.1.0'), 0);
    expect(compareStoreVersions('1.0.9', '1.1'), -1);
    expect(compareStoreVersions('invalid', '1.1'), isNull);
  });

  testWidgets('public iOS update blocks play and opens the App Store', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IosStoreUpdateGateway.debugForceChecks = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var storeOpened = false;
    messenger.setMockMethodCallHandler(IosStoreUpdateGateway.channel, (
      call,
    ) async {
      if (call.method == 'checkStoreUpdate') return response();
      if (call.method == 'openStoreUpdate') {
        storeOpened = true;
        return true;
      }
      return null;
    });
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    try {
      await tester.pumpWidget(const GardenNinjaApp());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Update Required'), findsOneWidget);
      await tester.tap(find.text('UPDATE NOW'));
      await tester.pump();
      expect(storeOpened, isTrue);
      expect(find.text('Update Required'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      IosStoreUpdateGateway.debugForceChecks = false;
      messenger.setMockMethodCallHandler(IosStoreUpdateGateway.channel, null);
    }
  });
}
