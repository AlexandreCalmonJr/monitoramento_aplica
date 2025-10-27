// File: lib/models/module_info.dart
import 'package:flutter/material.dart';

class ModuleInfo {
  final String id;
  final String name;
  final String type;
  final String description;
  final int assetCount;

  ModuleInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.assetCount,
  });

  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    return ModuleInfo(
      id: json['_id'] ?? json['id'],
      name: json['name'],
      type: json['type'],
      description: json['description'] ?? '',
      assetCount: json['asset_count'] ?? 0,
    );
  }

  // Ícone baseado no tipo
  IconData get icon {
    switch (type.toLowerCase()) {
      case 'desktop':
        return Icons.computer;
      case 'notebook':
        return Icons.laptop;
      case 'panel':
        return Icons.tv;
      case 'printer':
        return Icons.print;
      case 'mobile':
        return Icons.smartphone;
      case 'totem':
        return Icons.account_box;
      default:
        return Icons.device_unknown;
    }
  }

  // Cor baseada no tipo
  Color get color {
    switch (type.toLowerCase()) {
      case 'desktop':
        return Colors.blue;
      case 'notebook':
        return Colors.purple;
      case 'panel':
        return Colors.orange;
      case 'printer':
        return Colors.green;
      case 'mobile':
        return Colors.teal;
      case 'totem':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}