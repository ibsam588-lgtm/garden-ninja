import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/audio/audio_assets.dart';

void main() {
  test('every Ogg track has a native Apple playback asset', () {
    final originals = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.ogg'));
    expect(originals, isNotEmpty);
    for (final original in originals) {
      final asset = original.path.replaceAll('\\', '/').substring(7);
      expect(
        platformAudioAsset(asset, platform: TargetPlatform.android),
        asset,
      );
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final playable = File(
          'assets/${platformAudioAsset(asset, platform: platform)}',
        );
        expect(playable.existsSync(), isTrue, reason: asset);
        final bytes = playable.readAsBytesSync();
        final header = String.fromCharCodes(bytes.take(12));
        if (asset.startsWith('audio/sfx/')) {
          expect(header.startsWith('RIFF'), isTrue, reason: asset);
          expect(header.endsWith('WAVE'), isTrue, reason: asset);
        } else {
          expect(header.substring(4, 8), 'ftyp', reason: asset);
        }
      }
    }
  });
}
