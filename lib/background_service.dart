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
    
    if (_settingsService.moduleId.isNotEmpty && 
        _settingsService.ip.isNotEmpty && 
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty) {
      await start();
    } else {
      debugPrint('⚠️  Background Service: Aguardando configuração inicial');
      debugPrint('   Requer: IP, Porta, Token e Módulo');
    }
  }

  Future<void> start() async {
    if (_isRunning) {
      debugPrint('⚠️  Background Service: Já está rodando');
      return;
    }

    await _settingsService.loadSettings();
    
    if (_settingsService.moduleId.isEmpty || 
        _settingsService.ip.isEmpty || 
        _settingsService.port.isEmpty ||
        _settingsService.token.isEmpty) {
      debugPrint('❌ Background Service: Configurações incompletas');
      return;
    }

    _currentSettings = {
      'moduleId': _settingsService.moduleId,
      'serverUrl': 'http://${_settingsService.ip}:${_settingsService.port}',
      'interval': _settingsService.interval,
      'sector': _settingsService.sector,
      'floor': _settingsService.floor,
      'token': _settingsService.token,
    };

    _isRunning = true;
    debugPrint('✅ Background Service: Iniciado');
    debugPrint('   Módulo: ${_settingsService.moduleId}');
    debugPrint('   Servidor: ${_currentSettings!['serverUrl']}');
    debugPrint('   Intervalo: ${_settingsService.interval}s');
    
    // Executa imediatamente
    await _runCycle();
    
    // Agenda execuções periódicas
    _scheduleNextRun();
  }

  void _scheduleNextRun() {
    _timer?.cancel();
    
    final interval = _currentSettings?['interval'] as int? ?? 300;
    debugPrint('⏰ Próxima execução em ${interval}s (${Duration(seconds: interval).inMinutes} minutos)');
    
    _timer = Timer(Duration(seconds: interval), () async {
      await _runCycle();
      _scheduleNextRun();
    });
  }

  Future<void> _runCycle() async {
    if (_currentSettings == null) {
      debugPrint('⚠️  Background Service: Configurações ausentes');
      return;
    }

    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final sector = _currentSettings!['sector'] as String?;
    final floor = _currentSettings!['floor'] as String?;
    final token = _currentSettings!['token'] as String?;

    if (moduleId == null || moduleId.isEmpty || 
        serverUrl == null || serverUrl.isEmpty ||
        token == null || token.isEmpty) {
      debugPrint('❌ Background Service: Configurações incompletas para executar ciclo');
      return;
    }

    debugPrint('\n' + '=' * 60);
    debugPrint('🔄 EXECUTANDO CICLO DE MONITORAMENTO');
    debugPrint('   Timestamp: ${DateTime.now()}');
    debugPrint('=' * 60);

    try {
      await _monitoringService.collectAndSendData(
        moduleId: moduleId,
        serverUrl: serverUrl,
        manualSector: sector,
        manualFloor: floor,
        token: token,
      );
      
      debugPrint('=' * 60);
      debugPrint('✅ CICLO CONCLUÍDO COM SUCESSO');
      debugPrint('=' * 60 + '\n');
    } catch (e, stackTrace) {
      debugPrint('=' * 60);
      debugPrint('❌ ERRO NO CICLO DE MONITORAMENTO');
      debugPrint('   Erro: $e');
      debugPrint('   Stack: $stackTrace');
      debugPrint('=' * 60 + '\n');
    }
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    debugPrint('🔄 Background Service: Atualizando configurações');
    
    _currentSettings = settings;
    
    // Cancela o timer atual e reagenda
    _timer?.cancel();
    _scheduleNextRun();
    
    // Executa imediatamente com as novas configurações
    debugPrint('⚡ Executando ciclo imediato com novas configurações...');
    await _runCycle();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('🛑 Background Service: Parado');
  }

  void dispose() {
    stop();
  }
}