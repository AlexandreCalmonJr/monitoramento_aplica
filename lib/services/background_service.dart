// File: lib/services/background_service.dart
import 'dart:async';
import 'dart:io';

import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:logger/logger.dart';
import 'package:agent_windows/services/command_executor_service.dart';
import 'package:agent_windows/services/service_locator.dart';

class BackgroundService {
  Timer? _timer;
  final Logger _logger;
  final MonitoringService _monitoringService;
  final SettingsService _settingsService;

  bool _isRunning = false;
  Map<String, dynamic>? _currentSettings;

  bool get isRunning => _isRunning;
  String lastRunStatus = "Aguardando";
  DateTime? lastRunTime;
  DateTime? nextRunTime;

  int syncCount = 0;
  int errorCount = 0;
  DateTime? startTime;

  BackgroundService(
      this._logger, this._settingsService, this._monitoringService) {
    _logger.i('BackgroundService inicializado');
  }

  Future<void> initialize() async {
    await _settingsService.loadSettings();

    if (_settingsService.ip.isNotEmpty &&
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty) {
      await start();
    } else {
      _logger.w('⚠️  Background Service: Aguardando configuração inicial');
      lastRunStatus = "Aguardando Configuração";
    }

    // Tenta iniciar, mas não bloqueia se falhar
    _startCommandPolling();
  }

  /// Inicia o polling de comandos remotos
  Future<void> _startCommandPolling() async {
    try {
      // Recarrega settings para garantir dados frescos
      await _settingsService.loadSettings();

      if (_settingsService.ip.isEmpty ||
          _settingsService.token.isEmpty ||
          _settingsService.moduleId.isEmpty) {
        // Silencioso para não spammar log se não estiver configurado
        return;
      }

      final serialNumber = await _getSerialNumber();
      final commandExecutor = locator<CommandExecutorService>();
      final serverUrl =
          'http://${_settingsService.ip}:${_settingsService.port}';

      // Inicia o serviço de comandos
      commandExecutor.startCommandPolling(
        serverUrl: serverUrl,
        moduleId: _settingsService.moduleId,
        serialNumber: serialNumber,
        interval: const Duration(seconds: 30),
      );

      _logger.i('✅ Polling de comandos ativado para S/N: $serialNumber');
    } catch (e) {
      _logger.e('❌ Erro ao iniciar polling de comandos: $e');
    }
  }

  Future<String> _getSerialNumber() async {
    try {
      final result = await Process.run(
        'wmic',
        ['bios', 'get', 'serialnumber'],
        runInShell: true,
      );
      final serial = result.stdout
          .toString()
          .split('\n')
          .where((line) =>
              line.trim().isNotEmpty && !line.contains('SerialNumber'))
          .first
          .trim();
      return serial.isNotEmpty
          ? serial
          : (Platform.environment['COMPUTERNAME'] ?? 'UNKNOWN');
    } catch (e) {
      return Platform.environment['COMPUTERNAME'] ?? 'UNKNOWN';
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      _logger.w('⚠️  Background Service: Já está rodando');
      return;
    }

    await _settingsService.loadSettings();

    _currentSettings = {
      'moduleId': _settingsService.moduleId,
      'serverUrl': 'http://${_settingsService.ip}:${_settingsService.port}',
      'interval': _settingsService.interval,
      'sector': _settingsService.sector,
      'floor': _settingsService.floor,
      'token': _settingsService.token,
      'assetName': _settingsService.assetName,
      'forceLegacyMode': _settingsService.forceLegacyMode,
    };

    _isRunning = true;
    startTime = DateTime.now();
    _logger.i('✅ Background Service: Iniciado');

    _timer?.cancel();
    runCycle(); // Executa o primeiro ciclo
    _scheduleNextRun(_settingsService.interval);

    // Força início do polling ao iniciar o serviço
    _startCommandPolling();
  }

  Future<void> runCycle() async {
    if (_currentSettings == null) return;

    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final token = _currentSettings!['token'] as String?;
    final forceLegacyMode =
        _currentSettings!['forceLegacyMode'] as bool? ?? false;

    // Validação básica
    if (serverUrl == null ||
        serverUrl.isEmpty ||
        token == null ||
        token.isEmpty) {
      lastRunStatus = "Erro: Config incompleta";
      return;
    }

    _logger.i('🔄 EXECUTANDO CICLO DE MONITORAMENTO');
    lastRunStatus = "Sincronizando...";

    try {
      await _monitoringService.collectAndSendData(
        moduleId: moduleId ?? '',
        serverUrl: serverUrl,
        token: token,
        manualSector: _currentSettings!['sector'],
        manualFloor: _currentSettings!['floor'],
        manualAssetName: _currentSettings!['assetName'],
        forceLegacyMode: forceLegacyMode,
      );

      _logger.i('✅ CICLO CONCLUÍDO COM SUCESSO');
      lastRunStatus = "Sucesso";
      syncCount++;

      // ✅ AUTO-HEALING: Se o ciclo funcionou, garante que o polling de comandos está ativo
      _startCommandPolling();
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO NO CICLO DE MONITORAMENTO',
          error: e, stackTrace: stackTrace);
      lastRunStatus = "Erro: ${e.toString()}";
      errorCount++;
    }

    lastRunTime = DateTime.now();
  }

  Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    _logger.i('🔄 Background Service: Atualizando configurações');
    _currentSettings ??= {};
    _currentSettings!.addAll(newSettings);

    _timer?.cancel();
    runCycle(); // Roda ciclo imediato

    // Reinicia polling com novas configurações
    await _startCommandPolling();

    final intervalSeconds =
        _currentSettings!['interval'] as int? ?? _settingsService.interval;
    _scheduleNextRun(intervalSeconds);
  }

  void _scheduleNextRun(int intervalSeconds) {
    _logger.i('   Agendando próximo ciclo em $intervalSeconds segundos');
    _timer = Timer(Duration(seconds: intervalSeconds), () async {
      if (!_isRunning) return;
      await runCycle();
      if (_isRunning) {
        final currentInterval =
            _currentSettings!['interval'] as int? ?? intervalSeconds;
        _scheduleNextRun(currentInterval);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    lastRunStatus = "Parado";

    try {
      locator<CommandExecutorService>().stopCommandPolling();
    } catch (e) {
      _logger.w('Erro ao parar polling: $e');
    }

    _logger.i('🛑 Background Service: Parado');
  }
}
