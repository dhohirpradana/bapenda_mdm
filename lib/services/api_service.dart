import 'dart:io';
import 'package:bapenda_mdm/constants/constant.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class ApiClient {
  static final backendUrl = Constants.backendUrl;
  // Development Dio instance
  static final Dio dioDev =
      Dio(
          BaseOptions(
            baseUrl: backendUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
        )
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.badCertificateCallback =
                (X509Certificate cert, String host, int port) {
                  return true;
                };
            return client;
          },
        );
  // Production Dio instance
  static final Dio dioProd = Dio(
    BaseOptions(
      baseUrl: backendUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
}
