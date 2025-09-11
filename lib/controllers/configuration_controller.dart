import 'dart:convert';
import 'dart:io';
import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/root_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class ConfigurationController extends GetxController {
  var screensaverType = ''.obs;
  var screensaverImage = ''.obs;
  var screensaverText = ''.obs;
  var screensaverVideo = ''.obs;
  var allowedApps = <String>[].obs;

  /// Semua aplikasi yang terinstall
  List<Map<String, String>> allApps = [];

  /// Aplikasi yang difilter (ditampilkan ke UI)
  var apps = <Map<String, String>>[].obs;

  Future<void> updateFromPocketBase(Map<String, dynamic> data) async {
    debugPrint("Updating configuration with data: $data");

    // === Update Apps hanya jika berubah ===
    final installedApps = await RootService.getInstalledApps();
    setInstalledApps(List<Map<String, String>>.from(installedApps));

    // === Screensaver ===
    screensaverType.value = data['screensaverType'] ?? '';
    screensaverImage.value = data['screensaverImage'] ?? '';
    screensaverText.value = data['screensaverText'] ?? '';
    screensaverVideo.value = data['screensaverVideo'] ?? '';
    allowedApps.value = List<String>.from(data['allowedApps'] ?? []);

    final isScreensaverEnabled = data['isScreensaverEnabled'] ?? false;
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

    final futures = <Future<File?>>[];
    if (screensaverType.value == "IMAGE" && screensaverImage.value.isNotEmpty) {
      futures.add(downloadFile(imageUrl, screensaverImage.value));
    }
    if (screensaverType.value == "VIDEO" && screensaverVideo.value.isNotEmpty) {
      futures.add(downloadFile(videoUrl, screensaverVideo.value));
    }
    final results = await Future.wait(futures);
    if (results.isNotEmpty) localImage = results[0];
    if (results.length > 1) localVideo = results[1];

    await saveScreensaverConfig(
      isEnabled: isScreensaverEnabled,
      type: screensaverType.value,
      text: screensaverText.value,
      imagePath: localImage?.path,
      videoPath: localVideo?.path,
      interval: data['screensaverInterval'] ?? 10,
    );

    // === Kiosk Mode ===
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
    if (!_listEquals(allApps, installed)) {
      allApps = installed;
      filterApps();
    } else {
      debugPrint("Installed apps unchanged, skip update");
    }
  }

  void filterApps() {
    if (allowedApps.isNotEmpty) {
      apps.value = allApps
          .where((app) => allowedApps.contains(app['package']))
          .toList();
    } else {
      apps.value = allApps;
    }
  }

  bool _listEquals(List<Map<String, String>> a, List<Map<String, String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['package'] != b[i]['package']) return false;
    }
    return true;
  }
}

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

  // validasi minimal 10 detik → simpan dalam ms
  final intervalMs = (interval < 10 ? 10 : interval) * 1000;

  final data = {
    'isEnabled': isEnabled,
    'type': type,
    'text': text ?? '',
    'imagePath': imagePath ?? '',
    'videoPath': videoPath ?? '',
    'interval': intervalMs,
  };

  debugPrint("Saving screensaver config: $data");
  return file.writeAsString(jsonEncode(data));
}

Future<File> downloadFile(String url, String filename) async {
  debugPrint("Downloading file from $url");
  final dir = await getApplicationDocumentsDirectory();
  final filePath = "${dir.path}/$filename";
  final file = File(filePath);

  if (!await file.exists() || await file.length() == 0) {
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
