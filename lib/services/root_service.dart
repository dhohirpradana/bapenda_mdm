import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class RootService {
  static const MethodChannel _channel = MethodChannel('root/control');

  static Future<String> runCommand(String cmd) async {
    final result = await _channel.invokeMethod('runCommand', {"cmd": cmd});
    return result ?? '';
  }

  // openApp
  static Future<String> openApp(String packageName) async {
    debugPrint("Opening app: $packageName");
    final result = await _channel.invokeMethod('openApp', {
      "package": packageName,
    });
    return result ?? '';
  }

  static Future<List<Map<String, String>>> getInstalledApps() async {
    final List apps = await _channel.invokeMethod('getInstalledApps');
    return apps.map((e) => Map<String, String>.from(e)).toList();
  }

  // Enable kiosk mode
  static Future<void> enableKiosk(String packageName) async {
    await _channel.invokeMethod('enableKiosk', {"package": packageName});
  }

  // Enable kiosk mode launcher
  static Future<void> enableKioskLauncher() async {
    await _channel.invokeMethod('enableKioskLauncher');
  }

  // Disable kiosk mode
  static Future<void> disableKiosk() async {
    await _channel.invokeMethod('disableKiosk');
  }
}
