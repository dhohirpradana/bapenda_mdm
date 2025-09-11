import 'package:bapenda_mdm/constants/constant.dart';
import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import '../controllers/configuration_controller.dart';

class PocketBaseService {
  static final String backendUrl = Constants.BACKEND_URL;
  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: backendUrl,
      connectTimeout: Duration(seconds: 10),
      receiveTimeout: Duration(seconds: 30),
    ),
  );
  static final pb = PocketBase(Constants.POCKETBASE_URL);
  static final storage = GetStorage();
  static String? _configurationId;
  static String? _deviceRecordId;

  static final configController = Get.put(ConfigurationController());
  static final authController = Get.put(AuthController());

  static Future<bool> enrollDevice({
    required String code,
    required String deviceId,
    required String displayName,
    required String platform,
    required String osVersion,
    required String appVersion,
    required String tailscaleIp,
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
      };

      // debugPrint("Enrolling device with data: $jsonData");

      final res = await dio.post('/enroll', data: jsonData);

      final data = res.data;
      final email = data['email'];
      final password = data['password'];
      _deviceRecordId = data['deviceRecordId'];
      _configurationId = data['configurationId'];

      debugPrint("Enroll response data: $data");

      // login ke PocketBase
      if (password != null && password.isNotEmpty) {
        await pb.collection('devices').authWithPassword(email, password);
      }

      // get configuration allowedApps from PocketBase
      final config = await pb
          .collection('configurations')
          .getOne(_configurationId!);
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

      // subscribe to device and configuration
      await subscribeToDevice(_deviceRecordId!);
      await subscribeToConfiguration(_configurationId!);

      authController.setLoading(false);

      return true;
    } catch (e) {
      debugPrint("Enroll error: $e");
      return false;
    }
  }

  static Future<void> subscribeToConfiguration(String configurationId) async {
    await pb.collection('configurations').subscribe(configurationId, (e) {
      if (e.record != null) {
        final recordData = e.record!.toJson();
        configController.updateFromPocketBase(recordData);
      }
    });

    // Ambil data awal dari configuration
    final config = await pb
        .collection('configurations')
        .getOne(configurationId);
    configController.updateFromPocketBase(config.toJson());
  }

  static Future<void> subscribeToDevice(String deviceRecordId) async {
    await pb.collection('devices').subscribe(deviceRecordId, (e) async {
      debugPrint("Device subscription event: $e");
      if (e.record != null) {
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

      // debugPrint("Configuration ID: $_configurationId");
      // debugPrint("Device ID: $deviceRecordId");

      // subscribe to device and configuration
      await subscribeToDevice(deviceRecordId);
      await subscribeToConfiguration(_configurationId!);

      // simpan configurationId
      storage.write('configurationId', _configurationId);

      authController.setLoggedIn(true);
    } catch (e) {
      debugPrint("Login error: $e");
      // authController.setLoggedIn(false);
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
