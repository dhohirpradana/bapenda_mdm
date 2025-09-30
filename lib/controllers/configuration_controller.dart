// ignore_for_file: invalid_use_of_protected_member
import 'dart:io';
import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/services/download_file.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/root_service.dart';
import 'package:bapenda_mdm/services/screensaver_service.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

final box = GetStorage();

class ConfigurationController extends GetxController {
  var screensaverType = ''.obs;
  // var screensaverImage = RecordModel().obs;
  var screensaverText = ''.obs;
  // var screensaverVideo = RecordModel().obs;
  var allowedApps = <String>[].obs;

  /// Semua aplikasi yang terinstall
  List<Map<String, String>> allApps = [];

  /// Aplikasi yang difilter (ditampilkan ke UI)
  var apps = <Map<String, String>>[].obs;

  /// Cache untuk menyimpan konfigurasi terakhir
  Map<String, dynamic> _lastConfiguration = {};

  // Update allowedApps dari local storage saat inisialisasi
  @override
  void onInit() {
    super.onInit();
    final storedAllowedApps = List<String>.from(box.read('allowedApps') ?? []);
    _updateAllowedAppsIfChanged(storedAllowedApps);
    debugPrint("Loaded allowedApps from storage: $storedAllowedApps");
  }

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

    if (newAllowedApps.isNotEmpty) {
      box.write('allowedApps', newAllowedApps);
      _updateAllowedAppsIfChanged(newAllowedApps);
    } else {
      final fromLocal = List<String>.from(box.read('allowedApps') ?? []);
      _updateAllowedAppsIfChanged(fromLocal);
    }

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
    // screensaverImage.value = data['screensaverImage'];
    screensaverText.value = data['screensaverText'] ?? '';
    // screensaverVideo.value = data['screensaverVideo'];

    final isScreensaverEnabled = data['isScreensaverEnabled'] ?? false;

    debugPrint("Screensaver type: ${screensaverType.value}");
    debugPrint("Screensaver Interval: ${data['screensaverInterval']}");

    final screensaverImage = data['screensaverImage'];
    final screensaverVideo = data['screensaverVideo'];
    debugPrint("Screensaver Image: $screensaverImage");
    debugPrint("Screensaver Video: $screensaverVideo");

    // Download files secara parallel jika diperlukan
    final downloadTasks = <Future<File?>>[];

    if (screensaverImage != null) {
      final recordId = screensaverImage.data['id'];
      final contentCollectionId = screensaverImage.data['collectionId'];
      final contentFile = screensaverImage.data['file'];
      final imageUrl =
          "${Constants.pocketbaseUrl}/api/files/$contentCollectionId/$recordId/$contentFile";
      debugPrint("Image URL: $imageUrl");
      downloadTasks.add(downloadFile(imageUrl, contentFile));
    }

    if (screensaverVideo != null) {
      final recordId = screensaverVideo.data['id'];
      final contentCollectionId = screensaverVideo.data['collectionId'];
      final contentFile = screensaverVideo.data['file'];
      final videoUrl =
          "${Constants.pocketbaseUrl}/api/files/$contentCollectionId/$recordId/$contentFile";
      debugPrint("Video URL: $videoUrl");
      downloadTasks.add(downloadFile(videoUrl, contentFile));
    }

    final downloadResults = await Future.wait(downloadTasks);

    File? localImage;
    File? localVideo;

    if (data['screensaverImage'] != null &&
        data['screensaverImage'].data != null &&
        downloadResults.isNotEmpty) {
      localImage = downloadResults[0];
    }
    if (data['screensaverVideo'] != null &&
        data['screensaverVideo'].data != null) {
      final videoIndex = data['screensaverImage'].data['id'].isNotEmpty ? 1 : 0;
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
      interval: data['screensaverInterval'] ?? 60,
    );
  }

  /// Update konfigurasi kiosk mode
  Future<void> _updateKioskConfiguration(Map<String, dynamic> data) async {
    final isKioskEnabled = data["isKioskEnabled"] ?? false;
    final kioskTarget = data["kioskTarget"] ?? '';
    final kioskService = KioskService();

    if (isKioskEnabled && kioskTarget.isNotEmpty) {
      debugPrint("Setting kiosk mode for target: $kioskTarget");
      RootService.openApp(kioskTarget);
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

// disable screensaver
Future<File> disableScreensaver() async {
  return saveScreensaverConfig(isEnabled: false, type: '', interval: 0);
}
