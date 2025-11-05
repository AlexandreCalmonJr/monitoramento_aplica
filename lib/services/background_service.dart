// File: lib/background_service.dart
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
  BackgroundService(this._logger, this._settingsService, this._monitoringService) {
    _logger.i('BackgroundService inicializado');
  }

  Future<void> initialize() async {
    await _settingsService.loadSettings();
    
    if (_settingsService.moduleId.isNotEmpty && 
        _settingsService.ip.isNotEmpty && 
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty) {
      await start();
    } else {
      _logger.w('⚠️  Background Service: Aguardando configuração inicial');
      _logger.d('   Requer: IP, Porta, Token e Módulo');
      lastRunStatus = "Aguardando Configuração";
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      _logger.w('⚠️  Background Service: Já está rodando');
      return;
    }

    await _settingsService.loadSettings();
    
    if (_settingsService.moduleId.isEmpty || 
        _settingsService.ip.isEmpty || 
        _settingsService.port.isEmpty ||
        _settingsService.token.isEmpty) {
      _logger.e('❌ Background Service: Configurações incompletas');
      lastRunStatus = "Configuração Incompleta";
      return;
    }

    _currentSettings = {
      'moduleId': _settingsService.moduleId,
      'serverUrl': 'http://${_settingsService.ip}:${_settingsService.port}',
      'interval': _settingsService.interval,
      'sector': _settingsService.sector,
      'floor': _settingsService.floor,
      'token': _settingsService.token,
      'assetName': _settingsService.assetName, // <-- NOVO
    };

    _isRunning = true;
    startTime = DateTime.now(); // NOVO
    _logger.i('✅ Background Service: Iniciado');
    _logger.i('   Módulo: ${_settingsService.moduleId}');
    _logger.i('   Servidor: ${_currentSettings!['serverUrl']}');
    _logger.i('   Intervalo: ${_settingsService.interval}s');
    
    await runCycle();
    
  }

  Future<void> runCycle() async {
    if (_currentSettings == null) {
      _logger.w('⚠️  Background Service: Configurações ausentes');
      lastRunStatus = "Erro: Config ausente";
      return;
    }

    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final sector = _currentSettings!['sector'] as String?;
    final floor = _currentSettings!['floor'] as String?;
    final token = _currentSettings!['token'] as String?;
    final assetName = _currentSettings!['assetName'] as String?; // <-- NOVO

    if (moduleId == null || moduleId.isEmpty || 
        serverUrl == null || serverUrl.isEmpty ||
        token == null || token.isEmpty) {
      _logger.e('❌ Background Service: Configurações incompletas para executar ciclo');
      lastRunStatus = "Erro: Config incompleta";
      errorCount++; // NOVO
      return;
    }

    _logger.i('🔄 EXECUTANDO CICLO DE MONITORAMENTO');
    lastRunStatus = "Sincronizando...";

    try {
      await _monitoringService.collectAndSendData(
        moduleId: moduleId,
        serverUrl: serverUrl,
        manualSector: sector,
        manualFloor: floor,
        token: token,
        manualAssetName: assetName, // <-- NOVO
      );
      
      _logger.i('✅ CICLO CONCLUÍDO COM SUCESSO');
      lastRunStatus = "Sucesso";
      syncCount++; // NOVO
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO NO CICLO DE MONITORAMENTO', error: e, stackTrace: stackTrace);
      lastRunStatus = "Erro: ${e.toString().substring(0, (e.toString().length < 50) ? e.toString().length : 50)}...";
      errorCount++; // NOVO
    }
    
    lastRunTime = DateTime.now();
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    _logger.i('🔄 Background Service: Atualizando configurações');
    
    _currentSettings = settings;
    
    // Cancela o timer atual e reagenda
    _timer?.cancel();
    
    
    // Executa imediatamente com as novas configurações
    _logger.i('⚡ Executando ciclo imediato com novas configurações...');
    await runCycle();
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