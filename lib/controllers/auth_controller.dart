import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuthController extends GetxController {
  var isLoggedIn = false.obs;
  var loading = false.obs;
  var errorMessage = RxnString();
  final codeController = TextEditingController();
  var deviceDisplayName = ''.obs;
  var deviceId = ''.obs;
  var hasError = false.obs;

  // set logged in status
  void setLoggedIn(bool value) {
    isLoggedIn.value = value;
  }

  // set loading status
  void setLoading(bool value) {
    loading.value = value;
  }

  // set error message
  void setErrorMessage(String? message) {
    errorMessage.value = message;
  }

  // set device info
  void setDeviceInfo(String displayName, String id) {
    deviceDisplayName.value = displayName;
    deviceId.value = id;
  }

  void showErrorOnce(String title, String message) {
    if (!hasError.value) {
      hasError.value = true;
      setErrorMessage(message);
    }
  }

  void clearError() {
    if (hasError.value) {
      hasError.value = false;
      Get.closeAllSnackbars();
    }
  }
}
