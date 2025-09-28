import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/controllers/configuration_controller.dart';
import 'package:bapenda_mdm/screens/app_list_screen.dart';
import 'package:bapenda_mdm/screens/enroll_screen.dart';
import 'package:bapenda_mdm/screens/root_required_app_screen.dart';
import 'package:bapenda_mdm/services/background_service.dart';
import 'package:bapenda_mdm/services/pocketbase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  // ✅ Minta permission storage dulu
  await requestStoragePermission();

  // ✅ Cek root dengan menjalankan "id"
  const MethodChannel rootChannel = MethodChannel('root/control');
  String rootCheck = "";
  try {
    final result = await rootChannel.invokeMethod("runCommand", {"cmd": "id"});
    rootCheck = result ?? "";
  } catch (e) {
    rootCheck = "";
  }

  if (rootCheck.isEmpty || !rootCheck.contains("uid=0")) {
    runApp(const RootRequiredApp());
    return;
  }

  // Restore auth & init controller
  await PocketBaseService.restoreAuth();
  Get.put(ConfigurationController());
  Get.put(AuthController());

  await initForegroundChannel();

  runApp(const MdmLauncherApp());
}

// ✅ Fungsi permission storage
Future<void> requestStoragePermission() async {
  if (!await Permission.manageExternalStorage.isGranted) {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      debugPrint("Storage permission denied! Folder access will fail.");
      runApp(const RootRequiredApp());
      return;
    }
  }
}

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AuthController>(() => AuthController());
    Get.lazyPut<ConfigurationController>(() => ConfigurationController());
  }
}

class MdmLauncherApp extends StatefulWidget {
  const MdmLauncherApp({super.key});
  static const MethodChannel _channel = MethodChannel('root/control');

  @override
  State<MdmLauncherApp> createState() => _MdmLauncherAppState();
}

class _MdmLauncherAppState extends State<MdmLauncherApp>
    with WidgetsBindingObserver {
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

  Future<void> startTouchDetectService() async {
    try {
      final result = await MdmLauncherApp._channel.invokeMethod(
        'startTouchDetectService',
      );
      debugPrint(result);
    } catch (e) {
      debugPrint('Error starting touch detect service: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startForegroundService();
      startKioskWatchdogService();
      startWifiAdbActivity();
      startTouchDetectService();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MDM Launcher',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      initialBinding: AppBinding(),
      getPages: [
        GetPage(
          name: '/',
          page: () {
            final authCtrl = Get.find<AuthController>();
            return Obx(() {
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
            });
          },
        ),
        GetPage(name: '/enroll', page: () => const EnrollScreen()),
        GetPage(name: '/apps', page: () => AppListScreen()),
      ],
    );
  }
}
