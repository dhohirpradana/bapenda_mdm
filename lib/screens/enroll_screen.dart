// EnrollController
import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../services/pocketbase_service.dart';
import '../services/root_service.dart';
import '../controllers/configuration_controller.dart';
import 'app_list_screen.dart';

class EnrollController extends GetxController with GetTickerProviderStateMixin {
  // Text controllers
  final codeController = TextEditingController();
  final displayNameController = TextEditingController();

  // Reactive variables
  final loading = false.obs;
  final errorMessage = RxnString();
  final tailscaleIp = RxnString();
  final androidInfo = Rxn<AndroidDeviceInfo>();

  // Timers
  Timer? _authTimer;
  Timer? _ipRefreshTimer;

  // Animation controllers
  late AnimationController fadeController;
  late AnimationController slideController;
  late AnimationController pulseController;
  late Animation<double> fadeAnimation;
  late Animation<Offset> slideAnimation;
  late Animation<double> pulseAnimation;

  @override
  void onInit() {
    super.onInit();
    _initAnimations();
    _getDeviceInfo();
    getTailscaleIp();
    restoreAuth();
    _startTimers();
  }

  @override
  void onClose() {
    codeController.dispose();
    displayNameController.dispose();
    _authTimer?.cancel();
    _ipRefreshTimer?.cancel();
    fadeController.dispose();
    slideController.dispose();
    pulseController.dispose();
    super.onClose();
  }

  void _initAnimations() {
    fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: fadeController, curve: Curves.easeOut));

    slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: slideController, curve: Curves.easeOutBack),
        );

    pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
    );

    fadeController.forward();
    slideController.forward();
    pulseController.repeat(reverse: true);
  }

  void _startTimers() {
    _authTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      getTailscaleIp();
      restoreAuth();
    });

    _ipRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (tailscaleIp.value == null) {
        getTailscaleIp();
      }
    });
  }

  Future<void> restoreAuth() async {
    try {
      await PocketBaseService.restoreAuth();
    } catch (e) {
      debugPrint("Error restoring auth: $e");
    }
  }

  Future<void> getTailscaleIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );

      for (var iface in interfaces) {
        if (iface.name.contains("tailscale") || iface.name.contains("tun")) {
          for (var addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              debugPrint("Tailscale IP: ${addr.address}");
              tailscaleIp.value = addr.address;
              return;
            }
          }
        }
      }
      tailscaleIp.value = null;
    } catch (e) {
      debugPrint("Error getting Tailscale IP: $e");
      tailscaleIp.value = null;
    }
  }

  Future<void> _getDeviceInfo() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo android = await deviceInfo.androidInfo;
      androidInfo.value = android;
    } catch (e) {
      debugPrint("Error getting device info: $e");
    }
  }

  Future<void> scanQrCode() async {
    HapticFeedback.lightImpact();

    final result = await Get.dialog<String>(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          height: 450,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F0F0F)],
            ),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: MobileScanner(
                  controller: MobileScannerController(),
                  onDetect: (capture) {
                    final code = capture.barcodes.first.rawValue ?? "";
                    Get.back(result: code);
                  },
                ),
              ),
              // Overlay with scanning guide
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.black.withValues(alpha: 0.3),
                ),
                child: Stack(
                  children: [
                    // Scanning frame
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF3B82F6),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    // Close button
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () => Get.back(),
                        ),
                      ),
                    ),
                    // Instructions
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Position QR code within the frame",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      codeController.text = result;
      HapticFeedback.lightImpact();
    }
  }

  Future<void> enroll() async {
    HapticFeedback.lightImpact();

    final code = codeController.text.trim();
    final displayName = displayNameController.text.trim();

    // Validation
    if (tailscaleIp.value == null) {
      errorMessage.value =
          "Tailscale IP tidak ditemukan. Pastikan Tailscale aktif.";
      HapticFeedback.heavyImpact();
      return;
    }

    if (code.isEmpty) {
      errorMessage.value = "Enrollment Code tidak boleh kosong";
      HapticFeedback.heavyImpact();
      return;
    }

    if (displayName.isEmpty) {
      errorMessage.value = "Device Name tidak boleh kosong";
      HapticFeedback.heavyImpact();
      return;
    }

    if (androidInfo.value == null) {
      errorMessage.value = "Device information not available";
      HapticFeedback.heavyImpact();
      return;
    }

    loading.value = true;
    errorMessage.value = null;

    try {
      final deviceId = const Uuid().v4();
      final result = await PocketBaseService.enrollDevice(
        code: code,
        deviceId: deviceId,
        displayName: displayName,
        platform: "Android",
        osVersion: androidInfo.value!.version.release,
        appVersion: "1.0.0",
        tailscaleIp: tailscaleIp.value!,
        deviceModel: androidInfo.value!.model,
        manufacturer: androidInfo.value!.manufacturer,
        type: androidInfo.value!.device,
      );

      if (!result.success) {
        errorMessage.value = result.message;
        HapticFeedback.heavyImpact();
        return;
      }

      HapticFeedback.lightImpact();
      Get.put(ConfigurationController());

      Get.off(
        () => const AppListScreen(),
        transition: Transition.rightToLeft,
        duration: const Duration(milliseconds: 300),
      );
    } catch (e) {
      errorMessage.value = e.toString();
      HapticFeedback.heavyImpact();
    } finally {
      loading.value = false;
    }
  }

  void openSettings() {
    RootService.openApp("com.android.settings");
  }
}

// EnrollScreen Widget
class EnrollScreen extends StatelessWidget {
  const EnrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(EnrollController());

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), // Set scaffold background
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0B),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F0F0F),
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: controller.fadeAnimation,
            builder: (context, child) {
              return FadeTransition(
                opacity: controller.fadeAnimation,
                child: SlideTransition(
                  position: controller.slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        _buildHeader(controller),
                        const SizedBox(height: 40),
                        Obx(() {
                          if (controller.androidInfo.value != null) {
                            return Column(
                              children: [
                                _buildDeviceInfoCard(controller),
                                const SizedBox(height: 32),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                        _buildEnrollmentForm(controller),
                        const SizedBox(height: 32),
                        _buildEnrollButton(controller),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(EnrollController controller) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: controller.pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: controller.pulseAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF3B82F6),
                      Color(0xFF1D4ED8),
                      Color(0xFF1E40AF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.devices, color: Colors.white, size: 50),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        const Text(
          "Device Enrollment",
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard(EnrollController controller) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1F2937).withValues(alpha: 0.8),
            const Color(0xFF111827).withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Color(0xFF3B82F6),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Device Information",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Obx(
                    () => _buildCompactInfoItem(
                      Icons.wifi,
                      controller.tailscaleIp.value ?? "Detecting...",
                      isConnected: controller.tailscaleIp.value != null,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        controller.getTailscaleIp();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(
                    () => _buildCompactInfoItem(
                      Icons.phone_android,
                      controller.androidInfo.value?.model ?? "Unknown",
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Obx(
                    () => _buildCompactInfoItem(
                      Icons.android,
                      controller.androidInfo.value != null
                          ? "Android ${controller.androidInfo.value!.version.release}"
                          : "Unknown",
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(
                    () => _buildCompactInfoItem(
                      Icons.business,
                      controller.androidInfo.value?.manufacturer ?? "Unknown",
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactInfoItem(
    IconData icon,
    String value, {
    bool isConnected = true,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF374151).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isConnected
                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                : const Color(0xFFF59E0B).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isConnected
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              size: 18,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnrollmentForm(EnrollController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          if (controller.errorMessage.value != null) {
            return Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFEF4444).withValues(alpha: 0.1),
                    const Color(0xFFDC2626).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.errorMessage.value!,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }),

        _buildInputField(
          label: "Enrollment Code",
          controller: controller.codeController,
          hint: "Enter your enrollment code",
          prefixIcon: Icons.qr_code,
          suffixIcon: Icons.qr_code_scanner,
          onSuffixTap: controller.scanQrCode,
        ),

        const SizedBox(height: 24),

        _buildInputField(
          label: "Device Name",
          controller: controller.displayNameController,
          hint: "Enter device display name",
          prefixIcon: Icons.device_hub,
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    IconData? suffixIcon,
    VoidCallback? onSuffixTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 16,
              ),
              filled: true,
              fillColor: const Color(0xFF1F2937).withValues(alpha: 0.8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF3B82F6),
                  width: 2,
                ),
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  prefixIcon,
                  color: const Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              suffixIcon: suffixIcon != null
                  ? Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: Icon(
                          suffixIcon,
                          color: const Color(0xFF3B82F6),
                          size: 24,
                        ),
                        onPressed: onSuffixTap,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnrollButton(EnrollController controller) {
    return Obx(() {
      final isLoading = controller.loading.value;

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isLoading
              ? null
              : const LinearGradient(
                  colors: [
                    Color(0xFF3B82F6),
                    Color(0xFF1D4ED8),
                    Color(0xFF1E40AF),
                  ],
                ),
          boxShadow: isLoading
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: SizedBox(
          height: 60,
          child: ElevatedButton(
            onPressed: isLoading ? null : controller.enroll,
            onLongPress: isLoading ? null : controller.openSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: isLoading
                  ? Colors.grey[800]
                  : Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        "Enrolling Device...",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.security, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        "Enroll Device",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}
