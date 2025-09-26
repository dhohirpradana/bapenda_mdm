import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/models/result_model.dart';
import 'package:bapenda_mdm/services/device_service.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';
import 'package:bapenda_mdm/services/root_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import '../controllers/configuration_controller.dart';

class PocketBaseService {
  static final String backendUrl = Constants.BACKEND_URL;
  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: backendUrl,
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 30),
    ),
  );
  static final pb = PocketBase(Constants.POCKETBASE_URL);
  static final storage = GetStorage();
  static String? _configurationId;
  static String? _deviceRecordId;

  static final configController = Get.put(ConfigurationController());
  static final authController = Get.put(AuthController());

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
    try {
      authController.setLoading(true);

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
        // login ke PocketBase
        if (password != null && password.isNotEmpty) {
          await pb.collection('devices').authWithPassword(email, password);
        }

        // get configuration allowedApps dari PocketBase
        final config = await pb
            .collection('configurations')
            .getOne(_configurationId!);

        final allowedApps = config.data['allowedApps'] as List<dynamic>;
        final appNames = await Future.wait(
          allowedApps.map((id) async {
            final app = await pb.collection('apps').getOne(id);
            return app.data['packageId'];
          }).toList(),
        );

        config.data['allowedApps'] = appNames;
        debugPrint("Allowed apps: $appNames");

        configController.updateFromPocketBase(config.toJson());
        authController.setLoggedIn(true);

        // simpan auth
        storage.write('token', pb.authStore.token);
        storage.write('user', pb.authStore.model.toJson());
        storage.write('deviceRecordId', data['deviceRecordId']);
        storage.write('configurationId', data['configurationId']);

        // simpan auth email password
        storage.write('email', email);
        storage.write('password', password);

        // subscribe ke device dan configuration
        await subscribeToDevice(_deviceRecordId!);
        await subscribeToConfiguration(_configurationId!);

        authController.setLoading(false);

        return Result.ok("Berhasil enroll perangkat");
      } catch (e) {
        debugPrint("Enroll error Pocketbase: $e");
        return Result.fail("PocketBase error: $e");
      }
    } on DioException catch (e) {
      // khusus untuk network error
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
    } catch (e) {
      debugPrint("Enroll error umum: $e");
      // jika status code 404
      if (e is DioException && e.response?.statusCode == 404) {
        return Result.fail("Code tidak valid atau sudah digunakan");
      }
      return Result.fail("Unexpected error: $e");
    }
  }

  static Future<void> subscribeToConfiguration(String configurationId) async {
    await pb.collection('configurations').subscribe(configurationId, (e) {
      if (e.record != null) {
        final recordData = e.record!.toJson();
        // AllowedApps masih [id, id] dari table apps, perlu diubah ke nama package
        final allowedApps = recordData['allowedApps'] as List<dynamic>;
        debugPrint(
          "Configuration subscription event allowedApps: $allowedApps",
        );
        Future.wait(
          allowedApps.map((id) async {
            final app = await pb.collection('apps').getOne(id);
            return app.data['packageId'];
          }).toList(),
        ).then((appNames) {
          recordData['allowedApps'] = appNames;
          debugPrint("Configuration subscription event: $recordData");
          configController.updateFromPocketBase(recordData);
        });
      }
    });

    // Ambil data awal dari configuration
    final config = await pb
        .collection('configurations')
        .getOne(configurationId);

    // AllowedApps masih [id, id] dari table apps, perlu diubah ke nama package
    final allowedApps = config.data['allowedApps'] as List<dynamic>;
    final appNames = await Future.wait(
      allowedApps.map((id) async {
        final app = await pb.collection('apps').getOne(id);
        return app.data['packageId'];
      }).toList(),
    );
    config.data['allowedApps'] = appNames;
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

  // refresh device and configuration by device ID
  static Future<void> refreshDeviceAndConfiguration(
    String deviceRecordId,
  ) async {
    debugPrint("Refreshing device and configuration for ID: $deviceRecordId");

    final email = storage.read('email');
    final password = storage.read('password');

    // validate email and password
    if (email == null || password == null) {
      debugPrint("Email or password is null");
      logout();
      RootService.disableKiosk();
      authController.setLoggedIn(false);
      return;
    }

    try {
      debugPrint("Logging in with email: $email");

      // login ke PocketBase
      final device = await pb
          .collection('devices')
          .authWithPassword(email, password);

      debugPrint("Logged in as: ${device.record.data['displayName']}");
      _configurationId = device.record.data['configuration'];

      // get configuration allowedApps from PocketBase
      final config = await pb
          .collection('configurations')
          .getOne(_configurationId!);
      configController.updateFromPocketBase(config.toJson());

      // get latest device record
      final deviceInfo = await pb.collection('devices').getOne(deviceRecordId);

      final DeviceService deviceService = DeviceService();
      final deviceDetails = await deviceService.getDeviceInfo();

      // cek ip address
      if (deviceDetails['ipAddress'] == null) {
        deviceDetails['ipAddress'] = deviceInfo.data['ipAddress'];
        deviceDetails['isVPNConnected'] = false;
      } else {
        deviceDetails['isVPNConnected'] = true;
      }

      Map<String, dynamic> updateData = {
        'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
        'batteryLevel': deviceDetails['batteryLevel'],
        'storageFree': deviceDetails['storageFree'],
        'storageTotal': deviceDetails['storageTotal'],
        'storageUsed': deviceDetails['storageUsed'],
        'ipAddress': deviceDetails['ipAddress'],
        'isVPNConnected': deviceDetails['isVPNConnected'],
      };

      await pb.collection('devices').update(deviceRecordId, body: updateData);

      // subscribe
      await subscribeToDevice(deviceRecordId);
      await subscribeToConfiguration(_configurationId!);

      // simpan config id
      storage.write('configurationId', _configurationId);

      authController.setLoggedIn(true);
    } catch (e) {
      debugPrint("Login error: $e");

      final errorStr = e.toString();

      // kalau error jaringan → jangan logout
      if (errorStr.contains("SocketException") ||
          errorStr.contains("Network") ||
          errorStr.contains("Timeout")) {
        debugPrint("Network error, skip logout");
        // tetap logged in
      } else {
        // selain network error (misalnya unauthorized / invalid credential)
        debugPrint("Non-network error, logging out");
        authController.setLoggedIn(false);
        // logout();
        // disable kiosk mode
        RootService.disableKiosk();
        KioskService().stopKioskDaemon();
        // disable screensaver
        disableScreensaver();
        Get.offAllNamed('/enroll');
      }

      return;
    }
  }

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
    storage.remove('email');
    storage.remove('password');
    authController.setLoggedIn(false);
  }

  static bool isLoggedIn() {
    return storage.hasData('token') && storage.read('token') != null;
  }
}
