import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/controllers/configuration_controller.dart';
import 'package:bapenda_mdm/controllers/content_controller.dart';
import 'package:bapenda_mdm/models/result_model.dart';
import 'package:bapenda_mdm/services/api_service.dart';
import 'package:bapenda_mdm/services/device_service.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pocketbase/pocketbase.dart';

class PocketBaseService {
  static final String backendUrl = Constants.backendUrl;
  // static final Dio dio = Dio(
  //   BaseOptions(
  //     baseUrl: backendUrl,
  //     connectTimeout: const Duration(seconds: 15),
  //     receiveTimeout: const Duration(seconds: 30),
  //   ),
  // );
  static final Dio dio = ApiClient.dioProd;
  // PocketBase instance
  static final pb = PocketBase(Constants.pocketbaseUrl);
  static final storage = GetStorage();
  static String? _configurationId;
  static String? _deviceRecordId;

  // Controllers
  static final configController = Get.put(ConfigurationController());
  static final authController = Get.put(AuthController());

  /// ---------------- ENROLL DEVICE ----------------
  static Future<Result> enrollDevice({
    required String code,
    required String deviceId,
    required String displayName,
    required String platform,
    required String osVersion,
    required String appVersion,
    required String tailscaleIp,
    required String deviceModel,
    required String manufacturer,
    required String type,
  }) async {
    authController.setLoading(true);

    try {
      final jsonData = {
        "code": code,
        "ipAddress": tailscaleIp,
        "deviceId": deviceId,
        "displayName": displayName,
        "platform": platform,
        "osVersion": osVersion,
        "appVersion": appVersion,
        "deviceModel": deviceModel,
        "manufacturer": manufacturer,
        "type": type,
      };

      final res = await dio.post('/enroll', data: jsonData);
      final data = res.data;

      final email = data['email'];
      final password = data['password'];
      _deviceRecordId = data['deviceRecordId'];
      _configurationId = data['configurationId'];

      debugPrint("Enroll response data: $data");

      try {
        if (email != null && password != null && password.isNotEmpty) {
          await pb.collection('devices').authWithPassword(email, password);
        }

        await _loadConfiguration(_configurationId!);

        // Simpan auth & device info ke storage
        _saveAuthToStorage(email, password, data);

        await subscribeToDevice(_deviceRecordId!);
        await subscribeToConfiguration(_configurationId!);

        authController.setLoggedIn(true);
        authController.setLoading(false);

        return Result.ok("Berhasil enroll perangkat");
      } catch (e) {
        debugPrint("Enroll error: $e");
        authController.setLoading(false);
        await logout();
        return Result.fail("Gagal autentikasi device: $e");
      }
    } on DioException catch (e) {
      debugPrint("Enroll DioException: $e");
      authController.setLoading(false);
      if (e.response?.statusCode == 404) {
        return Result.fail("Code tidak valid atau sudah digunakan");
      }
      return _handleDioError(e);
    } catch (e) {
      authController.setLoading(false);
      debugPrint("Enroll error umum: $e");
      return Result.fail("Unexpected error: $e");
    }
  }

  /// ---------------- SUBSCRIBE ----------------
  /// Contents
  static Future<void> subscribeToContent(String contentId) async {
    await pb.collection('contents').subscribe(contentId, (e) {
      debugPrint("Content subscription event: $e");
      if (e.record != null) {
        // Handle content update if needed
        debugPrint("Content record updated: ${e.record!.toJson()}");
        final contentController = Get.find<ContentController>();
        contentController.updateImageVideo(e.record!);
      }
    });
  }

  /// ---------------- SUBSCRIBE ----------------
  static Future<void> subscribeToConfiguration(String configurationId) async {
    await pb.collection('configurations').subscribe(configurationId, (e) async {
      if (e.record != null) {
        final recordData = e.record!.toJson();
        recordData['allowedApps'] = await _resolveAllowedApps(
          recordData['allowedApps'],
        );
        // relation screensaverImage and screensaverVideo from tabel contents
        recordData['screensaverImage'] = await _resolveScreensaverImageVideo(
          recordData['screensaverImage'],
        );
        recordData['screensaverVideo'] = await _resolveScreensaverImageVideo(
          recordData['screensaverVideo'],
        );
        final targetApp = await _resolveTargetApp(recordData['kioskTarget']);
        if (targetApp != null) {
          recordData['kioskTarget'] = targetApp.data['packageId'];
        }
        configController.updateFromPocketBase(recordData);
      }
    });

    final config = await pb
        .collection('configurations')
        .getOne(configurationId);
    config.data['allowedApps'] = await _resolveAllowedApps(
      config.data['allowedApps'],
    );
    // relation screensaverImage and screensaverVideo from tabel contents
    config.data['screensaverImage'] = await _resolveScreensaverImageVideo(
      config.data['screensaverImage'],
    );
    config.data['screensaverVideo'] = await _resolveScreensaverImageVideo(
      config.data['screensaverVideo'],
    );
    final targetApp = await _resolveTargetApp(config.data['kioskTarget']);
    if (targetApp != null) {
      config.data['kioskTarget'] = targetApp.data['packageId'];
    }
    configController.updateFromPocketBase(config.toJson());
  }

  static Future<void> subscribeToDevice(String deviceRecordId) async {
    await pb.collection('devices').subscribe(deviceRecordId, (e) async {
      debugPrint("Device subscription event: $e");
      if (e.record != null) {
        authController.setDeviceInfo(
          e.record!.data['displayName'] ?? '',
          e.record!.id,
        );
        final newConfigId = e.record!.data['configuration'];
        if (newConfigId != null && newConfigId != _configurationId) {
          _configurationId = newConfigId;
          await subscribeToConfiguration(newConfigId);
        }
      }
    });
  }

  /// ---------------- REFRESH DEVICE & CONFIG ----------------
  static Future<void> refreshDeviceAndConfiguration(
    String deviceRecordId,
  ) async {
    debugPrint("Refreshing device and configuration for ID: $deviceRecordId");

    final email = storage.read('email');
    final password = storage.read('password');

    if (email == null || password == null) {
      debugPrint("Email or password is null");
      await _safeLogout("Email atau password kosong. Silakan enroll ulang.");
      return;
    }

    try {
      // 🔹 Re-authenticate device
      final device = await pb
          .collection('devices')
          .authWithPassword(email, password);

      _configurationId = device.record.data['configuration'];
      if (_configurationId == null) {
        throw Exception("Configuration ID tidak ditemukan di record device.");
      }

      // 🔹 Load configuration
      await _loadConfiguration(_configurationId!);

      // 🔹 Update device info ke server
      final deviceInfo = await pb.collection('devices').getOne(deviceRecordId);
      final deviceDetails = await DeviceService().getDeviceInfo();
      _mergeDeviceInfo(deviceDetails, deviceInfo.data);

      await pb
          .collection('devices')
          .update(deviceRecordId, body: deviceDetails);

      // 🔹 Subscribe realtime
      await subscribeToDevice(deviceRecordId);
      await subscribeToConfiguration(_configurationId!);

      // 🔹 Persist configuration ID
      storage.write('configurationId', _configurationId);

      // 🔹 Mark logged in
      authController.setLoggedIn(true);
    } catch (e, st) {
      debugPrint("Login error: $e\n$st");
      final errorStr = e.toString();

      if (errorStr.contains("SocketException") ||
          errorStr.contains("Network") ||
          errorStr.contains("Timeout")) {
        debugPrint("Network error, skip logout");
        authController.showErrorOnce(
          "Network Error",
          "Periksa koneksi internet Anda.",
        );
      } else {
        await _safeLogout(
          "Sesi Anda sudah berakhir, silakan enroll ulang.",
          title: "Login Gagal",
        );
      }
    }
  }

  /// Helper untuk logout yang aman
  static Future<void> _safeLogout(
    String message, {
    String title = "Logout",
  }) async {
    try {
      logout();
    } catch (e) {
      debugPrint("Logout error: $e");
    }

    try {
      KioskService().stopKioskDaemon();
    } catch (e) {
      debugPrint("KioskService stop error: $e");
    }

    try {
      disableScreensaver();
    } catch (e) {
      debugPrint("Disable screensaver error: $e");
    }

    authController.setLoggedIn(false);
    authController.showErrorOnce(title, message);
  }

  /// ---------------- RESTORE & LOGOUT ----------------
  static Future<void> restoreAuth() async {
    final deviceId = storage.read('deviceRecordId');
    debugPrint("Restoring auth, deviceId: $deviceId");
    if (deviceId != null) {
      await refreshDeviceAndConfiguration(deviceId);
    } else {
      authController.setLoggedIn(false);
    }
  }

  static Future<void> logout() async {
    pb.authStore.clear();
    storage.remove('token');
    storage.remove('user');
    storage.remove('deviceRecordId');
    storage.remove('configurationId');
    // storage.remove('email');
    // storage.remove('password');
    authController.setLoggedIn(false);
  }

  static bool isLoggedIn() {
    return storage.hasData('token') && storage.read('token') != null;
  }

  /// ---------------- PRIVATE HELPERS ----------------
  static Future<List<String>> _resolveAllowedApps(
    List<dynamic> allowedAppsIds,
  ) async {
    return await Future.wait(
      allowedAppsIds.map((id) async {
        final app = await pb.collection('apps').getOne(id);
        return app.data['packageId'] as String;
      }).toList(),
    );
  }

  static Future<void> _loadConfiguration(String configId) async {
    final config = await pb.collection('configurations').getOne(configId);
    config.data['allowedApps'] = await _resolveAllowedApps(
      config.data['allowedApps'],
    );
    // relation screensaverImage and screensaverVideo from tabel contents
    config.data['screensaverImage'] = await _resolveScreensaverImageVideo(
      config.data['screensaverImage'],
    );
    config.data['screensaverVideo'] = await _resolveScreensaverImageVideo(
      config.data['screensaverVideo'],
    );
    final targetApp = await _resolveTargetApp(config.data['kioskTarget']);
    if (targetApp != null) {
      config.data['kioskTarget'] = targetApp.data['packageId'];
    }
    configController.updateFromPocketBase(config.toJson());
  }

  // resolve targetApp from apps table
  static Future<dynamic> _resolveTargetApp(String? appId) async {
    if (appId == null || appId.isEmpty) return null;
    try {
      final app = await pb.collection('apps').getOne(appId);
      return app;
    } catch (e) {
      debugPrint("Error resolving target app: $e");
      return null;
    }
  }

  static Future<dynamic> _resolveScreensaverImageVideo(
    String? contentId,
  ) async {
    if (contentId == null || contentId.isEmpty) return null;
    try {
      final content = await pb.collection('contents').getOne(contentId);
      return content;
    } catch (e) {
      debugPrint("Error resolving screensaver image: $e");
      return null;
    }
  }

  static void _saveAuthToStorage(
    String email,
    String password,
    Map<String, dynamic> data,
  ) {
    storage.write('token', pb.authStore.token);
    // ignore: deprecated_member_use
    storage.write('user', pb.authStore.model.toJson());
    storage.write('deviceRecordId', data['deviceRecordId']);
    storage.write('configurationId', data['configurationId']);
    storage.write('email', email);
    storage.write('password', password);
  }

  static void _mergeDeviceInfo(
    Map<String, dynamic> deviceDetails,
    Map<String, dynamic> deviceInfoData,
  ) {
    if (deviceDetails['ipAddress'] == null) {
      deviceDetails['ipAddress'] = deviceInfoData['ipAddress'];
      deviceDetails['isVPNConnected'] = false;
    } else {
      deviceDetails['isVPNConnected'] = true;
    }
    deviceDetails['lastSeenAt'] = DateTime.now().toUtc().toIso8601String();
  }

  static Result _handleDioError(DioException e) {
    debugPrint("Enroll DioException: $e");
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Result.fail("Network timeout, periksa koneksi internet");
    } else if (e.type == DioExceptionType.badResponse) {
      return Result.fail("Server error: ${e.response?.statusCode}");
    } else {
      return Result.fail("Network error: ${e.message}");
    }
  }
}
