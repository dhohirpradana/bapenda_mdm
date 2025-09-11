import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AuthController extends GetxController {
  var isLoggedIn = false.obs;
  var loading = false.obs;
  var errorMessage = RxnString();
  final codeController = TextEditingController();

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
}
