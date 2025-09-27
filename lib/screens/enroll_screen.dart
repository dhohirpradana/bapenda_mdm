import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../controllers/configuration_controller.dart';
import '../services/pocketbase_service.dart';
import '../services/root_service.dart';
import 'app_list_screen.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen>
    with TickerProviderStateMixin {
  final TextEditingController codeController = TextEditingController();
  final TextEditingController displayNameController = TextEditingController();
  bool loading = false;
  String? errorMessage;
  String? tailscaleIp;
  AndroidDeviceInfo? androidInfo;
  Timer? _authTimer;
  Timer? _ipRefreshTimer;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _getDeviceInfo();
    getTailscaleIp();
    restoreAuth();

    _authTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      getTailscaleIp();
      restoreAuth();
    });

    _ipRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (tailscaleIp == null) {
        getTailscaleIp();
      }
    });
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    codeController.dispose();
    displayNameController.dispose();
    _authTimer?.cancel();
    _ipRefreshTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // restore auth
  Future<void> restoreAuth() async {
    try {
      await PocketBaseService.restoreAuth();
    } catch (e) {
      debugPrint("Error restoring auth: $e");
    }
  }

  void openSettings(BuildContext context) {
    Navigator.of(context).pop();
    RootService.openApp("com.android.settings");
  }

  Future<String?> getTailscaleIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );

    for (var iface in interfaces) {
      if (iface.name.contains("tailscale") || iface.name.contains("tun")) {
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            debugPrint("Tailscale IP: ${addr.address}");
            if (mounted) {
              setState(() {
                tailscaleIp = addr.address;
              });
            }
            return addr.address;
          }
        }
      }
    }
    return null;
  }

  Future<void> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo android = await deviceInfo.androidInfo;
    if (mounted) {
      setState(() {
        androidInfo = android;
      });
    }
  }

  Future<void> _scanQrPopup() async {
    HapticFeedback.lightImpact();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            height: 450,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A1A2E),
                  Color(0xFF16213E),
                  Color(0xFF0F0F0F),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF3B82F6).withOpacity(0.3),
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
                      Navigator.of(context).pop(code);
                    },
                  ),
                ),
                // Overlay with scanning guide
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.black.withOpacity(0.3),
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
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
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
                            color: Colors.black.withOpacity(0.8),
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
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        codeController.text = result;
      });
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _enroll() async {
    HapticFeedback.lightImpact();
    final code = codeController.text.trim();
    final displayName = displayNameController.text.trim();
    final ipAddress = await getTailscaleIp();

    if (ipAddress == null) {
      setState(() {
        tailscaleIp = null;
        errorMessage =
            "Tailscale IP tidak ditemukan. Pastikan Tailscale aktif.";
      });
      HapticFeedback.heavyImpact();
      return;
    }

    if (code.isEmpty) {
      setState(() {
        errorMessage = "Enrollment Code tidak boleh kosong";
      });
      HapticFeedback.heavyImpact();
      return;
    }

    if (displayName.isEmpty) {
      setState(() {
        errorMessage = "Device Name tidak boleh kosong";
      });
      HapticFeedback.heavyImpact();
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
        HapticFeedback.heavyImpact();
        return;
      }

      HapticFeedback.lightImpact();
      Get.put(ConfigurationController());

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                AppListScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: animation.drive(
                      Tween(
                        begin: const Offset(1.0, 0.0),
                        end: Offset.zero,
                      ).chain(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                    child: child,
                  );
                },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
      HapticFeedback.heavyImpact();
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
            animation: _fadeAnimation,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        _buildHeader(),
                        const SizedBox(height: 40),
                        if (androidInfo != null) ...[
                          _buildDeviceInfoCard(),
                          const SizedBox(height: 32),
                        ],
                        _buildEnrollmentForm(),
                        const SizedBox(height: 32),
                        _buildEnrollButton(),
                        const SizedBox(height: 20),
                        _buildFooterInfo(),
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

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
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
                      color: const Color(0xFF3B82F6).withOpacity(0.4),
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
          ),
          child: Text(
            "Register your device securely",
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1F2937).withOpacity(0.8),
            const Color(0xFF111827).withOpacity(0.9),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF3B82F6).withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Color(0xFF3B82F6),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Device Information",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                getTailscaleIp();
              },
              child: _buildDeviceInfoRow(
                "Network IP",
                tailscaleIp ?? "Detecting...",
                icon: Icons.wifi,
                isRefreshable: true,
                isConnected: tailscaleIp != null,
              ),
            ),
            _buildDeviceInfoRow(
              "Device Model",
              androidInfo!.model,
              icon: Icons.phone_android,
            ),
            _buildDeviceInfoRow(
              "Manufacturer",
              androidInfo!.manufacturer,
              icon: Icons.business,
            ),
            _buildDeviceInfoRow(
              "System Version",
              "Android ${androidInfo!.version.release}",
              icon: Icons.android,
            ),
            _buildDeviceInfoRow(
              "Hardware ID",
              androidInfo!.device,
              icon: Icons.memory,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoRow(
    String label,
    String value, {
    IconData? icon,
    bool isRefreshable = false,
    bool isConnected = true,
    bool isLast = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF374151).withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFF59E0B).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: isConnected
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              size: 20,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isRefreshable) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF10B981).withOpacity(0.2)
                    : const Color(0xFFF59E0B).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isConnected ? Icons.check_circle : Icons.refresh,
                color: isConnected
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnrollmentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFEF4444).withOpacity(0.1),
                  const Color(0xFFDC2626).withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.3),
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
                    errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        _buildInputField(
          label: "Enrollment Code",
          controller: codeController,
          hint: "Enter your enrollment code",
          prefixIcon: Icons.qr_code,
          suffixIcon: Icons.qr_code_scanner,
          onSuffixTap: _scanQrPopup,
        ),

        const SizedBox(height: 24),

        _buildInputField(
          label: "Device Name",
          controller: displayNameController,
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
                color: Colors.black.withOpacity(0.1),
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
                color: Colors.white.withOpacity(0.4),
                fontSize: 16,
              ),
              filled: true,
              fillColor: const Color(0xFF1F2937).withOpacity(0.8),
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
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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

  Widget _buildEnrollButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: loading
            ? null
            : const LinearGradient(
                colors: [
                  Color(0xFF3B82F6),
                  Color(0xFF1D4ED8),
                  Color(0xFF1E40AF),
                ],
              ),
        boxShadow: loading
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: SizedBox(
        height: 60,
        child: ElevatedButton(
          onPressed: loading ? null : _enroll,
          onLongPress: loading ? null : () => openSettings(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: loading ? Colors.grey[800] : Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: loading
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
  }

  Widget _buildFooterInfo() {
    return Container(
      // padding: const EdgeInsets.all(16),
      // decoration: BoxDecoration(
      //   color: const Color(0xFF1F2937).withOpacity(0.3),
      //   borderRadius: BorderRadius.circular(12),
      //   border: Border.all(color: Colors.white.withOpacity(0.1)),
      // ),
      // child: Row(
      //   children: [
      //     Icon(
      //       Icons.info_outline,
      //       color: Colors.white.withOpacity(0.6),
      //       size: 20,
      //     ),
      //     const SizedBox(width: 12),
      //     Expanded(
      //       child: Text(
      //         "Long press the enroll button to open device settings",
      //         style: TextStyle(
      //           color: Colors.white.withOpacity(0.6),
      //           fontSize: 14,
      //           fontWeight: FontWeight.w500,
      //         ),
      //       ),
      //     ),
      //   ],
      // ),
    );
  }
}
