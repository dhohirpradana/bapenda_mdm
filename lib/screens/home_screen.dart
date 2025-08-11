import 'package:bapenda_mdm/services/root_service.dart';
import 'package:flutter/material.dart';
import 'app_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("MDM Launcher")),
      body: Center(
        child: Column(
          children: [
            ElevatedButton(
              child: const Text("Show Installed Apps"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppListScreen()),
                );
              },
            ),
            ElevatedButton(
              onPressed: () {
                RootService.enableKiosk("com.whatsapp");
              },
              child: Text("Enable Kiosk"),
            ),
            ElevatedButton(
              onPressed: () {
                RootService.disableKiosk();
              },
              child: Text("Disable Kiosk"),
            ),
          ],
        ),
      ),
    );
  }
}
