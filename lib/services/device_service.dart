import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:get_storage_info/get_storage_info.dart';

class DeviceService {
  final Battery _battery = Battery();

  /// Ambil IP dari Tailscale (interface `tailscale0` atau `tun`)
  Future<String?> getTailscaleIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        if (iface.name.contains("tailscale") || iface.name.contains("tun")) {
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              debugPrint("Tailscale IP: ${addr.address}");
              return addr.address;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error getTailscaleIp: $e");
      return null;
    }
    return null;
  }

  /// Ambil informasi perangkat (battery, storage, tailscale IP)
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final batteryLevel = await _battery.batteryLevel;

      final totalGB = await GetStorageInfo.getStorageTotalSpaceInGB;
      final freeGB = await GetStorageInfo.getStorageFreeSpaceInGB;
      final usedGB = await GetStorageInfo.getStorageUsedSpaceInGB;

      debugPrint("Battery Level: $batteryLevel%");
      debugPrint("Storage Total: ${totalGB.toStringAsFixed(2)} GB");
      debugPrint("Storage Free : ${freeGB.toStringAsFixed(2)} GB");
      debugPrint("Storage Used : ${usedGB.toStringAsFixed(2)} GB");

      final tailscaleIp = await getTailscaleIp();
      debugPrint("Tailscale IP: $tailscaleIp");

      return {
        'batteryLevel': batteryLevel,
        'storageTotal': totalGB,
        'storageFree': freeGB,
        'storageUsed': usedGB,
        'ipAddress': tailscaleIp,
      };
    } catch (e) {
      debugPrint("Error getDeviceInfo: $e");
      return {
        'batteryLevel': null,
        'storageTotalGB': null,
        'storageFreeGB': null,
        'storageUsedGB': null,
        'ipAddress': null,
      };
    }
  }
}
