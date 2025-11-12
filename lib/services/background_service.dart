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
      'assetName': _settingsService.assetName,
      'forceLegacyMode': _settingsService.forceLegacyMode, // <-- ADICIONE ESTA LINHA
    };

    _isRunning = true;
    startTime = DateTime.now(); 
    _logger.i('✅ Background Service: Iniciado');
    _logger.i('   Módulo: ${_settingsService.moduleId}');
    _logger.i('   Servidor: ${_currentSettings!['serverUrl']}');
    _logger.i('   Intervalo: ${_settingsService.interval}s');
    
    // --- INÍCIO DA CORREÇÃO DO TIMER ---
    // Cancela qualquer timer antigo
    _timer?.cancel();

    // Executa o primeiro ciclo imediatamente
    await runCycle(); 
    
    // Agenda os ciclos futuros
    _scheduleNextRun(_settingsService.interval);
    // --- FIM DA CORREÇÃO DO TIMER ---
  }

  Future<void> runCycle() async {
    // CORREÇÃO (Item 3): Adicionar verificação de token no início do ciclo
    if (_currentSettings == null ||
        _currentSettings!['token'] == null ||
        _currentSettings!['token'].toString().isEmpty) {
      _logger.e('❌ Token ausente. Não é possível executar ciclo.');
      lastRunStatus = "Erro: Token ausente";
      errorCount++;
      return;
    }
    // FIM DA CORREÇÃO

    // Atualiza o horário da próxima execução (para a UI)
    final interval = _currentSettings!['interval'] as int? ?? 300;
    nextRunTime = DateTime.now().add(Duration(seconds: interval));

    final moduleId = _currentSettings!['moduleId'] as String?;
    final serverUrl = _currentSettings!['serverUrl'] as String?;
    final sector = _currentSettings!['sector'] as String?;
    final floor = _currentSettings!['floor'] as String?;
    final token = _currentSettings!['token'] as String?;
    final assetName = _currentSettings!['assetName'] as String?; 
    
    // --- ADIÇÃO DA LEITURA DO MODO LEGADO ---
final forceLegacyMode = _currentSettings!['forceLegacyMode'] as bool? ?? false;

    if (moduleId == null || moduleId.isEmpty || 
        serverUrl == null || serverUrl.isEmpty ||
        token == null || token.isEmpty) {
      _logger.e('❌ Background Service: Configurações incompletas para executar ciclo');
      lastRunStatus = "Erro: Config incompleta";
      errorCount++; 
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
        manualAssetName: assetName,
        forceLegacyMode: forceLegacyMode, // <-- ADICIONE ESTE PARÂMETRO
      );
      
      _logger.i('✅ CICLO CONCLUÍDO COM SUCESSO');
      lastRunStatus = "Sucesso";
      syncCount++; 
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO NO CICLO DE MONITORAMENTO', error: e, stackTrace: stackTrace);
      lastRunStatus = "Erro: ${e.toString().substring(0, (e.toString().length < 50) ? e.toString().length : 50)}...";
      errorCount++; 
    }
    
    lastRunTime = DateTime.now();
  }

  Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    _logger.i('🔄 Background Service: Atualizando configurações');
    
    // --- INÍCIO DA CORREÇÃO DO BUG 1 ---
    // Garante que _currentSettings não seja nulo
    _currentSettings ??= {};
    
    // Mescla as novas configurações com as existentes, em vez de substituir
    _currentSettings!.addAll(newSettings);
    // --- FIM DA CORREÇÃO DO BUG 1 ---
    
    // Cancela o timer antigo
    _timer?.cancel();
    
    _logger.i('⚡ Executando ciclo imediato com novas configurações...');
    await runCycle(); // Executa 1x com as novas configs

    // --- INÍCIO DA CORREÇÃO DO TIMER 2 ---
    // Reagenda o timer com o novo intervalo (se houver)
    final intervalSeconds = _currentSettings!['interval'] as int? ?? _settingsService.interval;
    _scheduleNextRun(intervalSeconds);
    // --- FIM DA CORREÇÃO DO TIMER 2 ---
  }

  // --- MÉTODO AUXILIAR ADICIONADO ---
  // CORREÇÃO (Item 4): Usar Timer simples em vez de Timer.periodic
  void _scheduleNextRun(int intervalSeconds) {
    _logger.i('   Agendando próximo ciclo em $intervalSeconds segundos');
    
    // Atualiza a UI
    nextRunTime = DateTime.now().add(Duration(seconds: intervalSeconds));

    // Usa Timer simples
    _timer = Timer(Duration(seconds: intervalSeconds), () async {
      if (!_isRunning) {
        _logger.w('Timer disparado, mas serviço está parado.');
        return;
      }

      _logger.d('Timer disparado, executando ciclo...');
      await runCycle(); // ✅ Aguarda ciclo terminar

      // Reagendar próximo ciclo
      if (_isRunning) {
        // Pega o intervalo *atualizado* caso tenha mudado
        final currentInterval = _currentSettings!['interval'] as int? ?? intervalSeconds;
        _scheduleNextRun(currentInterval);
      }
    });
  }
  // --- FIM DO MÉTODO AUXILIAR ---

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