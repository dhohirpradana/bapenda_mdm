import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/configuration_controller.dart';
import '../services/pocketbase_service.dart';
import 'app_list_screen.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  final TextEditingController codeController = TextEditingController();
  bool loading = false;
  String? errorMessage;

  Future<void> _enroll() async {
    final code = codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        errorMessage = "Code tidak boleh kosong";
      });
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final result = await PocketBaseService.enrollDevice(
        code: code,
        deviceId: "TEST_DEVICE",
        displayName: "My Device",
        platform: "Android",
        osVersion: "14",
        appVersion: "1.0.0",
      );

      debugPrint("Enroll result: $result");

      if (!result) {
        setState(() {
          errorMessage = "Enrollment failed. Please try again.";
        });
        return;
      }

      // Init controller & subscribe config
      Get.put(ConfigurationController());

      // Navigate to AppListScreen using Navigator
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => AppListScreen()),
      );
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Enroll Device",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Enrollment Code",
                  labelStyle: const TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : _enroll,
                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Enroll"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
