import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:bapenda_mdm/constants/constant.dart';

class AppInstallService {
  final PocketBase pb = PocketBase(Constants.pocketbaseUrl);

  /// Cek log di PocketBase untuk device tertentu lalu install jika perlu
  Future<void> checkAndInstall(String deviceId) async {
    debugPrint('checkAndInstall: start for deviceId=$deviceId');

    try {
      final listResult = await pb
          .collection('install_logs')
          .getList(filter: 'device = "$deviceId"', expand: 'app', perPage: 50);

      debugPrint('Fetched ${listResult.items.length} records');

      if (listResult.items.isEmpty) return;

      for (final log in listResult.items) {
        final logId = log.id;
        debugPrint('Processing logId=$logId');

        final app = log.expand['app']?.first;
        if (app == null) {
          debugPrint('Log $logId has no expanded app -> skip');
          continue;
        }

        final apkFilename = app.data['file']?.toString() ?? 'unknown.apk';
        final collectionId = app.data['collectionId'];
        final apkUrl =
            "${Constants.pocketbaseUrl}/api/files/$collectionId/${app.id}/$apkFilename";

        // 🔹 Simpan ke app directory, bukan /data/local/tmp
        final dir = await getApplicationDocumentsDirectory();
        final savePath = "${dir.path}/$apkFilename";

        debugPrint('Log $logId -> apkUrl=$apkUrl');
        debugPrint('Log $logId -> savePath=$savePath');

        // mark as downloading
        await _safeUpdate(logId, {
          "stage": "downloading",
          "status": "in_progress",
        });

        // download file
        final client = HttpClient();
        try {
          final req = await client.getUrl(Uri.parse(apkUrl));
          final res = await req.close();
          if (res.statusCode != 200) {
            await _safeUpdate(logId, {
              "stage": "error",
              "status": "failed",
              "message": "Download failed ${res.statusCode}",
            });
            continue;
          }
          final file = File(savePath);
          final sink = file.openWrite();
          await res.pipe(sink);
          await sink.close();
        } catch (e) {
          await _safeUpdate(logId, {
            "stage": "error",
            "status": "failed",
            "message": "Exception download: $e",
          });
          continue;
        } finally {
          client.close();
        }

        // mark as installing
        await _safeUpdate(logId, {
          "stage": "installing",
          "status": "in_progress",
        });

        // jalankan pm install via su
        try {
          final result = await Process.run("su", [
            "-c",
            "pm install -r \"$savePath\"",
          ]);

          if (result.exitCode == 0) {
            await _safeUpdate(logId, {
              "stage": "done",
              "status": "success",
              "message": "Installed OK",
            });
          } else {
            await _safeUpdate(logId, {
              "stage": "error",
              "status": "failed",
              "message": result.stderr.toString(),
            });
          }
        } catch (e) {
          await _safeUpdate(logId, {
            "stage": "error",
            "status": "failed",
            "message": "Exception install: $e",
          });
        }
      }
    } catch (e) {
      debugPrint("checkAndInstall exception: $e");
    }

    debugPrint('checkAndInstall: finished for deviceId=$deviceId');
  }

  Future<void> _safeUpdate(String id, Map<String, dynamic> body) async {
    try {
      await pb.collection('install_logs').update(id, body: body);
    } catch (e) {
      debugPrint("Failed to update log $id: $e");
    }
  }
}
