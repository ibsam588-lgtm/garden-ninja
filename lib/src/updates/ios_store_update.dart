import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

int? compareStoreVersions(String left, String right) {
  final numeric = RegExp(r'^\d+(?:\.\d+){0,3}$');
  if (!numeric.hasMatch(left) || !numeric.hasMatch(right)) return null;
  final a = left.split('.').map(int.parse).toList();
  final b = right.split('.').map(int.parse).toList();
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final difference = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (difference != 0) return difference.sign;
  }
  return 0;
}

class IosStoreUpdate {
  const IosStoreUpdate(this.version);
  final String version;

  static IosStoreUpdate? fromResponse(
    Map<dynamic, dynamic>? data,
    String appId,
  ) {
    if (data == null || data['production'] != true || appId.isEmpty) {
      return null;
    }
    final listing = data['listing'];
    if (listing is! Map ||
        listing['bundleId'] != 'com.corsairlabs.gardenNinja' ||
        listing['trackId'].toString() != appId) {
      return null;
    }
    final installed = data['installedVersion'];
    final available = listing['version'];
    final minimumOS = listing['minimumOsVersion'];
    final currentOS = data['systemVersion'];
    if (installed is! String ||
        available is! String ||
        minimumOS is! String ||
        currentOS is! String) {
      return null;
    }
    if (compareStoreVersions(available, installed) != 1 ||
        ![0, 1].contains(compareStoreVersions(currentOS, minimumOS))) {
      return null;
    }
    return IosStoreUpdate(available);
  }
}

class IosStoreUpdateGateway {
  static const channel = MethodChannel('garden_ninja/app_update');
  static const appId = String.fromEnvironment(
    'APP_STORE_ID',
    defaultValue: '6834694197',
  );
  @visibleForTesting
  static bool debugForceChecks = false;
  static bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      (kReleaseMode || debugForceChecks);

  Future<IosStoreUpdate?> check() async {
    if (!supported) return null;
    try {
      final response = await channel.invokeMapMethod<dynamic, dynamic>(
        'checkStoreUpdate',
        {'appStoreId': appId},
      );
      return IosStoreUpdate.fromResponse(response, appId);
    } catch (_) {
      // Unlisted apps, offline devices and TestFlight builds remain playable.
      return null;
    }
  }

  Future<bool> openStore() async {
    try {
      return await channel.invokeMethod<bool>('openStoreUpdate', {
            'appStoreId': appId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
