import 'package:bapenda_mdm/screens/app_list_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MdmLauncherApp());
}

class MdmLauncherApp extends StatelessWidget {
  const MdmLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Launcher',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const AppListScreen(),
    );
  }
}
