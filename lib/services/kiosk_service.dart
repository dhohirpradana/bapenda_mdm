import 'package:bapenda_mdm/services/root_service.dart';
import 'package:flutter/material.dart';

class KioskService {
  Future<void> setKioskConfig({
    required bool enabled,
    required String target,
  }) async {
    final json =
        '{"enabled": ${enabled ? 'true' : 'false'}, "target": "$target"}';
    final cmd =
        "cat > /data/adb/kiosk_config.json <<'EOF'\n$json\nEOF\nchown root:shell /data/adb/kiosk_config.json\nchmod 660 /data/adb/kiosk_config.json";
    await RootService.runCommand(cmd);
    // cek sukses atau tidak
    final verify = await RootService.runCommand(
      "cat /data/adb/kiosk_config.json",
    );
    debugPrint("Kiosk config: $verify");
    if (verify.contains(target)) {
      debugPrint("Kiosk config set successfully");
    } else {
      debugPrint("Failed to set kiosk config");
    }
  }

  Future<void> stopKioskDaemon() async {
    await RootService.runCommand(
      "sh /data/adb/modules/kiosk_module/daemon.sh stop || sh /data/adb/modules_update/kiosk_module/daemon.sh stop",
    );
  }
}
