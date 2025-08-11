import 'package:flutter/material.dart';
import '../services/root_service.dart';
import '../widgets/app_tile.dart';

class AppListScreen extends StatefulWidget {
  const AppListScreen({super.key});

  @override
  State<AppListScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<AppListScreen> {
  List<Map<String, String>> apps = [];

  @override
  void initState() {
    super.initState();
    loadApps();
    // enableKioskLauncher();
  }

  void loadApps() async {
    final data = await RootService.getInstalledApps();
    setState(() {
      apps = data.where((app) => app['package'] != 'id.bapenda.mdm').toList();
    });
  }

  // Enable kiosk launcher
  void enableKioskLauncher() {
    RootService.enableKioskLauncher();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: apps.isEmpty
            ? Center(
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
              )
            : GridView.builder(
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
                    onTap: () {
                      RootService.openApp(app['package'] ?? '');
                    },
                    onLongPress: () =>
                        RootService.enableKiosk(app['package'] ?? ''),
                    child: AppTile(app: app),
                  );
                },
              ),
      ),
    );
  }
}
