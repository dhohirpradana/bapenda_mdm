import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

final file = File("/data/user/0/id.bapenda.mdm/files/kiosk_config.json");

class KioskService {
  Future<void> setKioskConfig({
    required bool enabled,
    required String target,
  }) async {
    debugPrint("Setting kiosk config: enabled=$enabled, target=$target");
    final jsonData = {"enabled": enabled, "target": target};

    debugPrint("Writing kiosk config to ${file.path}");

    await file.writeAsString(jsonEncode(jsonData));
    debugPrint("Kiosk config written to ${file.path}");

    final verify = await file.readAsString();
    debugPrint("Kiosk config: $verify");
  }

  Future<void> stopKioskDaemon() async {
    // kalau non-root mungkin stop daemon via bound service
    // enable false di config
    final jsonData = {"enabled": false, "target": ""};
    await file.writeAsString(jsonEncode(jsonData));
    debugPrint("Kiosk config written to ${file.path}");
    final verify = await file.readAsString();
    debugPrint("Kiosk config: $verify");
    // debugPrint("Stop kiosk not implemented for non-root yet");
  }
}
