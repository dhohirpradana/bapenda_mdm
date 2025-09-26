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

      Get.showSnackbar(
        GetSnackBar(
          titleText: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          messageText: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          duration: const Duration(days: 1), // biar tetap muncul
          isDismissible: false,
        ),
      );
    }
  }

  void clearError() {
    if (hasError.value) {
      hasError.value = false;
      Get.closeAllSnackbars();
    }
  }
}
