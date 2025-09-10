// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';

// class ScreensaverPage extends StatefulWidget {
//   const ScreensaverPage({super.key});

//   @override
//   State<ScreensaverPage> createState() => _ScreensaverPageState();
// }

// class _ScreensaverPageState extends State<ScreensaverPage> {
//   static const platform = MethodChannel("root/control");

//   @override
//   void initState() {
//     super.initState();

//     // Lock orientation portrait
//     SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

//     // Hide system UI after first frame
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _hideSystemUI();
//     });
//   }

//   @override
//   void dispose() {
//     _showSystemUI();
//     // Restore all orientations
//     SystemChrome.setPreferredOrientations(DeviceOrientation.values);
//     super.dispose();
//   }

//   void _hideSystemUI() {
//     SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
//   }

//   void _showSystemUI() {
//     SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
//   }

//   void _resetTimer() {
//     platform.invokeMethod("sendResetIdle");
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Pastikan setiap build tetap immersive
//     _hideSystemUI();

//     return AnnotatedRegion<SystemUiOverlayStyle>(
//       value: SystemUiOverlayStyle.light, // ikon status bar putih
//       child: Scaffold(
//         extendBodyBehindAppBar: true,
//         backgroundColor: Colors.black,
//         body: GestureDetector(
//           behavior: HitTestBehavior.opaque,
//           onTap: () {
//             _resetTimer();
//             Navigator.of(context).pop(); // Tutup screensaver
//           },
//           child: const Center(
//             child: Text(
//               "Screensaver",
//               style: TextStyle(color: Colors.white, fontSize: 40),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
