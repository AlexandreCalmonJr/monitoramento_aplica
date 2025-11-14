// File: lib/services/monitoring_service.dart
// VERSÃO COM DETECÇÃO AUTOMÁTICA DE MÓDULOS LEGADOS
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/legacy_totem_service.dart';
import 'package:agent_windows/services/local_cache_service.dart';
import 'package:agent_windows/services/module_detection_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/payload_validator.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

class MonitoringService {
  final Logger _logger;
  final AuthService _authService;
  final ModuleStructureService _moduleStructureService;
  final LocalCacheService _cacheService;
  final LegacyTotemService _legacyTotemService;
  final ModuleDetectionService _detectionService;

  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 3;

  MonitoringService(
    this._logger,
    this._authService,
    this._moduleStructureService,
    this._cacheService,
    SettingsService settingsService,
  )   : _legacyTotemService = LegacyTotemService(_logger),
        _detectionService = ModuleDetectionService(_logger, _authService) {
    _logger.i('MonitoringService inicializado com suporte a sistemas legados');
  }

  String _decodeOutput(dynamic output) {
    if (output is List<int>) {
      return latin1.decode(output, allowInvalid: true);
    }
    return output.toString();
  }

  Future<String> _runCommand(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args, runInShell: true);
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0) {
        return stdoutString.trim();
      } else {
        _logger
            .w("Erro no comando '$command ${args.join(' ')}': $stderrString");
        return "";
      }
    } catch (e) {
      _logger.e("Exceção no comando '$command ${args.join(' ')}': $e");
      return "";
    }
  }

  Future<String> _runScript(String scriptName) async {
    final tempDir = Directory.systemTemp;
    final scriptFile = File(p.join(tempDir.path, scriptName));

    try {
      final scriptContent =
          await rootBundle.loadString('assets/scripts/$scriptName');
      await scriptFile.writeAsString(scriptContent,
          flush: true, encoding: utf8);

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
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (e) {
        _logger.w('Falha ao deletar script temporário: ${scriptFile.path}, $e');
      }
    }
  }

  Future<Map<String, dynamic>> _getCoreSystemInfo() async {
    final stdoutString = await _runScript('get_core_system_info.ps1');

    if (stdoutString.isNotEmpty) {
      try {
        final decodedJson = json.decode(stdoutString);
        _logger.i('✅ Informações do sistema coletadas via script consolidado');
        if (decodedJson['mac_address_radio'] == null ||
            decodedJson['mac_address_radio'] == 'N/A' ||
            decodedJson['mac_address_radio'].toString().isEmpty) {
          _logger.w(
              '⚠️ BSSID não detectado no script. Tentando coletar manualmente...');
          decodedJson['mac_address_radio'] = await _getBssidManually();
        }
        return decodedJson;
      } catch (e) {
        _logger.e('Erro ao decodificar JSON do get_core_system_info.ps1: $e');
        _logger.e('Saída recebida: $stdoutString'); // Log da saída real
        return {};
      }
    }
    _logger.e('Erro ao executar script consolidado: (saída vazia)');
    return {};
  }

  Future<String> _getBssidManually() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          r'(Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.PhysicalMediaType -like "*802.11*"} | Get-NetAdapterStatistics | Select-Object -First 1).MacAddress'
        ],
        runInShell: true,
      );

      final bssid = _decodeOutput(result.stdout).trim();
      if (bssid.isNotEmpty && bssid != 'N/A') {
        _logger.i('✅ BSSID coletado manually: $bssid');
        return bssid;
      }
    } catch (e) {
      _logger.e('❌ Erro ao coletar BSSID manualmente: $e');
    }
    return 'N/A';
  }

  Future<List<Map<String, dynamic>>> _getPrintersInfo() async {
    _logger.i("--- Iniciando coleta de impressoras ---");

    try {
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

  Future<void> _sendPayload(
    Map<String, dynamic> payload,
    String serverUrl,
    String moduleId,
    String moduleType,
  ) async {
    try {
      final validation = PayloadValidator.validate(payload, moduleType);

      if (!validation.isValid) {
        _logger.e('❌ Payload inválido:');
        for (var e in validation.errors) {
          _logger.e('   • $e');
        }
        throw Exception('Payload inválido: ${validation.errors.join(', ')}');
      }

      if (validation.warnings.isNotEmpty) {
        _logger.w('⚠️ Avisos no payload:');
        for (var w in validation.warnings) {
          _logger.w('   • $w');
        }
      }

      // CORREÇÃO (Item 5): Lógica de validação de serial removida daqui,
      // pois foi movida para o PayloadValidator.
      // A lógica de fallback permanece.
      String serial = (payload['serial_number'] ?? '').toString().trim();
      String assetName = (payload['asset_name'] ?? '').toString().trim();
      String hostname = (payload['hostname'] ?? '').toString().trim();

      if (serial.isEmpty ||
          serial == 'N/A' ||
          serial.toLowerCase() == 'null' ||
          serial.contains('000000')) {
        _logger.w('⚠️ Serial inválido: "$serial". Tentando usar hostname...');
        serial = hostname.isNotEmpty && hostname != 'N/A'
            ? hostname
            : 'UNKNOWN-${DateTime.now().millisecondsSinceEpoch}';
      }

      if (assetName.isEmpty ||
          assetName == 'N/A' ||
          assetName.toLowerCase() == 'null') {
        _logger.w(
            '⚠️ Asset Name inválido: "$assetName". Usando hostname ou serial...');
        assetName =
            hostname.isNotEmpty && hostname != 'N/A' ? hostname : serial;
      }

      if (serial.isEmpty || assetName.isEmpty) {
        _logger
            .e('❌ PAYLOAD CRÍTICO: Impossível enviar sem identificação válida');
        _logger.e(
            '   Serial: "$serial" | AssetName: "$assetName" | Hostname: "$hostname"');
        return;
      }

      payload['serial_number'] = serial;
      payload['asset_name'] = assetName;
      if (hostname.isNotEmpty && hostname != 'N/A') {
        payload['hostname'] = hostname;
      }

      _logger.i('📤 Enviando ativo: Nome="$assetName" | S/N="$serial"');

      final headers = _authService.getHeaders();

      final response = await http
          .post(
            Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
            headers: headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

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

      await _cacheService.cacheFailedPayload({
        ...payload,
        'moduleId': moduleId,
        'serverUrl': serverUrl,
      });

      rethrow;
    }
  }

  // === MÉTODO PRINCIPAL COM DETECÇÃO AUTOMÁTICA ===

  Future<void> collectAndSendData({
    required String moduleId, // ID do módulo salvo (pode estar vazio)
    required String serverUrl,
    required String token,
    String? manualSector,
    String? manualFloor,
    String? manualAssetName,
    bool? forceLegacyMode, // O valor do checkbox
  }) async {
    if (serverUrl.isEmpty || token.isEmpty) {
      _logger.w('❌ Configurações incompletas. Abortando envio.');
      return;
    }

    await _cacheService.syncCachedData(serverUrl, token);
    _logger.i('🔄 INICIANDO CICLO DE MONITORAMENTO');

    try {
      await _authService.refreshTokenIfNeeded(serverUrl: serverUrl);

      _logger.i('Coletando dados do host (PC)...');
      Map<String, dynamic> coreInfo = await _getCoreSystemInfo();

      if (coreInfo.isEmpty ||
          (coreInfo['serial_number'] as String?).toString().isEmpty) {
        throw Exception('Não foi possível obter informações do sistema');
      }

      final bool isNotebook = coreInfo['is_notebook'] == true;
      final String deviceType = isNotebook ? 'notebook' : 'desktop';
      _logger.i('Tipo de dispositivo detectado: $deviceType');

      // --- ✅ LÓGICA DE DECISÃO BINÁRIA (Sem Híbrido) ---

      // 1. O Modo Legado está forçado E o dispositivo NÃO é um notebook?
      if (forceLegacyMode == true && !isNotebook) {
        _logger.i(
            '🔧 Modo legado forçado (Desktop/Totem). Enviando APENAS para /api/monitor.');
        await _sendToLegacySystem(
            coreInfo, serverUrl, token, manualSector ?? '', manualFloor ?? '');

        // Esta é a correção: para de executar e não tenta enviar para os módulos.
        _consecutiveErrors = 0;
        _logger.i('✅ CICLO (LEGADO) CONCLUÍDO\n');
        return; // <-- PARA A EXECUÇÃO AQUI
      }

      // 2. Se a condição acima for falsa (é notebook OU não está forçado)
      //    trata como um envio normal para o Sistema de Módulos.
      _logger.i('Executando envio para Sistema de Módulos...');
      String effectiveModuleId = moduleId; // Usa o ID salvo

      if (effectiveModuleId.isEmpty) {
        _logger.w('⚠️ Nenhum módulo configurado. Tentando auto-detecção...');
        final autoModuleId = await _detectionService.selectModuleForDeviceType(
          serverUrl: serverUrl,
          token: token,
          deviceType: deviceType,
        );

        if (autoModuleId != null) {
          effectiveModuleId = autoModuleId;
          _logger.i('🎯 Módulo auto-selecionado: $effectiveModuleId');
        } else {
          _logger.e(
              '❌ Falha na auto-detecção. É necessário configurar um módulo.');
          throw Exception('Nenhum módulo configurado ou auto-detectado.');
        }
      } else {
        _logger
            .i('✅ Usando módulo configurado pelo usuário: $effectiveModuleId');
      }

      // Envia os dados para o módulo novo
      await _sendToNewSystem(
        coreInfo,
        serverUrl,
        effectiveModuleId,
        token,
        manualSector,
        manualFloor,
        manualAssetName,
      );

      _consecutiveErrors = 0;
    } catch (e) {
      _logger.e('❌ ERRO no ciclo de monitoramento: $e');
      _consecutiveErrors++;

      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _logger.e('❌ CRÍTICO: $_consecutiveErrors erros consecutivos!');
        await _showWindowsNotification(
            'Erro de Sincronização', 'Verifique a conexão com o servidor');
      }

      final delaySeconds = pow(2, min(_consecutiveErrors, 5)).toInt();
      _logger.w('⏳ Aguardando ${delaySeconds}s antes de tentar novamente...');
      await Future.delayed(Duration(seconds: delaySeconds));

      rethrow;
    }

    _logger.i('✅ CICLO (MÓDULOS) CONCLUÍDO\n');
  }

  // --- ENVIO PARA SISTEMA LEGADO (CORRIGIDO) ---
  Future<void> _sendToLegacySystem(
    Map<String, dynamic> coreInfo,
    String serverUrl,
    String token,
    String sector,
    String floor,
  ) async {
    _logger.i('📡 Enviando para sistema LEGADO de Totem (/api/monitor)...');

    // ✅ CORREÇÃO: Não chama mais scripts antigos
    // Os dados (periféricos, programas) já estão em coreInfo

    final success = await _legacyTotemService.sendTotemData(
      serverUrl: serverUrl,
      systemInfo: coreInfo, // Passa o coreInfo completo
      token: token,
      sector: sector,
      floor: floor,
    );

    if (success) {
      _logger.i('✅ Dados enviados ao sistema legado com sucesso');
    } else {
      _logger.w('⚠️ Falha ao enviar para sistema legado');
    }
  }

  // --- ENVIO PARA SISTEMA NOVO (CORRIGIDO) ---
  Future<void> _sendToNewSystem(
    Map<String, dynamic> coreInfo,
    String serverUrl,
    String moduleId,
    String token,
    String? sector,
    String? floor,
    String? assetName,
  ) async {
    _logger.i('📡 Enviando para sistema NOVO de módulos (/api/modules)...');
    _logger.d('📋 Módulo: $moduleId');

    final structure = await _moduleStructureService.fetchModuleStructure(
      serverUrl: serverUrl,
      token: token,
      moduleId: moduleId,
    );

    if (structure == null) {
      throw Exception('Não foi possível obter a estrutura do módulo');
    }

    _logger.i('📦 Tipo do módulo: ${structure.type}');
    final String moduleType = structure.type.toLowerCase();

    if (moduleType == 'printer') {
      await _handlePrinterModule(
          serverUrl, moduleId, moduleType, sector, floor);
      return;
    }

    Map<String, dynamic> payload = {
      'custom_data': {'sector': sector, 'floor': floor}
    };

    payload.addAll(coreInfo);

    if (assetName != null && assetName.isNotEmpty) {
      _logger.i('Usando Nome do Ativo manual: $assetName');
      payload['asset_name'] = assetName;
    }

    // ✅ CORREÇÃO: 'current_user' já vem do coreInfo
    // payload['assigned_to'] = await _runCommand('whoami', []);

    // Remove dados desnecessários dependendo do tipo
    switch (moduleType) {
      case 'desktop':
        _logger.i('💻 Preparando dados de Desktop...');
        payload.remove('battery_level');
        payload.remove('battery_health');
        break;

      case 'notebook':
        _logger.i('💼 Preparando dados de Notebook...');
        payload.remove('biometric_reader');
        payload.remove('connected_printer');
        break;

      // ... (outros cases) ...
    }

    if (!_moduleStructureService.validateData(payload, structure.type)) {
      _logger.w('⚠️ Alguns campos obrigatórios estão ausentes');
    }

    await _sendPayload(payload, serverUrl, moduleId, moduleType);
  }

  // Método auxiliar para impressoras (mantido do original)
  Future<void> _handlePrinterModule(
    String serverUrl,
    String moduleId,
    String moduleType,
    String? sector,
    String? floor,
  ) async {
    _logger.i('🖨️ Módulo de Impressora selecionado. Coletando impressoras...');
    final printers = await _getPrintersInfo();

    if (printers.isEmpty) {
      _logger.i('Nenhuma impressora física encontrada para enviar.');
      return;
    }

    for (final printerPayload in printers) {
      printerPayload['custom_data'] = {'sector': sector, 'floor': floor};

      if (!_moduleStructureService.validateData(printerPayload, 'printer')) {
        _logger.w(
            '⚠️ Impressora [${printerPayload['serial_number']}] com campos obrigatórios ausentes. Pulando envio.');
        continue;
      }

      await _sendPayload(printerPayload, serverUrl, moduleId, moduleType);
    }
  }

  Future<void> _showWindowsNotification(String title, String message) async {
    try {
      await Process.run('powershell', [
        '-Command',
        'New-BurnerToastNotification -Text "$title", "$message"'
      ]);
    } catch (e) {
      _logger.w('Não foi possível mostrar notificação: $e');
    }
  }
}
