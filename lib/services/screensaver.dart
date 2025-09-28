import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

Future<File> saveScreensaverConfig({
  required bool isEnabled,
  required String type,
  String? text,
  String? imagePath,
  String? videoPath,
  required int interval,
}) async {
  final file = File(
    "/storage/emulated/0/Android/data/id.bapenda.mdm/files/screensaver_config.json",
  );

  final intervalMs = interval < 60 ? 60 : interval;

  final data = {
    'isEnabled': isEnabled,
    'type': type,
    'text': text ?? '',
    'imagePath': imagePath ?? '',
    'videoPath': videoPath ?? '',
    'interval': intervalMs,
  };

  debugPrint("Saving screensaver config: $data");

  // Pastikan directory ada
  await file.parent.create(recursive: true);

  return file.writeAsString(jsonEncode(data));
}

// Update screensaver new Image/Video only
Future<void> updateScreensaverMedia({
  String? imagePath,
  String? videoPath,
}) async {
  final file = File(
    "/storage/emulated/0/Android/data/id.bapenda.mdm/files/screensaver_config.json",
  );

  if (!await file.exists()) {
    debugPrint("Screensaver config file does not exist. Cannot update media.");
    return;
  }

  final content = await file.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;

  if (imagePath != null) {
    data['imagePath'] = imagePath;
  }
  if (videoPath != null) {
    data['videoPath'] = videoPath;
  }

  debugPrint("Updating screensaver media: $data");

  await file.writeAsString(jsonEncode(data));
}
