import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlayReviewGateway {
  static const MethodChannel _channel = MethodChannel(
    'garden_ninja/play_review',
  );

  static bool get supportsStoreListing =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          (defaultTargetPlatform == TargetPlatform.iOS &&
              RegExp(
                r'^[0-9]+$',
              ).hasMatch(const String.fromEnvironment('APP_STORE_ID'))));

  Future<bool> requestReview() async {
    try {
      return await _channel.invokeMethod<bool>('requestReview') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openStoreListing() async {
    try {
      return await _channel.invokeMethod<bool>('openStoreListing', {
            'appStoreId': const String.fromEnvironment('APP_STORE_ID'),
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
