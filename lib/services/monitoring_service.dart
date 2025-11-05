// File: lib/services/monitoring_service.dart
// (VERSÃO ATUALIZADA - Scripts movidos para assets e asset_name manual)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:flutter/services.dart' show rootBundle; // NOVO: Import para assets
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p; // NOVO: Import para manipulação de paths

class MonitoringService {
  final Logger _logger;
  final AuthService _authService;
  final ModuleStructureService _moduleStructureService;

  MonitoringService(this._logger, this._authService, this._moduleStructureService) {
    _logger.i('MonitoringService inicializado');
  }
  
  String _decodeOutput(dynamic output) {
    if (output is List<int>) {
      return latin1.decode(output, allowInvalid: true);
    }
    return output.toString();
  }

  // MODIFICADO: _runCommand agora é para comandos simples
  Future<String> _runCommand(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args, runInShell: true);
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0) {
        return stdoutString.trim();
      } else {
        _logger.w("Erro no comando '$command ${args.join(' ')}': $stderrString");
        return "";
      }
    } catch (e) {
      _logger.e("Exceção no comando '$command ${args.join(' ')}': $e");
      return "";
    }
  }

  // NOVO: Função auxiliar para carregar, salvar e executar scripts dos assets
  Future<String> _runScript(String scriptName) async {
    final tempDir = Directory.systemTemp;
    final scriptFile = File(p.join(tempDir.path, scriptName));

    try {
      // Carrega o script dos assets
      final scriptContent = await rootBundle.loadString('assets/scripts/$scriptName');
      // Salva o script em um arquivo temporário
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);

      // Executa o arquivo de script temporário
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );
      
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0) {
        return stdoutString.trim();
      } else {
        _logger.w("Erro no script '$scriptName': $stderrString");
        return "";
      }
    } catch (e) {
      _logger.e("Exceção ao executar script '$scriptName': $e");
      return "";
    } finally {
      // Limpa o arquivo temporário
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (e) {
        _logger.w('Falha ao deletar script temporário: ${scriptFile.path}, $e');
      }
    }
  }
  
  // === MÉTODOS DE COLETA OTIMIZADOS ===

  // ===================================================================
  // ✅ ATUALIZADO: SCRIPT DE COLETA DO HOST (Agora usa _runScript)
  // ===================================================================
  Future<Map<String, dynamic>> _getCoreSystemInfo() async {
    // MODIFICADO: Chama o _runScript com o nome do arquivo
    final stdoutString = await _runScript('get_core_system_info.ps1');

    if (stdoutString.isNotEmpty) {
      try {
        final decodedJson = json.decode(stdoutString);
        _logger.i('✅ Informações do sistema coletadas via script consolidado');
        return decodedJson;
      } catch (e) {
         _logger.e('Erro ao decodificar JSON do get_core_system_info.ps1: $e');
         return {};
      }
    }
    _logger.e('Erro ao executar script consolidado: (saída vazia)');
    return {};
  }

  // MODIFICADO: Agora usa _runScript
  Future<List<String>> _getInstalledPrograms() async {
    _logger.i("--- Iniciando coleta de programas ---");
    try {
      // MODIFICADO: Chama o _runScript
      final result = await _runScript('get_installed_programs.ps1');
      if (result.isNotEmpty && !result.startsWith("Erro")) {
        final programs = result.split('\n').where((s) => s.trim().isNotEmpty).toList();
        _logger.i("✅ ${programs.length} programas encontrados");
        return programs;
      }
    } catch (e) {
      _logger.e("❌ Erro ao coletar programas: $e");
    }
    return [];
  }

  // MODIFICADO: Agora usa _runScript
  Future<Map<String, dynamic>> _getBatteryInfo() async {
    try {
      // MODIFICADO: Chama o _runScript
      final result = await _runScript('get_battery_info.ps1');
      
      if (result.contains(';')) {
        final parts = result.split(';');
        _logger.i('✅ Informações da bateria coletadas');
        return {
          'battery_level': int.tryParse(parts[0]),
          'battery_health': parts[1],
        };
      }
    } catch (e) {
      _logger.e("Erro ao coletar informações da bateria: $e");
    }
    return {'battery_level': null, 'battery_health': 'N/A'};
  }

  // MODIFICADO: Agora usa _runScript
  Future<Map<String, String>> _getPeripherals() async {
    _logger.i("--- Iniciando coleta de periféricos ---");
    try {
      // MODIFICADO: Chama o _runScript
      final stdoutString = await _runScript('get_peripherals.ps1');

      Map<String, String> devices = {'zebra': 'Não detectado', 'bematech': 'Não detectado', 'biometric': 'Não detectado'};
      final lines = stdoutString.split('\n');
      for (String line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('ZEBRA:')) { devices['zebra'] = trimmedLine.substring('ZEBRA:'.length).trim(); }
        else if (trimmedLine.startsWith('BEMATECH:')) { devices['bematech'] = trimmedLine.substring('BEMATECH:'.length).trim(); }
        else if (trimmedLine.startsWith('BIOMETRIC:')) { devices['biometric'] = trimmedLine.substring('BIOMETRIC:'.length).trim(); }
      }
      _logger.i('✅ Periféricos verificados');
      return devices;
    } catch (e) {
      _logger.e("❌ Erro ao detectar periféricos: $e");
      return {'zebra': 'Erro', 'bematech': 'Erro', 'biometric': 'Erro'};
    }
  }

  // ===================================================================
  // ✅ SCRIPT DE COLETA DE IMPRESSORAS (Agora usa _runScript)
  // ===================================================================
  Future<List<Map<String, dynamic>>> _getPrintersInfo() async {
    _logger.i("--- Iniciando coleta de impressoras ---");
    
    try {
      // MODIFICADO: Chama o _runScript
      final stdoutString = await _runScript('get_printers_info.ps1');

      if (stdoutString.isNotEmpty && stdoutString.startsWith('[')) {
        final List<dynamic> decodedJson = json.decode(stdoutString);
        _logger.i('✅ ${decodedJson.length} impressoras físicas encontradas');
        return decodedJson.cast<Map<String, dynamic>>();
      } else {
        _logger.e('Erro ao executar script de impressoras: $stdoutString');
        return [];
      }
    } catch (e) {
      _logger.e("❌ Exceção ao executar script de impressoras: $e");
      return [];
    }
  }

  // ===================================================================
  // ✅ FUNÇÃO DE ENVIO DE PAYLOAD (Sem alterações)
  // ===================================================================
  Future<void> _sendPayload(Map<String, dynamic> payload, String serverUrl, String moduleId) async {
    try {
      // 🔥 VALIDAÇÃO E SANITIZAÇÃO ROBUSTA
      String serial = (payload['serial_number'] ?? '').toString().trim();
      String assetName = (payload['asset_name'] ?? '').toString().trim();
      String hostname = (payload['hostname'] ?? '').toString().trim();

      // 1. Validar Serial Number
      if (serial.isEmpty || serial == 'N/A' || serial.toLowerCase() == 'null' || serial.contains('000000')) {
        _logger.w('⚠️ Serial inválido: "$serial". Tentando usar hostname...');
        serial = hostname.isNotEmpty && hostname != 'N/A' ? hostname : 'UNKNOWN-${DateTime.now().millisecondsSinceEpoch}';
      }

      // 2. Validar Asset Name (prioriza hostname, fallback para serial)
      if (assetName.isEmpty || assetName == 'N/A' || assetName.toLowerCase() == 'null') {
        _logger.w('⚠️ Asset Name inválido: "$assetName". Usando hostname ou serial...');
        assetName = hostname.isNotEmpty && hostname != 'N/A' ? hostname : serial;
      }

      // 3. Validação final (rejeita apenas se TUDO falhar)
      if (serial.isEmpty || assetName.isEmpty) {
        _logger.e('❌ PAYLOAD CRÍTICO: Impossível enviar sem identificação válida');
        _logger.e('   Serial: "$serial" | AssetName: "$assetName" | Hostname: "$hostname"');
        return;
      }

      // Atualiza o payload com valores sanitizados
      payload['serial_number'] = serial;
      payload['asset_name'] = assetName;
      if (hostname.isNotEmpty && hostname != 'N/A') {
        payload['hostname'] = hostname;
      }

      _logger.i('📤 Enviando ativo: Nome="$assetName" | S/N="$serial"');

      final headers = _authService.getHeaders();
      
      final response = await http.post(
        Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
        headers: headers,
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final wasUpdated = responseData['updated'] ?? false;
        _logger.i(wasUpdated 
          ? '✅ Ativo "$assetName" atualizado com sucesso!' 
          : '✅ Novo ativo "$assetName" criado com sucesso!');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.w('❌ Token inválido ou expirado para "$assetName"');
        throw Exception('Autenticação falhou');
      } else {
        _logger.e('❌ Erro ao enviar "$assetName": ${response.statusCode}');
        _logger.e('   Resposta: ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO no envio do payload: $e');
      _logger.d('Stack: $stackTrace');
    }
  }

  // ===================================================================
  // ✅ MÉTODO PRINCIPAL DE COLETA E ENVIO
  // ===================================================================
  Future<void> collectAndSendData({
    required String moduleId,
    required String serverUrl,
    required String token,
    String? manualSector,
    String? manualFloor,
    String? manualAssetName, // <-- NOVO
  }) async {
    if (serverUrl.isEmpty || moduleId.isEmpty || token.isEmpty) {
      _logger.w('❌ Configurações incompletas. Abortando envio.');
      return;
    }

    _logger.i('🔄 INICIANDO CICLO DE MONITORAMENTO');
    _logger.d('📋 Módulo: $moduleId');

    try {
      // 1. Buscar estrutura do módulo
      await _authService.refreshTokenIfNeeded(serverUrl: serverUrl);
      final structure = await _moduleStructureService.fetchModuleStructure(
        serverUrl: serverUrl, token: token, moduleId: moduleId,
      );
      if (structure == null) { throw Exception('Não foi possível obter a estrutura do módulo'); }
      _logger.i('📦 Tipo do módulo: ${structure.type}');
      final String moduleType = structure.type.toLowerCase();

      // ==========================================================
      // CASO ESPECIAL: MÓDULO DE IMPRESSORA
      // ==========================================================
      if (moduleType == 'printer') {
        _logger.i('🖨️  Módulo de Impressora selecionado. Coletando impressoras...');
        final printers = await _getPrintersInfo();

        if (printers.isEmpty) {
          _logger.i('Nenhuma impressora física encontrada para enviar.');
          _logger.i('✅ CICLO DE MONITORAMENTO (IMPRESSORAS) CONCLUÍDO\n');
          return;
        }

        for (final printerPayload in printers) {
          printerPayload['custom_data'] = { 'sector': manualSector, 'floor': manualFloor };
          // NOTA: O asset_name manual NÃO está sendo aplicado a impressoras,
          // elas usam a própria detecção. Isso parece ser o correto.
          if (!_moduleStructureService.validateData(printerPayload, 'printer')) {
              _logger.w('⚠️ Impressora [${printerPayload['serial_number']}] com campos obrigatórios ausentes. Pulando envio.');
              continue;
          }
          await _sendPayload(printerPayload, serverUrl, moduleId);
        }
        _logger.i('✅ CICLO DE MONITORAMENTO (IMPRESSORAS) CONCLUÍDO\n');
        return; 
      }
      
      // ==========================================================
      // LÓGICA PADRÃO (DESKTOP, NOTEBOOK, PANEL)
      // ==========================================================
      _logger.i('Coletando dados do host (PC)...');
      Map<String, dynamic> coreInfo = await _getCoreSystemInfo();

      if (coreInfo.isEmpty || (coreInfo['serial_number'] as String?).toString().isEmpty) {
        throw Exception('Não foi possível obter informações do sistema (serial number nulo)');
      }
      Map<String, dynamic> payload = {
          'custom_data': { 'sector': manualSector, 'floor': manualFloor }
      };
      
      payload.addAll(coreInfo);
      
      // <-- LÓGICA DE SOBRESCRITA DO ASSET_NAME
      if (manualAssetName != null && manualAssetName.isNotEmpty) {
        _logger.i('Usando Nome do Ativo manual: $manualAssetName');
        payload['asset_name'] = manualAssetName;
      }
      // FIM DA LÓGICA DE SOBRESCRITA
      
      payload['assigned_to'] = await _runCommand('whoami', []); 

      switch (moduleType) {
  case 'desktop':
    _logger.i('💻 Coletando dados específicos de Desktop...');
    payload['installed_software'] = await _getInstalledPrograms();
    final peripherals = await _getPeripherals();
    payload['biometric_reader'] = peripherals['biometric'];
    payload['connected_printer'] = '${peripherals['zebra']} / ${peripherals['bematech']}';
    break;

  case 'notebook':
    _logger.i('💼 Coletando dados específicos de Notebook...');
    payload['installed_software'] = await _getInstalledPrograms();
    final batteryInfo = await _getBatteryInfo();
    
    if (batteryInfo['battery_level'] != null) {
      payload['battery_level'] = batteryInfo['battery_level'];
    }
    payload['battery_health'] = batteryInfo['battery_health'];
    
    // NOVO: Adiciona informações de WiFi se disponíveis
    if (coreInfo['connection_type'] == 'WiFi') {
      if (coreInfo['wifi_ssid'] != null) {
        payload['wifi_ssid'] = coreInfo['wifi_ssid'];
      }
      if (coreInfo['wifi_signal'] != null) {
        payload['wifi_signal'] = coreInfo['wifi_signal'];
      }
      _logger.d('📶 WiFi detectado: SSID=${coreInfo['wifi_ssid']}, BSSID=${coreInfo['mac_address_radio']}, Sinal=${coreInfo['wifi_signal']}');
    }
    break;

  case 'panel':
    _logger.i('📺 Coletando dados de Panel...');
    payload.addAll({
      'is_online': true, 'screen_size': 'N/A',
      'resolution': 'N/A', 'firmware_version': 'N/A',
    });
    break;
    
  default:
    _logger.i('📦 Módulo customizado ou não mapeado: enviando apenas dados base');
}

      if (!_moduleStructureService.validateData(payload, structure.type)) {
        _logger.w('⚠️  Alguns campos obrigatórios estão ausentes');
      }
      await _sendPayload(payload, serverUrl, moduleId);

    } catch (e) {
      _logger.e('❌ ERRO no ciclo de monitoramento: $e');
      rethrow;
    }
    _logger.i('✅ CICLO DE MONITORAMENTO (HOST) CONCLUÍDO\n');
  }
}