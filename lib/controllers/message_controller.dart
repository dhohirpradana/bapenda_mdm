import 'package:get/get.dart';

class MessageController extends GetxController {
  // Menyimpan pesan error atau info
  final message = RxnString();

  // Status loading
  final isLoading = false.obs;

  void setMessage(String? newMessage) {
    message.value = newMessage;
  }

  void setLoading(bool value) {
    isLoading.value = value;
  }

  void clear() {
    message.value = null;
    isLoading.value = false;
  }
}
