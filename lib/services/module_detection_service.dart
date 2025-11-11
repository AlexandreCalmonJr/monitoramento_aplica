// File: lib/services/module_detection_service.dart
// Descrição: Detecta se deve usar sistema novo de módulos ou sistema legado de Totem
import 'dart:convert';

import 'package:agent_windows/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

enum SystemType {
  newModules, // Sistema novo com módulos customizados
  legacyTotem, // Sistema legado de Totem
  both, // Ambos sistemas ativos
}

class ModuleDetectionResult {
  final SystemType systemType;
  final bool hasNewModules;
  final bool hasLegacyTotem;
  final String? primaryModuleId; // ID do módulo principal (se sistema novo)
  final String? primaryModuleType; // Tipo do módulo principal

  ModuleDetectionResult({
    required this.systemType,
    required this.hasNewModules,
    required this.hasLegacyTotem,
    this.primaryModuleId,
    this.primaryModuleType,
  });
}

class ModuleDetectionService {
  final Logger _logger;
  final AuthService _authService;

  ModuleDetectionService(this._logger, this._authService);

  /// Detecta qual sistema está ativo no servidor
  Future<ModuleDetectionResult> detectActiveSystem({
    required String serverUrl,
    required String token,
  }) async {
    _logger.i('🔍 Detectando sistema ativo no servidor...');

    bool hasNewModules = false;
    bool hasLegacyTotem = false;
    String? primaryModuleId;
    String? primaryModuleType;

    // 1. Verifica se o sistema novo de módulos está ativo
    try {
      final newModulesActive = await _checkNewModulesSystem(serverUrl, token);
      if (newModulesActive != null) {
        hasNewModules = true;
        primaryModuleId = newModulesActive['id'];
        primaryModuleType = newModulesActive['type'];
        _logger.i('✅ Sistema novo de módulos detectado');
        _logger.d('   Módulo principal: ${newModulesActive['name']} (${newModulesActive['type']})');
      }
    } catch (e) {
      _logger.w('⚠️ Sistema novo de módulos não disponível: $e');
    }

    // 2. Verifica se o sistema legado de Totem está ativo
    try {
      hasLegacyTotem = await _checkLegacyTotemSystem(serverUrl);
      if (hasLegacyTotem) {
        _logger.i('✅ Sistema legado de Totem detectado');
      }
    } catch (e) {
      _logger.w('⚠️ Sistema legado de Totem não disponível: $e');
    }

    // 3. Determina qual sistema usar
    SystemType systemType;
    if (hasNewModules && hasLegacyTotem) {
      systemType = SystemType.both;
      _logger.i('📊 Ambos os sistemas estão ativos (prioridade: novo)');
    } else if (hasNewModules) {
      systemType = SystemType.newModules;
      _logger.i('📊 Usando sistema novo de módulos');
    } else if (hasLegacyTotem) {
      systemType = SystemType.legacyTotem;
      _logger.i('📊 Usando sistema legado de Totem');
    } else {
      _logger.e('❌ Nenhum sistema detectado no servidor!');
      throw Exception('Nenhum sistema de monitoramento disponível');
    }

    return ModuleDetectionResult(
      systemType: systemType,
      hasNewModules: hasNewModules,
      hasLegacyTotem: hasLegacyTotem,
      primaryModuleId: primaryModuleId,
      primaryModuleType: primaryModuleType,
    );
  }

  /// Verifica se o sistema novo de módulos está ativo
  /// Retorna o módulo principal compatível com o tipo de dispositivo
  Future<Map<String, dynamic>?> _checkNewModulesSystem(
    String serverUrl,
    String token,
  ) async {
    try {
      final headers = _authService.getHeaders();
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/modules'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final modules = data['modules'] as List;

        if (modules.isEmpty) {
          _logger.w('⚠️ Sistema de módulos existe mas nenhum módulo está configurado');
          return null;
        }

        // Procura módulo compatível (Desktop, Notebook, Panel)
        for (var module in modules) {
          final type = (module['type'] as String).toLowerCase();
          if (['desktop', 'notebook', 'panel'].contains(type)) {
            return {
              'id': module['_id'] ?? module['id'],
              'name': module['name'],
              'type': module['type'],
            };
          }
        }

        // Se não encontrou compatível, usa o primeiro módulo
        final firstModule = modules.first;
        return {
          'id': firstModule['_id'] ?? firstModule['id'],
          'name': firstModule['name'],
          'type': firstModule['type'],
        };
      } else if (response.statusCode == 404) {
        _logger.d('Sistema novo de módulos não está configurado (404)');
        return null;
      } else {
        _logger.w('Erro ao verificar módulos: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.d('Sistema novo não disponível: $e');
      return null;
    }
  }

  /// Verifica se o sistema legado de Totem está ativo
  Future<bool> _checkLegacyTotemSystem(String serverUrl) async {
    try {
      // Tenta fazer uma requisição simples para o endpoint legado
      // Não precisa de autenticação pois o endpoint /data é público
      final response = await http.get(
        Uri.parse('$serverUrl/api/monitoring/totems'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      // Se retornar 401, significa que o endpoint existe mas precisa de auth
      // Se retornar 200, existe e está acessível
      if (response.statusCode == 200 || response.statusCode == 401) {
        return true;
      }
      
      return false;
    } catch (e) {
      _logger.d('Sistema legado não disponível: $e');
      return false;
    }
  }

  /// Determina qual módulo usar baseado no tipo de dispositivo detectado
  Future<String?> selectModuleForDeviceType({
    required String serverUrl,
    required String token,
    required String deviceType, // 'desktop', 'notebook', 'panel'
  }) async {
    try {
      final headers = _authService.getHeaders();
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/modules'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final modules = data['modules'] as List;

        // Procura módulo que corresponda ao tipo do dispositivo
        for (var module in modules) {
          if ((module['type'] as String).toLowerCase() == deviceType.toLowerCase()) {
            final moduleId = module['_id'] ?? module['id'];
            _logger.i('🎯 Módulo selecionado: ${module['name']} para tipo $deviceType');
            return moduleId;
          }
        }

        _logger.w('⚠️ Nenhum módulo do tipo "$deviceType" encontrado');
        return null;
      }
      
      return null;
    } catch (e) {
      _logger.e('Erro ao selecionar módulo: $e');
      return null;
    }
  }
}