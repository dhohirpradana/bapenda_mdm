import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/pocketbase_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/configuration_controller.dart';
import '../services/root_service.dart';
import '../widgets/app_tile.dart';

class AppListScreen extends StatelessWidget {
  AppListScreen({super.key});
  final configCtrl = Get.find<ConfigurationController>();
  final KioskService kioskService = KioskService();

  Future<void> loadApps() async {
    final data = await RootService.getInstalledApps();
    final filtered = data
        .where((app) => app['package'] != 'id.bapenda.mdm')
        .toList();
    configCtrl.setInstalledApps(List<Map<String, String>>.from(filtered));
  }

  Future<void> setKioskTarget(String packageName) async {
    // await RootService.setKioskTarget(packageName);
    // await setKioskConfig(enabled: true, target: packageName);
    // disable kiosk daemon first
    await kioskService.setKioskConfig(enabled: false, target: packageName);
    await kioskService.stopKioskDaemon();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Obx(() {
          final apps = configCtrl.apps;

          if (apps.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Loading apps...',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return GestureDetector(
                onTap: () => RootService.openApp(app['package'] ?? ''),
                onLongPress: () async {
                  await setKioskTarget(app['package'] ?? '');
                },
                child: AppTile(app: app),
              );
            },
          );
        }),
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF1A1A1A),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white),
              onPressed: () {},
              onLongPress: () {
                // RootService.rebootDevice();
                PocketBaseService.logout();
                // Navigator.of(context).push(
                //   MaterialPageRoute(builder: (_) => const ScreensaverPage()),
                // );
              },
            ),
          ],
        ),
      ),
    );
  }
}
