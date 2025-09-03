import 'package:bapenda_mdm/services/root_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

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

    // installed apps packageids
    // final installedAppPackageIds = installedApps
    //     .map((app) => app['package'])
    //     .toList();
    // debugPrint("Installed apps package IDs: $installedAppPackageIds");

    debugPrint("Updating configuration with data: $data");
    screensaverType.value = data['screensaverType'] ?? '';
    screensaverImage.value = data['screensaverImage'] ?? '';
    screensaverText.value = data['screensaverText'] ?? '';
    screensaverVideo.value = data['screensaverVideo'] ?? '';
    allowedApps.value = List<String>.from(data['allowedApps'] ?? []);

    debugPrint("Updated allowedApps: $allowedApps");

    // Filter ulang apps kalau allowedApps berubah
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
