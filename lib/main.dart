import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/controllers/configuration_controller.dart';
import 'package:bapenda_mdm/screens/app_list_screen.dart';
import 'package:bapenda_mdm/screens/enroll_screen.dart';
import 'package:bapenda_mdm/services/background_service.dart';
import 'package:bapenda_mdm/services/pocketbase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // Restore auth & init controller
  await PocketBaseService.restoreAuth();
  Get.put(ConfigurationController());

  await initForegroundChannel();

  runApp(const MdmLauncherApp());
}

class MdmLauncherApp extends StatefulWidget {
  const MdmLauncherApp({super.key});
  static const MethodChannel _channel = MethodChannel('root/control');

  @override
  State<MdmLauncherApp> createState() => _MdmLauncherAppState();
}

class _MdmLauncherAppState extends State<MdmLauncherApp> {
  Future<void> startForegroundService() async {
    try {
      final result = await MdmLauncherApp._channel.invokeMethod(
        'startForegroundService',
      );
      debugPrint(result);
    } catch (e) {
      debugPrint('Error starting foreground service: $e');
    }
  }

  Future<void> startKioskWatchdogService() async {
    try {
      final result = await MdmLauncherApp._channel.invokeMethod(
        'startKioskWatchdogService',
      );
      debugPrint(result);
    } catch (e) {
      debugPrint('Error starting kiosk watchdog service: $e');
    }
  }

  // WifiAdbWatchdogService
  Future<void> startWifiAdbActivity() async {
    try {
      final result = await MdmLauncherApp._channel.invokeMethod(
        'startWifiAdbWatchdogService',
      );
      debugPrint(result);
    } catch (e) {
      debugPrint('Error starting wifi adb activity: $e');
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    startForegroundService();
    startKioskWatchdogService();
    startWifiAdbActivity();
    return GetMaterialApp(
      title: 'MDM Launcher',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/',
          page: () => GetBuilder<AuthController>(
            init: AuthController(),
            builder: (authCtrl) {
              if (authCtrl.loading.value) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }

              if (!authCtrl.isLoggedIn.value) {
                return const EnrollScreen();
              }

              return AppListScreen();
            },
          ),
        ),
        GetPage(name: '/enroll', page: () => const EnrollScreen()),
        GetPage(name: '/apps', page: () => AppListScreen()),
      ],
    );
  }
}
