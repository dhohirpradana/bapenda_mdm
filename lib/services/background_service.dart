import 'package:bapenda_mdm/services/pocketbase_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

const platform = MethodChannel('root/control');

Future<void> initForegroundChannel() async {
  platform.setMethodCallHandler((call) async {
    if (call.method == "restoreAuth") {
      await restoreAuth();
    }
  });
}

Future<void> restoreAuth() async {
  debugPrint("restoreAuth() dari Dart dipanggil...");
  // isi login/refresh token ke PocketBase
  await PocketBaseService.restoreAuth();
}
