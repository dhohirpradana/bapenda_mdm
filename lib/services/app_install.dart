import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:bapenda_mdm/constants/constant.dart';

class AppInstallService {
  final PocketBase pb = PocketBase(Constants.pocketbaseUrl);

  /// 🔹 Cek log dari PocketBase, lalu download & install jika perlu
  Future<void> checkAndInstall(String deviceId) async {
    debugPrint('checkAndInstall: start for deviceId=$deviceId');

    try {
      final listResult = await pb
          .collection('install_logs')
          .getList(
            filter: 'device = "$deviceId" && stage = "pending"',
            expand: "app",
            perPage: 50,
          );

      debugPrint('Fetched ${listResult.items.length} records');

      if (listResult.items.isEmpty) return;

      for (final log in listResult.items) {
        final logId = log.id;
        debugPrint('Processing logId=$logId');

        final app = log.get<List<RecordModel>>("expand.app").first;

        final apkFilename = app.data['file']?.toString() ?? 'unknown.apk';
        final collectionId = app.data['collectionId'];
        final apkUrl =
            "${Constants.pocketbaseUrl}/api/files/$collectionId/${app.id}/$apkFilename";

        debugPrint('Log $logId -> apkUrl=$apkUrl');

        // mark as downloading
        await _safeUpdate(logId, {
          "stage": "downloading",
          "status": "in_progress",
        });

        try {
          // 🔹 download dan install dengan fungsi modular
          final savePath = await downloadFile(apkUrl, apkFilename);

          // mark as installing
          await _safeUpdate(logId, {
            "stage": "installing",
            "status": "in_progress",
          });

          final success = await silentInstall(savePath);

          if (success) {
            await _safeUpdate(logId, {
              "stage": "done",
              "status": "success",
              "message": "Installed OK",
            });
          } else {
            await _safeUpdate(logId, {
              "stage": "error",
              "status": "failed",
              "message": "Silent install failed",
            });
          }
        } catch (e) {
          await _safeUpdate(logId, {
            "stage": "error",
            "status": "failed",
            "message": "Exception: $e",
          });
        }
      }
    } catch (e) {
      debugPrint("checkAndInstall exception: $e");
    }

    debugPrint('checkAndInstall: finished for deviceId=$deviceId');
  }

  /// 🔹 Update log PocketBase aman
  Future<void> _safeUpdate(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('install_logs').update(id, body: body);
    } catch (e) {
      debugPrint("Failed to update log $id: $e");
    }
  }

  /// 🔹 Download file dengan Dio ke /data/local/tmp/
  Future<String> downloadFile(String url, String fileName) async {
    Dio dio = Dio();
    debugPrint("Download file from: $url");

    // Simpan dulu ke sandbox app (punya izin tulis)
    final dir =
        Directory.systemTemp.path; // atau getApplicationDocumentsDirectory()
    final localPath = "$dir/$fileName";

    await dio.download(url, localPath);

    debugPrint("Download selesai di: $localPath");

    // Pindahkan ke /data/local/tmp lewat root
    final tmpPath = "/data/local/tmp/$fileName";
    final result = await Process.run('su', [
      '-c',
      'cp "$localPath" "$tmpPath" && chmod 644 "$tmpPath"',
    ]);

    debugPrint("copy stdout: ${result.stdout}");
    debugPrint("copy stderr: ${result.stderr}");

    return tmpPath;
  }

  /// 🔹 Silent install pakai `su pm install`
  Future<bool> silentInstall(String apkPath) async {
    try {
      // pm install default expect file di /data/local/tmp
      ProcessResult result = await Process.run('su', [
        '-c',
        'pm install -r "$apkPath"',
      ]);

      debugPrint("stdout: ${result.stdout}");
      debugPrint("stderr: ${result.stderr}");
      return result.exitCode == 0;
    } catch (e) {
      debugPrint("Silent install error: $e");
      return false;
    }
  }

  /// 🔹 Ambil semua install_logs dengan status "pending" untuk device tertentu
  Future<List<RecordModel>> fetchPendingLogs(String deviceId) async {
    try {
      final result = await pb
          .collection('install_logs')
          .getList(
            filter: 'device = "$deviceId" && stage = "pending"',
            expand: "app",
            perPage: 50,
          );
      debugPrint(
        "Found ${result.items.length} pending logs for device=$deviceId",
      );
      return result.items;
    } catch (e) {
      debugPrint("Error fetching pending logs: $e");
      return [];
    }
  }
}
