// ignore_for_file: invalid_use_of_protected_member

import 'dart:convert';
import 'dart:io';
import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/root_service.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
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

  /// Cache untuk menyimpan konfigurasi terakhir
  Map<String, dynamic> _lastConfiguration = {};

  Future<void> updateFromPocketBase(Map<String, dynamic> data) async {
    debugPrint("Updating configuration with data: $data");

    // === Cek perubahan konfigurasi ===
    if (_isConfigurationUnchanged(data)) {
      debugPrint("Configuration unchanged, skipping update");
      return;
    }

    // === Update Apps hanya jika berubah ===
    final installedApps = await RootService.getInstalledApps();
    debugPrint("Installed apps from RootService: $installedApps");
    setInstalledApps(List<Map<String, String>>.from(installedApps));

    // === Update Allowed Apps hanya jika berubah ===
    final newAllowedApps = List<String>.from(data['allowedApps'] ?? []);
    _updateAllowedAppsIfChanged(newAllowedApps);

    // === Screensaver Configuration ===
    await _updateScreensaverConfiguration(data);

    // === Kiosk Mode Configuration ===
    await _updateKioskConfiguration(data);

    // === Simpan konfigurasi terakhir ===
    _lastConfiguration = Map<String, dynamic>.from(data);

    filterApps();
  }

  /// Mengupdate allowedApps hanya jika ada perubahan
  void _updateAllowedAppsIfChanged(List<String> newAllowedApps) {
    // Gunakan DeepCollectionEquality untuk perbandingan yang lebih akurat
    const listEquality = ListEquality<String>();

    if (!listEquality.equals(allowedApps.value, newAllowedApps)) {
      debugPrint(
        "Allowed apps changed from ${allowedApps.value} to $newAllowedApps",
      );
      allowedApps.value = newAllowedApps;
    } else {
      debugPrint("Allowed apps unchanged, skip update");
    }
  }

  /// Cek apakah konfigurasi telah berubah
  bool _isConfigurationUnchanged(Map<String, dynamic> newData) {
    if (_lastConfiguration.isEmpty) return false;

    // Bandingkan field-field penting
    final criticalFields = [
      'screensaverType',
      'screensaverImage',
      'screensaverText',
      'screensaverVideo',
      'allowedApps',
      'isScreensaverEnabled',
      'screensaverInterval',
      'isKioskEnabled',
      'kioskTarget',
    ];

    for (final field in criticalFields) {
      final oldValue = _lastConfiguration[field];
      final newValue = newData[field];

      if (field == 'allowedApps') {
        // Khusus untuk allowedApps, gunakan perbandingan list
        const listEquality = ListEquality();
        final oldList = List.from(oldValue ?? []);
        final newList = List.from(newValue ?? []);

        if (!listEquality.equals(oldList, newList)) {
          return false;
        }
      } else {
        // Untuk field lainnya, bandingkan secara langsung
        if (oldValue != newValue) {
          return false;
        }
      }
    }

    return true;
  }

  /// Update konfigurasi screensaver
  Future<void> _updateScreensaverConfiguration(
    Map<String, dynamic> data,
  ) async {
    screensaverType.value = data['screensaverType'] ?? '';
    screensaverImage.value = data['screensaverImage'] ?? '';
    screensaverText.value = data['screensaverText'] ?? '';
    screensaverVideo.value = data['screensaverVideo'] ?? '';

    final isScreensaverEnabled = data['isScreensaverEnabled'] ?? false;
    final collectionId = data['collectionId'];
    final recordId = data['id'];

    debugPrint("Screensaver type: ${screensaverType.value}");
    debugPrint("Screensaver image: ${screensaverImage.value}");
    debugPrint("Screensaver video: ${screensaverVideo.value}");
    debugPrint("Screensaver Interval: ${data['screensaverInterval']}");

    // Download files secara parallel jika diperlukan
    final downloadTasks = <Future<File?>>[];

    if (screensaverImage.value.isNotEmpty) {
      final imageUrl =
          "${Constants.pocketbaseUrl}/api/files/$collectionId/$recordId/${screensaverImage.value}";
      downloadTasks.add(downloadFile(imageUrl, screensaverImage.value));
    }

    if (screensaverVideo.value.isNotEmpty) {
      final videoUrl =
          "${Constants.pocketbaseUrl}/api/files/$collectionId/$recordId/${screensaverVideo.value}";
      downloadTasks.add(downloadFile(videoUrl, screensaverVideo.value));
    }

    final downloadResults = await Future.wait(downloadTasks);

    File? localImage;
    File? localVideo;

    if (screensaverImage.value.isNotEmpty && downloadResults.isNotEmpty) {
      localImage = downloadResults[0];
    }
    if (screensaverVideo.value.isNotEmpty) {
      final videoIndex = screensaverImage.value.isNotEmpty ? 1 : 0;
      if (downloadResults.length > videoIndex) {
        localVideo = downloadResults[videoIndex];
      }
    }

    await saveScreensaverConfig(
      isEnabled: isScreensaverEnabled,
      type: screensaverType.value,
      text: screensaverText.value,
      imagePath: localImage?.path,
      videoPath: localVideo?.path,
      interval: data['screensaverInterval'] ?? 10,
    );
  }

  /// Update konfigurasi kiosk mode
  Future<void> _updateKioskConfiguration(Map<String, dynamic> data) async {
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
  }

  void setInstalledApps(List<Map<String, String>> installed) {
    if (!_isAppListEqual(allApps, installed)) {
      debugPrint("Installed apps changed, updating list");
      allApps = installed;
      filterApps();
    } else {
      debugPrint("Installed apps unchanged, skip update");
    }
  }

  void filterApps() {
    final filteredApps = allowedApps.isNotEmpty
        ? allApps.where((app) => allowedApps.contains(app['package'])).toList()
        : List<Map<String, String>>.from(allApps);

    // Update hanya jika berbeda
    if (!_isAppListEqual(apps.value, filteredApps)) {
      apps.value = filteredApps;
      debugPrint("Filtered apps updated: ${apps.length} apps");
    }
  }

  /// Perbandingan list aplikasi yang lebih efisien
  bool _isAppListEqual(
    List<Map<String, String>> listA,
    List<Map<String, String>> listB,
  ) {
    if (listA.length != listB.length) return false;

    // Bandingkan dengan cara yang lebih efisien
    for (int i = 0; i < listA.length; i++) {
      if (listA[i]['package'] != listB[i]['package'] ||
          listA[i]['name'] != listB[i]['name']) {
        return false;
      }
    }
    return true;
  }

  /// Reset cache konfigurasi (untuk testing atau debugging)
  void resetConfigurationCache() {
    _lastConfiguration.clear();
    debugPrint("Configuration cache reset");
  }

  /// Getter untuk mendapatkan status konfigurasi
  bool get hasConfigurationCache => _lastConfiguration.isNotEmpty;
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

// disable screensaver
Future<File> disableScreensaver() async {
  return saveScreensaverConfig(isEnabled: false, type: '', interval: 0);
}

Future<File> downloadFile(String url, String filename) async {
  debugPrint("Downloading file from $url");

  final dir = await getApplicationDocumentsDirectory();
  final filePath = "${dir.path}/$filename";
  final file = File(filePath);

  // Cek apakah file sudah ada dan valid
  if (await file.exists() && await file.length() > 0) {
    debugPrint("File already exists and valid: $filePath");
    return file;
  }

  try {
    // Pastikan directory ada
    await file.parent.create(recursive: true);

    // Download dengan timeout dan retry logic
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 60);

    await dio.download(url, filePath);
    debugPrint("Downloaded $filename to $filePath");

    // Verifikasi file berhasil didownload
    if (!await file.exists() || await file.length() == 0) {
      throw Exception("Downloaded file is empty or corrupted");
    }
  } catch (e) {
    debugPrint("Failed to download $filename: $e");

    // Hapus file yang corrupt jika ada
    if (await file.exists()) {
      await file.delete();
    }

    rethrow;
  }

  return file;
}
