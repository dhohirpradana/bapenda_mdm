import 'package:bapenda_mdm/screens/app_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MdmLauncherApp());
}

class MdmLauncherApp extends StatelessWidget {
  const MdmLauncherApp({super.key});
  static const MethodChannel _channel = MethodChannel('root/control');

  Future<void> startForegroundService() async {
    try {
      final result = await _channel.invokeMethod('startForegroundService');
      debugPrint(result);
    } catch (e) {
      debugPrint('Error starting foreground service: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    startForegroundService();
    return MaterialApp(
      title: 'MDM Launcher',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const AppListScreen(),
    );
  }
}
