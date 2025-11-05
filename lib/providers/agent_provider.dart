// File: lib/providers/agent_provider.dart
import 'dart:convert';

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


  Future<void> restartService() async {
    _logger.i('Reiniciando o serviço...');
    await _backgroundService.initialize();
    notifyListeners();
  }

  ModuleFetchStatus _moduleFetchStatus = ModuleFetchStatus.idle;
  ModuleFetchStatus get moduleFetchStatus => _moduleFetchStatus;

  bool get isConfigured => _status == AgentStatus.configured;

  // Controllers para o Wizard
  final PageController pageController = PageController();
  final ipController = TextEditingController();
  final portController = TextEditingController();
  final tokenController = TextEditingController();
  final sectorController = TextEditingController();
  final floorController = TextEditingController();
  final assetNameController = TextEditingController(); // <-- NOVO

  // Lista de Módulos
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
    assetNameController.text = _settingsService.assetName; // <-- NOVO
    _selectedInterval = _settingsService.interval;
    _selectedModuleId = _settingsService.moduleId;

    if (_settingsService.ip.isNotEmpty && 
        _settingsService.port.isNotEmpty &&
        _settingsService.token.isNotEmpty &&
        _settingsService.moduleId.isNotEmpty) {
      _logger.i('Configuração encontrada, definindo status como configurado');
      _status = AgentStatus.configured;
      await _authService.saveLegacyToken(_settingsService.token);
      // Busca módulos em background para exibir o nome correto no painel de status
      if (_availableModules.isEmpty) fetchModules(testConnectionOnly: true);
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

  Future<bool> fetchModules({bool testConnectionOnly = false}) async {
    _logger.i('Buscando módulos do servidor: ${ipController.text}');
    _moduleFetchStatus = ModuleFetchStatus.loading;
    _errorMessage = '';
    notifyListeners();

    try {
      final serverUrl = 'http://${ipController.text}:${portController.text}';
      final token = tokenController.text;

      await _authService.saveLegacyToken(token);
      final headers = _authService.getHeaders();

      final response = await http.get(
        Uri.parse('$serverUrl/api/modules'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _logger.i('Módulos buscados com sucesso');
        
        final data = json.decode(response.body);
        final List<dynamic> modulesJson = data['modules']; 
        
        _availableModules = modulesJson
            .map((json) => ModuleInfo.fromJson(json))
            .toList();
            
        if (testConnectionOnly) {
          _moduleFetchStatus = ModuleFetchStatus.success;
          notifyListeners();
          return true;
        }
        
        // Restaura o módulo selecionado se ainda existe
        if (_selectedModuleId != null) {
          try {
            final existingModule = _availableModules.firstWhere((m) => m.id == _selectedModuleId);
            _selectedModuleId = existingModule.id;
          } catch (e) {
            _selectedModuleId = null;
          }
        }
        
        _moduleFetchStatus = ModuleFetchStatus.success;
        if (!testConnectionOnly) {
          pageController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
        notifyListeners();
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.w('Token inválido ou expirado');
        throw Exception('Token inválido ou expirado.');
      } else {
        _logger.e('Falha ao buscar módulos: ${response.statusCode} ${response.body}');
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

  void nextOnboardingPage() {
    pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void previousOnboardingPage() {
    pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<bool> saveSettingsAndRestartService() async {
    _logger.i('Tentando salvar configurações...');
    if (_selectedModuleId == null || _selectedModuleId!.isEmpty) {
      _errorMessage = 'Por favor, selecione um módulo para se conectar.';
      notifyListeners();
      return false;
    }

    try {
      await _authService.saveLegacyToken(tokenController.text);
      
      await _settingsService.saveSettings(
        newIp: ipController.text,
        newPort: portController.text,
        newInterval: _selectedInterval,
        newModuleId: _selectedModuleId!,
        newSector: sectorController.text,
        newFloor: floorController.text,
        newToken: tokenController.text,
        newAssetName: assetNameController.text, // <-- NOVO
      );

      await _backgroundService.updateSettings({
        'moduleId': _selectedModuleId,
        'serverUrl': 'http://${ipController.text}:${portController.text}',
        'interval': _selectedInterval,
        'sector': sectorController.text,
        'floor': floorController.text,
        'token': tokenController.text,
        'assetName': assetNameController.text, // <-- NOVO
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

  // Chamado pelo Painel de Status para reconfigurar
  void enterReconfiguration() {
    _status = AgentStatus.configuring;
    
    // ADICIONADO: Atrasar a chamada do jumpToPage
    Future.delayed(Duration.zero, () {
      // Verifica se o controller ainda está associado a alguma página
      // (caso o usuário navegue muito rápido)
      if (pageController.hasClients) { 
        pageController.jumpToPage(0); // Reinicia o wizard
      } else {
        _logger.w("PageController não tem clientes ao tentar jumpToPage(0) em enterReconfiguration");
      }
    });
    notifyListeners();
  }

  // Cancela a reconfiguração
  void cancelReconfiguration() {
    _status = AgentStatus.configured;
    _loadSettings(); // Recarrega as configs salvas
    notifyListeners();
  }
}