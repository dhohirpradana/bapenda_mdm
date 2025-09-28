import 'package:bapenda_mdm/controllers/auth_controller.dart';
import 'package:bapenda_mdm/services/background_service.dart'
    // ignore: library_prefixes
    as PocketBaseService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/configuration_controller.dart';
import '../services/root_service.dart';
import '../widgets/app_tile.dart';
import 'package:bapenda_mdm/services/kiosk_service.dart';

class AppListScreen extends StatefulWidget {
  const AppListScreen({super.key});

  @override
  State<AppListScreen> createState() => _AppListScreenState();
}

class _AppListScreenState extends State<AppListScreen>
    with TickerProviderStateMixin {
  final configCtrl = Get.find<ConfigurationController>();
  final KioskService kioskService = KioskService();

  int tapCount = 0;
  DateTime? lastTapTime;
  bool isLoading = false;

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
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> loadApps() async {
    HapticFeedback.lightImpact();
    setState(() {
      isLoading = true;
    });

    try {
      final data = await RootService.getInstalledApps();
      configCtrl.setInstalledApps(List<Map<String, String>>.from(data));
      HapticFeedback.lightImpact();
    } catch (e) {
      HapticFeedback.heavyImpact();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Restore auth
  Future<void> restoreAuth() async {
    HapticFeedback.mediumImpact();
    try {
      await PocketBaseService.restoreAuth();
      HapticFeedback.lightImpact();
    } catch (e) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> setKioskTarget(String packageName) async {
    await kioskService.setKioskConfig(enabled: false, target: packageName);
    await kioskService.stopKioskDaemon();
  }

  void handleSecretTap() {
    final now = DateTime.now();

    if (lastTapTime == null ||
        now.difference(lastTapTime!) > const Duration(seconds: 2)) {
      tapCount = 1;
    } else {
      tapCount++;
    }
    lastTapTime = now;

    if (tapCount >= 8) {
      tapCount = 0;
      HapticFeedback.heavyImpact();
      _showUnlockDialog();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _showUnlockDialog() {
    const pinLength = 6;
    final List<TextEditingController> controllers = List.generate(
      pinLength,
      (_) => TextEditingController(),
    );
    final List<FocusNode> focusNodes = List.generate(
      pinLength,
      (_) => FocusNode(),
    );

    void clearAll() {
      for (var c in controllers) {
        c.clear();
      }
      focusNodes.first.requestFocus();
    }

    void checkPin(BuildContext context) {
      final enteredPin = controllers.map((c) => c.text).join();
      if (enteredPin == "123312") {
        Navigator.of(context).pop();
        HapticFeedback.lightImpact();
        RootService.openApp("com.android.settings");
      } else {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Text("Wrong PIN", style: TextStyle(color: Colors.white)),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        clearAll();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F2937), Color(0xFF111827), Color(0xFF0F0F0F)],
            ),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.security, color: Color(0xFF3B82F6), size: 24),
                    SizedBox(width: 12),
                    Text(
                      "Enter Security PIN",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // PIN Input
              StatefulBuilder(
                builder: (context, setState) {
                  return Wrap(
                    spacing: 8,
                    children: List.generate(pinLength, (index) {
                      return Container(
                        width: 45,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: controllers[index].text.isNotEmpty
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6),
                            width: 2,
                          ),
                          color: const Color(0xFF374151).withValues(alpha: 0.3),
                        ),
                        child: TextField(
                          controller: controllers[index],
                          focusNode: focusNodes[index],
                          maxLength: 1,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            counterText: "",
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            setState(() {});
                            if (val.isNotEmpty) {
                              HapticFeedback.selectionClick();
                              if (index < pinLength - 1) {
                                FocusScope.of(
                                  context,
                                ).requestFocus(focusNodes[index + 1]);
                              } else {
                                checkPin(context);
                              }
                            }
                          },
                          onSubmitted: (_) {
                            if (index == pinLength - 1) {
                              checkPin(context);
                            }
                          },
                        ),
                      );
                    }),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      clearAll();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      backgroundColor: const Color(
                        0xFF3B82F6,
                      ).withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Clear",
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      if (focusNodes.first.canRequestFocus) {
        focusNodes.first.requestFocus();
      }
    });
  }

  void _showDeviceInfoSheet() {
    final authCtrl = Get.find<AuthController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1F2937), Color(0xFF111827)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Color(0xFF3B82F6),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      "Device Information",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Device info cards
                Obx(
                  () => Column(
                    children: [
                      _buildInfoCard(
                        icon: Icons.phone_android,
                        label: "Device Name",
                        value: authCtrl.deviceDisplayName.value.isNotEmpty
                            ? authCtrl.deviceDisplayName.value
                            : "Unknown Device",
                        color: const Color(0xFF10B981),
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(
                        icon: Icons.fingerprint,
                        label: "Device ID",
                        value: authCtrl.deviceId.value.isNotEmpty
                            ? authCtrl.deviceId.value
                            : "Unknown ID",
                        color: const Color(0xFF8B5CF6),
                        isCopyable: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Close",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isCopyable = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF374151).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          if (isCopyable) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text("Copied to clipboard"),
                      ],
                    ),
                    backgroundColor: const Color(0xFF10B981),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: Icon(Icons.copy, color: color, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.1),
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F0F0F),
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
                    child: Stack(
                      children: [
                        // Main app grid
                        Obx(() {
                          final apps = configCtrl.apps;

                          if (apps.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.apps,
                                    size: 64,
                                    color: Colors.white24,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    "No apps available",
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            child: GridView.builder(
                              padding: const EdgeInsets.all(20),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 0.85,
                                  ),
                              itemCount: apps.length,
                              itemBuilder: (context, index) {
                                final app = apps[index];
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    RootService.openApp(app['package'] ?? '');
                                  },
                                  child: AnimatedContainer(
                                    duration: Duration(
                                      milliseconds: 300 + (index * 50),
                                    ),
                                    curve: Curves.easeOutCubic,
                                    child: AppTile(app: app),
                                  ),
                                );
                              },
                            ),
                          );
                        }),

                        // Floating action buttons
                        Positioned(
                          right: 16,
                          top: MediaQuery.of(context).size.height / 2 - 80,
                          child: Column(
                            children: [
                              _buildFloatingButton(
                                icon: isLoading ? null : Icons.refresh,
                                onTap: restoreAuth,
                                onLongPress: restoreAuth,
                                color: const Color(0xFF10B981),
                                isLoading: isLoading,
                              ),

                              const SizedBox(height: 12),

                              _buildFloatingButton(
                                icon: Icons.settings,
                                onTap: handleSecretTap,
                                color: const Color(0xFF3B82F6),
                                pulseAnimation: _pulseAnimation,
                              ),

                              const SizedBox(height: 12),

                              _buildFloatingButton(
                                icon: Icons.info,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _showDeviceInfoSheet();
                                },
                                color: const Color(0xFF8B5CF6),
                              ),
                            ],
                          ),
                        ),

                        // Loading overlay
                        if (isLoading)
                          Container(
                            color: Colors.black.withValues(alpha: 0.3),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: Color(0xFF10B981),
                                    strokeWidth: 3,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    "Refreshing apps...",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingButton({
    IconData? icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Color color,
    bool isLoading = false,
    Animation<double>? pulseAnimation,
  }) {
    Widget button = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: Colors.white.withValues(alpha: 0.7),
                      strokeWidth: 1.5,
                    ),
                  )
                : Icon(
                    icon,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 16,
                  ),
          ),
        ),
      ),
    );

    if (pulseAnimation != null) {
      return AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) {
          return Transform.scale(scale: pulseAnimation.value, child: button);
        },
      );
    }

    return button;
  }
}
