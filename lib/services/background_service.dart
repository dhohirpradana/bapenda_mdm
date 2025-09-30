import 'dart:isolate';

import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/services/app_install.dart';
import 'package:bapenda_mdm/services/pocketbase_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

const platform = MethodChannel('root/control');

Future<void> initForegroundChannel() async {
  platform.setMethodCallHandler((call) async {
    if (call.method == "restoreAuth") {
      await restoreAuth();
      await installApp();
    }
  });
}

Future<void> restoreAuth() async {
  debugPrint("restoreAuth() dari Dart dipanggil...");
  // isi login/refresh token ke PocketBase
  await PocketBaseService.restoreAuth();
}

// install app
Future<void> installApp() async {
  debugPrint("Installing app");
  final authCtrl = Get.find<AuthController>();
  final deviceId = authCtrl.deviceId.value;

  if (deviceId.isNotEmpty) {
    await Isolate.run(() async {
      final service = AppInstallService();
      await service.checkAndInstall(deviceId);
    });
    debugPrint("InstallApp selesai (main isolate tetap responsif)");
  }
}
