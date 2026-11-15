"""Create an isolated Flutter app to verify the vendored iOS SwiftPM bridge."""

from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    fixture = root / 'build/levelplay-spm-smoke'
    if fixture.exists():
        raise RuntimeError('Refusing to overwrite an existing smoke app')
    subprocess.run(['flutter', 'create', '--platforms=ios', '--org', 'com.corsairlabs',
                    '--project-name', 'levelplay_spm_smoke', str(fixture)], check=True)
    (fixture / 'pubspec.yaml').write_text('''name: levelplay_spm_smoke
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  unity_levelplay_mediation:
    path: ../../third_party/unity_levelplay_mediation
flutter:
  uses-material-design: true
  config:
    enable-swift-package-manager: true
''', encoding='utf-8')
    (fixture / 'lib/main.dart').write_text('''import 'dart:io';
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Exercise an actual native SDK call without initializing ads or credentials.
  await LevelPlayPrivacySettings.setCOPPA(false);
  runApp(const MaterialApp(home: Scaffold(body: Center(
    child: Text('LevelPlay SwiftPM bridge ready'),
  ))));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    File('${Directory.systemTemp.path}/levelplay_spm_ready').writeAsStringSync('ready');
  });
}
''', encoding='utf-8')
    for name in ('Debug', 'Release'):
        with (fixture / f'ios/Flutter/{name}.xcconfig').open('a', encoding='utf-8') as config:
            config.write('\nOTHER_LDFLAGS = $(inherited) -ObjC\n')


if __name__ == '__main__':
    main()
