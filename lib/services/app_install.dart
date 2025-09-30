import 'dart:io';
import 'package:dio/dio.dart';
import 'package:bapenda_mdm/constants/constant.dart';

class AppInstallService {
  final Dio dio = Dio();

  /// Cek log di PocketBase untuk device tertentu
  Future<void> checkAndInstall(String deviceId) async {
    try {
      final response = await dio.get(
        "${Constants.pocketbaseUrl}/api/collections/install_logs/records",
        queryParameters: {
          "filter": '(device_id="$deviceId" && status!="success")',
          "expand": "app", // biar langsung dapat info APK
        },
      );

      final items = response.data['items'] as List<dynamic>;
      if (items.isEmpty) return;

      for (var log in items) {
        final logId = log['id'];
        final app = log['expand']['app'];

        final apkUrl =
            "${Constants.pocketbaseUrl}/api/files/apps/${app['id']}/${app['apk_file']}";
        final savePath = "/data/local/tmp/${app['apk_file']}";

        // update status → mulai download
        await dio.patch(
          "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
          data: {"stage": "downloading", "status": "in_progress"},
        );

        // download dengan progres
        await dio.download(
          apkUrl,
          savePath,
          onReceiveProgress: (received, total) async {
            if (total != -1) {
              final percent = (received / total * 100).toInt();
              await dio.patch(
                "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
                data: {"progress": percent, "stage": "downloading"},
              );
            }
          },
        );

        // jalankan silent install (root required)
        await dio.patch(
          "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
          data: {"progress": 100, "stage": "installing"},
        );

        try {
          final result = await Process.run("su", [
            "-c",
            "pm install -r $savePath",
          ]);

          if (result.exitCode == 0) {
            await dio.patch(
              "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
              data: {
                "status": "success",
                "stage": "done",
                "message": "Installed OK",
              },
            );
          } else {
            await dio.patch(
              "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
              data: {
                "status": "failed",
                "stage": "error",
                "message": result.stderr.toString(),
              },
            );
          }
        } catch (e) {
          await dio.patch(
            "${Constants.pocketbaseUrl}/api/collections/install_logs/records/$logId",
            data: {
              "status": "failed",
              "stage": "error",
              "message": e.toString(),
            },
          );
        }
      }
    } catch (e) {
      print("Error checking install logs: $e");
    }
  }
}
