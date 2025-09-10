import 'dart:convert';
import 'dart:io';
import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/root_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class ConfigurationController extends GetxController {
  var screensaverType = ''.obs;
  var screensaverImage = ''.obs;
  var screensaverText = ''.obs;
  var screensaverVideo = ''.obs;
  var allowedApps = <String>[].obs;
  var apps = <Map<String, String>>[].obs;

  void updateFromPocketBase(Map<String, dynamic> data) async {
    final installedApps = await RootService.getInstalledApps();
    apps.value = installedApps;
    debugPrint("Updating configuration with data: $data");

    screensaverType.value = data['screensaverType'] ?? '';
    screensaverImage.value = data['screensaverImage'] ?? '';
    screensaverText.value = data['screensaverText'] ?? '';
    screensaverVideo.value = data['screensaverVideo'] ?? '';
    allowedApps.value = List<String>.from(data['allowedApps'] ?? []);

    final collectionId = data['collectionId'];
    final recordId = data['id'];

    final imageUrl =
        "${Constants.POCKETBASE_URL}/api/files/$collectionId/$recordId/${screensaverImage.value}";
    final videoUrl =
        "${Constants.POCKETBASE_URL}/api/files/$collectionId/$recordId/${screensaverVideo.value}";

    File? localImage;
    File? localVideo;

    debugPrint("Screensaver type: ${screensaverType.value}");
    debugPrint("Screensaver image: ${screensaverImage.value}");
    debugPrint("Screensaver video: ${screensaverVideo.value}");

    if (screensaverType.value == "IMAGE" && screensaverImage.value.isNotEmpty) {
      localImage = await downloadFile(imageUrl, screensaverImage.value);
    } else if (screensaverType.value == "VIDEO" &&
        screensaverVideo.value.isNotEmpty) {
      localVideo = await downloadFile(videoUrl, screensaverVideo.value);
    }

    await saveScreensaverConfig(
      isEnabled: screensaverType.value.isNotEmpty,
      type: screensaverType.value,
      text: screensaverText.value,
      imagePath: localImage?.path,
      videoPath: localVideo?.path,
      interval: data['screensaverInterval'] ?? 10000,
    );

    // Kiosk handling
    final isKioskEnabled = data["isKioskEnabled"] ?? false;
    final kioskTarget = data["kioskTarget"] ?? '';
    final kioskService = KioskService();

    if (isKioskEnabled && kioskTarget.isNotEmpty) {
      debugPrint("Setting kiosk mode for target: $kioskTarget");
      await kioskService.setKioskConfig(enabled: true, target: kioskTarget);
    } else {
      debugPrint("Disabling kiosk mode");
      await kioskService.setKioskConfig(enabled: false, target: '');
      await kioskService.stopKioskDaemon();
    }

    filterApps();
  }

  void setInstalledApps(List<Map<String, String>> installed) {
    apps.value = installed;
    filterApps();
  }

  void filterApps() {
    if (allowedApps.isNotEmpty) {
      apps.value = apps
          .where((app) => allowedApps.contains(app['package']))
          .toList();
    }
  }
}

Future<File> saveScreensaverConfig({
  required bool isEnabled,
  required String type,
  String? text,
  String? imagePath,
  String? videoPath,
  int interval = 10000,
}) async {
  // final dir = await getApplicationDocumentsDirectory();
  final fdir =
      "/storage/emulated/0/Android/data/id.bapenda.mdm/files/screensaver_config.json";
  // final file = File('${dir.path}/screensaver_config.json');
  final file = File(fdir);
  debugPrint("Saving screensaver config to: ${file.path}");

  // validasi minimal interval 10 detik
  if (interval < 10000) {
    interval = 10000;
  }

  final data = {
    'isEnabled': isEnabled,
    'type': type,
    'text': text ?? '',
    'imagePath': imagePath ?? '',
    'videoPath': videoPath ?? '',
    'interval': interval,
  };

  debugPrint("Screensaver config data: $data");

  return file.writeAsString(jsonEncode(data));
}

Future<File> downloadFile(String url, String filename) async {
  debugPrint("Downloading file from $url");
  final dir = await getApplicationDocumentsDirectory();
  final filePath = "${dir.path}/$filename";
  final file = File(filePath);

  if (!await file.exists()) {
    try {
      await Dio().download(url, filePath);
      debugPrint("Downloaded $filename to $filePath");
    } catch (e) {
      debugPrint("Failed to download $filename: $e");
    }
  } else {
    debugPrint("File already exists: $filePath");
  }

  return file;
}
