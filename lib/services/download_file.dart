import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<File> downloadFile(String url, String filename) async {
  debugPrint("Downloading file from $url");

  final dir = await getApplicationDocumentsDirectory();
  final filePath = "${dir.path}/$filename";
  final file = File(filePath);

  // Cek apakah file sudah ada dan valid
  if (await file.exists() && await file.length() > 0) {
    debugPrint("File already exists and valid: $filePath");
    return file;
  }

  try {
    // Pastikan directory ada
    await file.parent.create(recursive: true);

    // Download dengan timeout dan retry logic
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 60);

    await dio.download(url, filePath);
    debugPrint("Downloaded $filename to $filePath");

    // Verifikasi file berhasil didownload
    if (!await file.exists() || await file.length() == 0) {
      throw Exception("Downloaded file is empty or corrupted");
    }
  } catch (e) {
    debugPrint("Failed to download $filename: $e");

    // Hapus file yang corrupt jika ada
    if (await file.exists()) {
      await file.delete();
    }

    rethrow;
  }

  return file;
}
