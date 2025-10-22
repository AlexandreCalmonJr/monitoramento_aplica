// File: lib/services/background_service.dart
import 'dart:async';

import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/foundation.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  Timer? _timer;
  final MonitoringService _monitoringService = MonitoringService();
  final SettingsService _settingsService = SettingsService();
  
  bool _isRunning = false;
  Map<String, dynamic>? _currentSettings;

  bool get isRunning => _isRunning;

  Future<void> initialize() async {
    await _settingsService.loadSettings();
    
    // Só inicia se houver configurações válidas
    if (_settingsService.moduleId.isNotEmpty && 
        _settingsService.ip.isNotEmpty && 
        _settingsService.port.isNotEmpty) {
      await start();
    } else {
      debugPrint('Background Service: Aguardando configuração inicial');
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      debugPrint('Background Service: Já está rodando');
      return;
    }

    await _settingsService.loadSettings();
    
    // Valida configurações
    if (_settingsService.moduleId.isEmpty || 
        _settingsService.ip.isEmpty || 
        _settingsService.port.isEmpty) {
      debugPrint('Background Service: Configurações incompletas, não pode iniciar');
      return;
    }

    _currentSettings = {
      'moduleId': _settingsService.moduleId,
      'serverUrl': 'http://${_settingsService.ip}:${_settingsService.port}',
      'interval': _settingsService.interval,
      'sector': _settingsService.sector,
      'floor': _settingsService.floor,
    };

    _isRunning = true;
    debugPrint('Background Service: Iniciado com módulo ${_settingsService.moduleId}');
    
    // Executa imediatamente
    await _runCycle();
    
    // Agenda execuções periódicas
    _scheduleNextRun();
  }

  void _scheduleNextRun() {
    _timer?.cancel();
    
    final interval = _currentSettings?['interval'] as int? ?? 300;
    debugPrint('Background Service: Próxima execução em ${interval}s');
    
    _timer = Timer(Duration(seconds: interval), () async {
      await _runCycle();
      _scheduleNextRun();
    });
  }

  Future<void> _runCycle() async {
    if (_currentSettings == null) return;

    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final sector = _currentSettings!['sector'] as String?;
    final floor = _currentSettings!['floor'] as String?;

    if (moduleId != null && moduleId.isNotEmpty && 
        serverUrl != null && serverUrl.isNotEmpty) {
      debugPrint('Background Service: Coletando dados para o módulo $moduleId');
      await _monitoringService.collectAndSendData(
        moduleId: moduleId,
        serverUrl: serverUrl,
        manualSector: sector,
        manualFloor: floor,
      );
    } else {
      debugPrint('Background Service: Configurações incompletas');
    }
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    debugPrint('Background Service: Atualizando configurações');
    _currentSettings = settings;
    
    // Cancela o timer atual e reagenda
    _scheduleNextRun();
    
    // Executa imediatamente com as novas configurações
    await _runCycle();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('Background Service: Parado');
  }

  void dispose() {
    stop();
  }
}