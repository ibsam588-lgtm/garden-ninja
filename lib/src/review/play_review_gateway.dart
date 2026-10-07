import 'package:flutter/services.dart';

class PlayReviewGateway {
  static const MethodChannel _channel = MethodChannel('garden_ninja/play_review');

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
      return await _channel.invokeMethod<bool>('openStoreListing') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
