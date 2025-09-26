import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
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
  final TextEditingController displayNameController = TextEditingController();
  bool loading = false;
  String? errorMessage;
  String? tailscaleIp;
  AndroidDeviceInfo? androidInfo;
  Timer? _authTimer;

  @override
  void dispose() {
    codeController.dispose();
    displayNameController.dispose();
    _authTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _getDeviceInfo();
    getTailscaleIp();
    restoreAuth();

    _authTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      getTailscaleIp();
      restoreAuth();
    });
  }

  // restore auth
  Future<void> restoreAuth() async {
    try {
      await PocketBaseService.restoreAuth();
    } catch (e) {
      debugPrint("Error restoring auth: $e");
    }
  }

  Future<String?> getTailscaleIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );

    for (var iface in interfaces) {
      if (iface.name.contains("tailscale") || iface.name.contains("tun")) {
        // biasanya "tailscale0"
        // ipv4 saja
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            debugPrint("Tailscale IP: ${addr.address}");
            setState(() {
              tailscaleIp = addr.address;
            });
            return addr.address;
          }
        }
      }
    }
    return null;
  }

  // get device info
  Future<void> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo android = await deviceInfo.androidInfo;
    setState(() {
      androidInfo = android;
    });
  }

  Future<void> _scanQrPopup() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 400,
            child: Stack(
              children: [
                MobileScanner(
                  controller: MobileScannerController(),
                  onDetect: (capture) {
                    final code = capture.barcodes.first.rawValue ?? "";
                    Navigator.of(context).pop(code); // langsung return QR
                  },
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        codeController.text = result;
      });
    }
  }

  Future<void> _enroll() async {
    final code = codeController.text.trim();
    final displayName = displayNameController.text.trim();
    final ipAddress = await getTailscaleIp();

    if (ipAddress == null) {
      setState(() {
        tailscaleIp = null;
        errorMessage =
            "Tailscale IP tidak ditemukan. Pastikan Tailscale aktif.";
      });
      return;
    }

    if (code.isEmpty) {
      setState(() {
        errorMessage = "Enrollment Code tidak boleh kosong";
      });
      return;
    }

    if (displayName.isEmpty) {
      setState(() {
        errorMessage = "Device Name tidak boleh kosong";
      });
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final deviceId = Uuid().v4();
      final result = await PocketBaseService.enrollDevice(
        code: code,
        deviceId: deviceId,
        displayName: displayName,
        platform: "Android",
        osVersion: androidInfo!.version.release,
        appVersion: "1.0.0",
        tailscaleIp: ipAddress,
        deviceModel: androidInfo!.model,
        manufacturer: androidInfo!.manufacturer,
        type: androidInfo!.device,
      );

      if (!result.success) {
        setState(() {
          errorMessage = result.message;
          loading = false;
        });
        return;
      }

      Get.put(ConfigurationController());

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
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section
              const SizedBox(height: 32),
              _buildHeader(),

              const SizedBox(height: 40),

              // Device Info Card
              if (androidInfo != null) ...[
                _buildDeviceInfoCard(),
                const SizedBox(height: 22),
              ],

              // Enrollment Form
              _buildEnrollmentForm(),

              const SizedBox(height: 32),

              // Enroll Button
              _buildEnrollButton(),
            ],
          ),
        ),
      ),
    );
  }

  // Header Widget
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.phone_android, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        const Text(
          "Device Enrollment",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Register your device to get started",
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // Device Info Card Widget
  Widget _buildDeviceInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: const Color(0xFF2563EB),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Device Information",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                getTailscaleIp();
              },
              child: _buildDeviceInfoRow(
                "IP Address",
                tailscaleIp ?? "Unknown",
              ),
            ),
            _buildDeviceInfoRow("Device", androidInfo!.model),
            _buildDeviceInfoRow("Manufacturer", androidInfo!.manufacturer),
            _buildDeviceInfoRow("Model Code", androidInfo!.device),
            _buildDeviceInfoRow(
              "Android Version",
              androidInfo!.version.release,
            ),
          ],
        ),
      ),
    );
  }

  // Device Info Row Widget
  Widget _buildDeviceInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(": ", style: TextStyle(color: Colors.white, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Enrollment Form Widget
  Widget _buildEnrollmentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          "Enrollment Code",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: codeController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: "Enter your enrollment code",
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
            filled: true,
            fillColor: const Color(0xFF1F1F1F),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
            prefixIcon: Icon(
              Icons.qr_code,
              color: Colors.white.withOpacity(0.5),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              onPressed: _scanQrPopup,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Device Name",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: displayNameController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: "Enter device display name",
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
            filled: true,
            fillColor: const Color(0xFF1F1F1F),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
            prefixIcon: Icon(
              Icons.phone_iphone,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }

  // Enroll Button Widget
  Widget _buildEnrollButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : _enroll,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[800],
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Enrolling...",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : const Text(
                "Enroll Device",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
