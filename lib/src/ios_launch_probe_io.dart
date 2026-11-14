import 'dart:io';

Future<void> recordIosFirstFrame() async {
  if (Platform.isIOS) {
    await File(
      '${Directory.systemTemp.path}/garden_ninja_first_frame',
    ).writeAsString('ready', flush: true);
  }
}
