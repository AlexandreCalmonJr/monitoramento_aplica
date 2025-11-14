// File: lib/services/background_service.dart (CORRIGIDO)
import 'dart:async';

import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:logger/logger.dart';

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

  // Construtor com DI
  BackgroundService(
      this._logger, this._settingsService, this._monitoringService) {
    _logger.i('BackgroundService inicializado');
  }

  Future<void> initialize() async {
    await _settingsService.loadSettings();

    // A lógica de "configurado" no provider já valida isso
    if (_settingsService.ip.isNotEmpty &&
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty) {
      await start();
    } else {
      _logger.w('⚠️  Background Service: Aguardando configuração inicial');
      lastRunStatus = "Aguardando Configuração";
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      _logger.w('⚠️  Background Service: Já está rodando');
      return;
    }

    await _settingsService.loadSettings();

    // O check de config incompleta agora é feito no runCycle

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
    _logger.i(
        '   Módulo: ${_settingsService.moduleId.isEmpty ? "N/A" : _settingsService.moduleId}');
    _logger.i('   Modo Legado: ${_settingsService.forceLegacyMode}');
    _logger.i('   Servidor: ${_currentSettings!['serverUrl']}');
    _logger.i('   Intervalo: ${_settingsService.interval}s');

    _timer?.cancel();

    // Executa o ciclo em segundo plano e libera a UI
    runCycle();

    _scheduleNextRun(_settingsService.interval);
  }

  Future<void> runCycle() async {
    if (_currentSettings == null) {
      _logger.e('❌ _currentSettings é nulo. Ciclo abortado.');
      lastRunStatus = "Erro: Config nula";
      return;
    }

    // --- ✅ INÍCIO DA CORREÇÃO ---
    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final token = _currentSettings!['token'] as String?;
    final forceLegacyMode =
        _currentSettings!['forceLegacyMode'] as bool? ?? false;

    // 1. Verifica se IP, Porta e Token existem
    final bool connectionInfoMissing = (serverUrl == null ||
        serverUrl.isEmpty ||
        serverUrl == "http://:" ||
        token == null ||
        token.isEmpty);

    // 2. Verifica se o Módulo é necessário
    //    (Não é necessário se o modo legado estiver forçado)
    final bool moduleInfoMissing =
        (!forceLegacyMode && (moduleId == null || moduleId.isEmpty));

    if (connectionInfoMissing || moduleInfoMissing) {
      _logger.e(
          '❌ Background Service: Configurações incompletas para executar ciclo');
      if (connectionInfoMissing)
        _logger.e('   -> IP, Porta ou Token faltando.');
      if (moduleInfoMissing)
        _logger.e(
            '   -> Modo de Módulo está ativo, mas o ModuleID está faltando.');

      lastRunStatus = "Erro: Config incompleta";
      errorCount++;
      return;
    }
    // --- ✅ FIM DA CORREÇÃO ---

    final interval = _currentSettings!['interval'] as int? ?? 300;
    nextRunTime = DateTime.now().add(Duration(seconds: interval));

    final sector = _currentSettings!['sector'] as String?;
    final floor = _currentSettings!['floor'] as String?;
    final assetName = _currentSettings!['assetName'] as String?;

    _logger.i('🔄 EXECUTANDO CICLO DE MONITORAMENTO');
    lastRunStatus = "Sincronizando...";

    try {
      await _monitoringService.collectAndSendData(
        moduleId: moduleId ?? '', // Passa o ID (ou vazio)
        serverUrl: serverUrl,
        token: token,
        manualSector: sector,
        manualFloor: floor,
        manualAssetName: assetName,
        forceLegacyMode: forceLegacyMode, // Passa o flag
      );

      _logger.i('✅ CICLO CONCLUÍDO COM SUCESSO');
      lastRunStatus = "Sucesso";
      syncCount++;
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO NO CICLO DE MONITORAMENTO',
          error: e, stackTrace: stackTrace);
      lastRunStatus =
          "Erro: ${e.toString().substring(0, (e.toString().length < 50) ? e.toString().length : 50)}...";
      errorCount++;
    }

    lastRunTime = DateTime.now();
  }

  Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    _logger.i('🔄 Background Service: Atualizando configurações');

    _currentSettings ??= {};
    _currentSettings!.addAll(newSettings);

    _timer?.cancel();

    _logger.i('⚡ Executando ciclo imediato com novas configurações...');

    // Roda em segundo plano
    runCycle();

    final intervalSeconds =
        _currentSettings!['interval'] as int? ?? _settingsService.interval;
    _scheduleNextRun(intervalSeconds);
  }

  void _scheduleNextRun(int intervalSeconds) {
    _logger.i('   Agendando próximo ciclo em $intervalSeconds segundos');

    nextRunTime = DateTime.now().add(Duration(seconds: intervalSeconds));

    _timer = Timer(Duration(seconds: intervalSeconds), () async {
      if (!_isRunning) {
        _logger.w('Timer disparado, mas serviço está parado.');
        return;
      }

      _logger.d('Timer disparado, executando ciclo...');
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
    nextRunTime = null;
    _logger.i('🛑 Background Service: Parado');
  }

  void dispose() {
    stop();
  }

  void resetCounters() {
    syncCount = 0;
    errorCount = 0;
    startTime = DateTime.now();
    _logger.i('🔄 Contadores resetados');
  }
}
