// File: lib/providers/agent_provider.dart (COMPLETO E CORRIGIDO)
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/models/module_info.dart';
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

enum AgentStatus { unconfigured, configuring, configured, error }

enum ModuleFetchStatus { idle, loading, success, error }

class AgentProvider extends ChangeNotifier {
  final Logger _logger;
  final SettingsService _settingsService;
  final AuthService _authService;
  final BackgroundService _backgroundService;
  AgentStatus _status = AgentStatus.unconfigured;
  AgentStatus get status => _status;

  bool _forceLegacyMode = false;
  bool get forceLegacyMode => _forceLegacyMode;

  Future<void> restartService() async {
    _logger.i('Reiniciando o serviço...');
    _backgroundService.stop();
    await _backgroundService.initialize();
    notifyListeners();
  }

  ModuleFetchStatus _moduleFetchStatus = ModuleFetchStatus.idle;
  ModuleFetchStatus get moduleFetchStatus => _moduleFetchStatus;

  bool get isConfigured => _status == AgentStatus.configured;

  final PageController pageController = PageController();
  final ipController = TextEditingController();
  final portController = TextEditingController();
  final tokenController = TextEditingController();
  final sectorController = TextEditingController();
  final floorController = TextEditingController();
  final assetNameController = TextEditingController();

  List<ModuleInfo> _availableModules = [];
  List<ModuleInfo> get availableModules => _availableModules;
  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  String? _selectedModuleId;
  String? get selectedModuleId => _selectedModuleId;
  ModuleInfo? get selectedModule {
    try {
      return _availableModules.firstWhere((m) => m.id == _selectedModuleId);
    } catch (e) {
      return null;
    }
  }

  List<ModuleInfo> get filteredModules {
    if (_searchQuery.isEmpty) {
      return _availableModules;
    }

    final query = _searchQuery.toLowerCase();
    return _availableModules.where((module) {
      return module.name.toLowerCase().contains(query) ||
          module.type.toLowerCase().contains(query) ||
          module.description.toLowerCase().contains(query);
    }).toList();
  }

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  final List<Map<String, dynamic>> intervalOptions = [
    {'label': '5 Minutos', 'value': 300},
    {'label': '15 Minutos', 'value': 900},
    {'label': '30 Minutos', 'value': 1800},
    {'label': '1 Hora', 'value': 3600},
    {'label': '2 Horas', 'value': 7200},
  ];
  late int _selectedInterval;
  int get selectedInterval => _selectedInterval;

  AgentProvider()
      : _logger = locator<Logger>(),
        _settingsService = locator<SettingsService>(),
        _authService = locator<AuthService>(),
        _backgroundService = locator<BackgroundService>() {
    _logger.i('AgentProvider inicializado');
    _selectedInterval = intervalOptions.first['value'];
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsService.loadSettings();
    await _authService.loadTokens();

    ipController.text = _settingsService.ip;
    portController.text = _settingsService.port;
    sectorController.text = _settingsService.sector;
    floorController.text = _settingsService.floor;
    tokenController.text = _settingsService.token;
    assetNameController.text = _settingsService.assetName;
    _selectedInterval = _settingsService.interval;
    _selectedModuleId = _settingsService.moduleId;
    _forceLegacyMode = _settingsService.forceLegacyMode;

    if (_settingsService.ip.isNotEmpty &&
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty &&
        (_settingsService.moduleId.isNotEmpty || _forceLegacyMode)) {
      _logger.i('Configuração encontrada, definindo status como configurado');
      _status = AgentStatus.configured;
      await _authService.saveLegacyToken(_settingsService.token);
      if (_availableModules.isEmpty && !_forceLegacyMode) {
        fetchModules(testConnectionOnly: true);
      }
    } else {
      _logger.i('Nenhuma configuração encontrada, aguardando onboarding');
      _status = AgentStatus.unconfigured;
    }
    notifyListeners();
  }

  void setSelectedModule(String? moduleId) {
    _selectedModuleId = moduleId;
    notifyListeners();
  }

  void setSelectedInterval(int? interval) {
    if (interval != null) {
      _selectedInterval = interval;
      notifyListeners();
    }
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  Future<bool> _testConnection() async {
    _logger
        .i('Testando conexão com: ${ipController.text}:${portController.text}');
    try {
      final serverUrl = 'http://${ipController.text}:${portController.text}';
      final token = tokenController.text;
      await _authService.saveLegacyToken(token);
      final headers = _authService.getHeaders();

      final response = await http
          .get(
            Uri.parse('$serverUrl/api/auth/validate'), // Rota de teste
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401) {
        throw Exception('Token inválido ou expirado.');
      }

      _logger
          .i('Teste de conexão bem-sucedido (Status: ${response.statusCode})');
      return true;
    } catch (e) {
      _logger.e('Erro no teste de conexão: $e');
      _errorMessage = "Falha ao conectar: ${e.toString()}";
      return false;
    }
  }

  Future<bool> fetchModules({bool testConnectionOnly = false}) async {
    _logger.i('Buscando módulos do servidor: ${ipController.text}');
    _moduleFetchStatus = ModuleFetchStatus.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      // ✅ --- LÓGICA DE PULAR ETAPA (Modo Legado) ---
      if (_forceLegacyMode) {
        _logger.i('Modo legado forçado. Pulando seleção de módulo.');
        bool canConnect = await _testConnection(); // Apenas testa a conexão
        if (canConnect) {
          _moduleFetchStatus = ModuleFetchStatus.success;
          // Pula para a Página 3 (índice 2)
          pageController.animateToPage(2,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
          notifyListeners();
          return true;
        } else {
          _moduleFetchStatus = ModuleFetchStatus.error;
          notifyListeners();
          return false;
        }
      }
      // --- Fim da Correção ---

      final serverUrl = 'http://${ipController.text}:${portController.text}';
      final token = tokenController.text;

      await _authService.saveLegacyToken(token);
      final headers = _authService.getHeaders();

      final response = await http
          .get(
            Uri.parse('$serverUrl/api/modules'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _logger.i('Módulos buscados com sucesso');

        final data = json.decode(response.body);
        final List<dynamic> modulesJson = data['modules'];

        _availableModules =
            modulesJson.map((json) => ModuleInfo.fromJson(json)).toList();

        if (testConnectionOnly) {
          _moduleFetchStatus = ModuleFetchStatus.success;
          notifyListeners();
          return true;
        }

        if (_selectedModuleId != null) {
          try {
            final existingModule =
                _availableModules.firstWhere((m) => m.id == _selectedModuleId);
            _selectedModuleId = existingModule.id;
          } catch (e) {
            _selectedModuleId = null;
          }
        }

        _moduleFetchStatus = ModuleFetchStatus.success;
        if (!testConnectionOnly) {
          // Vai para a Etapa 2 (índice 1)
          pageController.animateToPage(1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        }
        notifyListeners();
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.w('Token inválido ou expirado');
        throw Exception('Token inválido ou expirado.');
      } else if (response.statusCode == 404) {
        _logger.w(
            'Servidor não suporta /api/modules (404). Forçando Modo Legado.');
        await updateForceLegacyMode(true);
        _moduleFetchStatus = ModuleFetchStatus.success;
        pageController.animateToPage(2,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
        notifyListeners();
        return true;
      } else {
        _logger.e(
            'Falha ao buscar módulos: ${response.statusCode} ${response.body}');
        throw Exception('Falha ao buscar módulos: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('Erro ao buscar módulos: $e');
      _errorMessage = e.toString();
      _moduleFetchStatus = ModuleFetchStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateForceLegacyMode(bool value) async {
    _logger.i('Atualizando modo legado forçado para: $value');
    _forceLegacyMode = value;

    if (_forceLegacyMode) {
      _selectedModuleId = '';
    }

    await _settingsService.saveForceLegacyMode(_forceLegacyMode);

    await _backgroundService.updateSettings({
      'forceLegacyMode': _forceLegacyMode,
    });

    notifyListeners();
  }

  Future<bool> saveSettingsAndRestartService() async {
    _logger.i('Tentando salvar configurações...');

    if (!_forceLegacyMode &&
        (_selectedModuleId == null || _selectedModuleId!.isEmpty)) {
      _errorMessage = 'Por favor, selecione um módulo para se conectar.';
      notifyListeners();
      return false;
    }

    try {
      await _authService.saveLegacyToken(tokenController.text);

      if (assetNameController.text.isEmpty) {
        assetNameController.text =
            Platform.environment['COMPUTERNAME'] ?? 'UNKNOWN_PC';
        _logger.i(
            'Nome do ativo vazio, usando hostname: ${assetNameController.text}');
      }

      await _settingsService.saveSettings(
        newIp: ipController.text,
        newPort: portController.text,
        newInterval: _selectedInterval,
        newModuleId: _selectedModuleId ?? '',
        newSector: sectorController.text,
        newFloor: floorController.text,
        newToken: tokenController.text,
        newAssetName: assetNameController.text,
        newForceLegacyMode: _forceLegacyMode,
      );

      await _settingsService.saveForceLegacyMode(_forceLegacyMode);

      await _backgroundService.updateSettings({
        'moduleId': _selectedModuleId ?? '',
        'serverUrl': 'http://${ipController.text}:${portController.text}',
        'interval': _selectedInterval,
        'sector': sectorController.text,
        'floor': floorController.text,
        'token': tokenController.text,
        'assetName': assetNameController.text,
        'forceLegacyMode': _forceLegacyMode,
      });

      _status = AgentStatus.configured;
      _logger.i('Configurações salvas e serviço reiniciado');
      notifyListeners();
      return true;
    } catch (e) {
      _logger.e('Erro ao salvar configurações: $e');
      _errorMessage = 'Erro ao salvar: $e';
      notifyListeners();
      return false;
    }
  }

  void enterReconfiguration() {
    _status = AgentStatus.configuring;

    Future.delayed(Duration.zero, () {
      if (pageController.hasClients) {
        pageController.jumpToPage(0);
      } else {
        _logger.w(
            "PageController não tem clientes ao tentar jumpToPage(0) em enterReconfiguration");
      }
    });
    notifyListeners();
  }

  void cancelReconfiguration() {
    _status = AgentStatus.configured;
    _loadSettings();
    notifyListeners();
  }

  // ✅ --- INÍCIO DA CORREÇÃO ---
  // A lógica estava faltando.
  void previousOnboardingPage() {
    if (pageController.hasClients) {
      pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void nextOnboardingPage() {
    if (pageController.hasClients) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  // ✅ --- FIM DA CORREÇÃO ---
}
