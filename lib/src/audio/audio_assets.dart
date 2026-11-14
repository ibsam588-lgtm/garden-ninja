import 'package:flutter/foundation.dart';

/// AVPlayer needs native Apple encodings instead of the game's Ogg assets.
String platformAudioAsset(String asset, {TargetPlatform? platform}) {
  final target = platform ?? defaultTargetPlatform;
  if ((target == TargetPlatform.iOS || target == TargetPlatform.macOS) &&
      asset.endsWith('.ogg')) {
    final extension = asset.startsWith('audio/sfx/') ? '.wav' : '.m4a';
    return asset.substring(0, asset.length - 4) + extension;
  }
  return asset;
}
