import 'dart:convert';
import 'package:flutter/material.dart';

class AppTile extends StatelessWidget {
  final Map<String, String> app;

  const AppTile({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // App Icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                // ignore: deprecated_member_use
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: app['icon'] != null
                ? Image.memory(
                    base64Decode(app['icon']!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFF3D3D3D),
                        child: const Icon(
                          Icons.android,
                          color: Colors.white,
                          size: 32,
                        ),
                      );
                    },
                  )
                : Container(
                    color: const Color(0xFF3D3D3D),
                    child: const Icon(
                      Icons.android,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        // App Name
        Text(
          app['name'] ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
