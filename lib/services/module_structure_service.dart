// File: lib/services/module_structure_service.dart
import 'dart:convert';

import 'package:agent_windows/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ModuleField {
  final String name;
  final String type;
  final bool required;
  final dynamic defaultValue;

  ModuleField({
    required this.name,
    required this.type,
    this.required = false,
    this.defaultValue,
  });

  factory ModuleField.fromJson(Map<String, dynamic> json) {
    return ModuleField(
      name: json['name'],
      type: json['type'],
      required: json['required'] ?? false,
      defaultValue: json['default'],
    );
  }
}

class ModuleStructure {
  final String id;
  final String name;
  final String type;
  final List<ModuleField> fields;

  ModuleStructure({
    required this.id,
    required this.name,
    required this.type,
    required this.fields,
  });

  factory ModuleStructure.fromJson(Map<String, dynamic> json) {
    List<ModuleField> fields = [];
    
    // Parse os campos customizados se existirem
    if (json['custom_fields'] != null) {
      final Map<String, dynamic> customFields = json['custom_fields'];
      customFields.forEach((key, value) {
        fields.add(ModuleField(
          name: key,
          type: value['type'] ?? 'String',
          required: value['required'] ?? false,
        ));
      });
    }

    return ModuleStructure(
      id: json['_id'] ?? json['id'],
      name: json['name'],
      type: json['type'],
      fields: fields,
    );
  }
}

class ModuleStructureService {
  final AuthService _authService = AuthService();
  
  /// Busca a estrutura completa de um módulo específico
  Future<ModuleStructure?> fetchModuleStructure({
    required String serverUrl,
    required String token,
    required String moduleId,
  }) async {
    try {
      debugPrint('🔍 Buscando estrutura do módulo: $moduleId');
      
      // Usa os headers do AuthService
      final headers = _authService.getHeaders();
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/modules/$moduleId'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final structure = ModuleStructure.fromJson(data['module']);
        
        debugPrint('✅ Estrutura do módulo carregada: ${structure.name}');
        debugPrint('   Tipo: ${structure.type}');
        debugPrint('   Campos customizados: ${structure.fields.length}');
        
        return structure;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('❌ Token inválido ou expirado');
        throw Exception('Token inválido ou expirado');
      } else {
        debugPrint('❌ Erro ao buscar estrutura: ${response.statusCode}');
        throw Exception('Erro ao buscar estrutura: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Exceção ao buscar estrutura do módulo: $e');
      return null;
    }
  }

  /// Retorna os campos obrigatórios baseado no tipo de módulo
  Map<String, dynamic> getRequiredFieldsByType(String moduleType) {
    switch (moduleType.toLowerCase()) {
      case 'desktop':
        return {
          // Campos base
          'asset_name': null,
          'serial_number': null,
          'ip_address': null,
          'mac_address': null,
          
          // Campos específicos de Desktop
          'hostname': null,
          'model': null,
          'manufacturer': null,
          'processor': null,
          'ram': null,
          'storage': null,
          'storage_type': null,
          'operating_system': null,
          'os_version': null,
          
          // Periféricos
          'biometric_reader': null,
          'connected_printer': null,
          
          // Software
          'installed_software': [],
          'java_version': null,
          'browser_version': null,
          
          // Segurança
          'antivirus_status': false,
          'antivirus_version': null,
        };
      
      case 'notebook':
        return {
          // Campos base
          'asset_name': null,
          'serial_number': null,
          'ip_address': null,
          'mac_address': null,
          
          // Campos específicos de Notebook
          'hostname': null,
          'model': null,
          'manufacturer': null,
          'processor': null,
          'ram': null,
          'storage': null,
          'operating_system': null,
          'os_version': null,
          
          // Bateria
          'battery_level': null,
          'battery_health': null,
          
          // Software e Segurança
          'installed_software': [],
          'antivirus_status': false,
          'antivirus_version': null,
          'is_encrypted': false,
        };
      
      case 'panel':
        return {
          // Campos base
          'asset_name': null,
          'serial_number': null,
          'ip_address': null,
          'mac_address': null,
          
          // Campos específicos de Panel
          'hostname': null,
          'model': null,
          'manufacturer': null,
          'screen_size': null,
          'resolution': null,
          'firmware_version': null,
          'is_online': false,
          
          // Conteúdo
          'current_content': null,
          'content_last_updated': null,
          
          // Configurações
          'brightness': null,
          'volume': null,
          'hdmi_input': null,
          
          // Periféricos
          'connected_devices': [],
        };
      
      case 'printer':
        return {
          // Campos base
          'asset_name': null,
          'serial_number': null,
          'ip_address': null,
          'mac_address': null,
          
          // Campos específicos de Printer
          'hostname': null,
          'model': null,
          'manufacturer': null,
          'connection_type': 'network',
          'usb_port': null,
          
          // Status
          'printer_status': 'unknown',
          'error_message': null,
          
          // Contadores
          'total_page_count': null,
          'color_page_count': null,
          'black_white_page_count': null,
          
          // Consumíveis
          'toner_levels': {},
          'paper_level': null,
          
          // Capacidades
          'is_duplex': false,
          'is_color': false,
          'supported_paper_sizes': [],
          
          // Host (para impressoras USB)
          'host_computer_name': null,
          'host_computer_ip': null,
          
          // Firmware
          'firmware_version': null,
          'driver_version': null,
        };
      
      default:
        // Módulo customizado - apenas campos base
        return {
          'asset_name': null,
          'serial_number': null,
          'ip_address': null,
          'mac_address': null,
          'custom_data': {},
        };
    }
  }

  /// Valida se os dados coletados contêm os campos obrigatórios
  bool validateData(Map<String, dynamic> data, String moduleType) {
    final requiredFields = getRequiredFieldsByType(moduleType);
    
    for (final key in requiredFields.keys) {
      if (!data.containsKey(key) || data[key] == null) {
        if (requiredFields[key] == null && 
            !['installed_software', 'connected_devices', 'supported_paper_sizes'].contains(key)) {
          debugPrint('⚠️  Campo obrigatório ausente: $key');
          return false;
        }
      }
    }
    
    return true;
  }
}