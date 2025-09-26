import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/services/background_service.dart'
    // ignore: library_prefixes
    as PocketBaseService;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/configuration_controller.dart';
import '../services/root_service.dart';
import '../widgets/app_tile.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';

class AppListScreen extends StatefulWidget {
  const AppListScreen({super.key});

  @override
  State<AppListScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<AppListScreen> {
  final configCtrl = Get.find<ConfigurationController>();
  final KioskService kioskService = KioskService();

  int tapCount = 0;
  DateTime? lastTapTime;

  Future<void> loadApps() async {
    final data = await RootService.getInstalledApps();
    configCtrl.setInstalledApps(List<Map<String, String>>.from(data));
  }

  // Restore auth
  Future<void> restoreAuth() async {
    await PocketBaseService.restoreAuth();
  }

  Future<void> setKioskTarget(String packageName) async {
    await kioskService.setKioskConfig(enabled: false, target: packageName);
    await kioskService.stopKioskDaemon();
  }

  void handleSecretTap() {
    final now = DateTime.now();

    if (lastTapTime == null ||
        now.difference(lastTapTime!) > Duration(seconds: 2)) {
      // reset jika terlalu lama
      tapCount = 1;
    } else {
      tapCount++;
    }
    lastTapTime = now;

    if (tapCount >= 8) {
      tapCount = 0;
      _showUnlockDialog();
    }
  }

  void _showUnlockDialog() {
    final pinLength = 8;
    final List<TextEditingController> controllers = List.generate(
      pinLength,
      (_) => TextEditingController(),
    );
    final List<FocusNode> focusNodes = List.generate(
      pinLength,
      (_) => FocusNode(),
    );

    void clearAll() {
      for (var c in controllers) {
        c.clear();
      }
      focusNodes.first.requestFocus();
    }

    void checkPin(BuildContext context) {
      final enteredPin = controllers.map((c) => c.text).join();
      if (enteredPin == "12344321") {
        Navigator.of(context).pop();
        RootService.openApp("com.android.settings");
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Wrong PIN")));
        clearAll();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Enter PIN", style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(pinLength, (index) {
                return SizedBox(
                  width: 40,
                  child: Padding(
                    padding: const EdgeInsets.all(1.0),
                    child: TextField(
                      controller: controllers[index],
                      focusNode: focusNodes[index],
                      maxLength: 1,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        counterText: "",
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.lightBlueAccent,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.black26,
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty) {
                          if (index < pinLength - 1) {
                            FocusScope.of(
                              context,
                            ).requestFocus(focusNodes[index + 1]);
                          } else {
                            // terakhir, cek PIN
                            checkPin(context);
                          }
                        }
                      },
                      onSubmitted: (_) {
                        if (index == pinLength - 1) {
                          checkPin(context);
                        }
                      },
                    ),
                  ),
                );
              }),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    // fokus awal ke kotak pertama
    Future.delayed(const Duration(milliseconds: 100), () {
      // ignore: use_build_context_synchronously
      FocusScope.of(context).requestFocus(focusNodes.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          children: [
            // Grid apps utama
            Obx(() {
              final apps = configCtrl.apps;

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: GridView.builder(
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
                      // onLongPress: () async {
                      //   await setKioskTarget(app['package'] ?? '');
                      // },
                      child: AppTile(app: app),
                    );
                  },
                ),
              );
            }),

            Positioned(
              right: 2,
              top: MediaQuery.of(context).size.height / 2 - 30,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: loadApps,
                    onLongPress: restoreAuth,
                    child: Opacity(
                      opacity: 0.1,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black12,
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.replay,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: handleSecretTap,
                    child: Opacity(
                      opacity: 0.1,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black12,
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onDoubleTap: () {
                      final authCtrl = Get.find<AuthController>();
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.black87,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        builder: (_) {
                          return Obx(
                            () => Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Device Info",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.phone_android,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          authCtrl
                                                  .deviceDisplayName
                                                  .value
                                                  .isNotEmpty
                                              ? authCtrl.deviceDisplayName.value
                                              : "Unknown",
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.fingerprint,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          authCtrl.deviceId.value.isNotEmpty
                                              ? authCtrl.deviceId.value
                                              : "Unknown",
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text(
                                        "Tutup",
                                        style: TextStyle(
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: Opacity(
                      opacity: 0.1,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black12,
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.info,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
