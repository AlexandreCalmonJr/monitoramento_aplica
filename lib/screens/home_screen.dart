// File: lib/screens/home_screen.dart
import 'dart:convert';

import 'package:agent_windows/background_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ModuleInfo {
  final String id;
  final String name;
  final String type;

  ModuleInfo({required this.id, required this.name, required this.type});

  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    // MODIFICADO: Ajustado para corresponder à estrutura de 'moduleRoutes.js'
    return ModuleInfo(
      id: json['_id'],
      name: json['name'],
      type: json['type'],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settingsService = SettingsService();
  final _backgroundService = BackgroundService();
  
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _sectorController = TextEditingController();
  final _floorController = TextEditingController();
  final _tokenController = TextEditingController(); // <-- ADICIONADO
  
  List<ModuleInfo> _availableModules = [];
  String? _selectedModuleId;
  bool _isLoadingModules = false;

  final List<Map<String, dynamic>> _intervalOptions = [
    {'label': '5 Minutos', 'value': 300},
    {'label': '15 Minutos', 'value': 900},
    {'label': '30 Minutos', 'value': 1800},
    {'label': '1 Hora', 'value': 3600},
    {'label': '2 Horas', 'value': 7200},
  ];
  late int _selectedInterval;

  @override
  void initState() {
    super.initState();
    _selectedInterval = _intervalOptions.first['value'];
    _loadSettings();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _sectorController.dispose();
    _floorController.dispose();
    _tokenController.dispose(); // <-- ADICIONADO
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await _settingsService.loadSettings();
    _ipController.text = _settingsService.ip;
    _portController.text = _settingsService.port;
    _sectorController.text = _settingsService.sector;
    _floorController.text = _settingsService.floor;
    _tokenController.text = _settingsService.token; // <-- ADICIONADO
    _selectedInterval = _settingsService.interval;
    _selectedModuleId = _settingsService.moduleId;

    // MODIFICADO: Só busca módulos se tiver IP, Porta e Token
    if (_ipController.text.isNotEmpty && 
        _portController.text.isNotEmpty &&
        _tokenController.text.isNotEmpty) {
      _fetchModules();
    }
    setState(() {});
  }

  Future<void> _fetchModules() async {
    // MODIFICADO: Adiciona verificação de token
    if (_ipController.text.isEmpty || 
        _portController.text.isEmpty ||
        _tokenController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, preencha IP, Porta e Token do servidor.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    setState(() {
      _isLoadingModules = true;
      _availableModules = [];
    });

    try {
      final serverUrl = 'http://${_ipController.text}:${_portController.text}';
      final token = _tokenController.text; // <-- OBTER TOKEN

      // MODIFICADO: Endpoint corrigido e cabeçalho AUTH_TOKEN
      final response = await http.get(
        Uri.parse('$serverUrl/api/modules'), // <-- CORRIGIDO (removido /agent-list)
        headers: {
          'AUTH_TOKEN': token, 
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // MODIFICADO: Ajustado para a resposta do servidor { success: true, modules: [...] }
        final List<dynamic> modulesJson = data['modules']; 
        
        if (mounted) {
          setState(() {
            _availableModules = modulesJson
                .map((json) => ModuleInfo.fromJson(json))
                .toList();
            if (_selectedModuleId != null && 
                !_availableModules.any((m) => m.id == _selectedModuleId)) {
              _selectedModuleId = null;
            }
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Falha ao buscar módulos: Token inválido ou expirado.');
      } else {
        throw Exception('Falha ao buscar módulos: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar módulos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingModules = false);
      }
    }
  }

  void _saveAndRestartService() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedModuleId == null || _selectedModuleId!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, selecione um módulo para se conectar.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // MODIFICADO: Passa o novo token ao salvar
      await _settingsService.saveSettings(
        newIp: _ipController.text,
        newPort: _portController.text,
        newInterval: _selectedInterval,
        newModuleId: _selectedModuleId!,
        newSector: _sectorController.text,
        newFloor: _floorController.text,
        newToken: _tokenController.text, // <-- ADICIONADO
      );

      // MODIFICADO: Passa o token para o serviço de background
      await _backgroundService.updateSettings({
        'moduleId': _selectedModuleId,
        'serverUrl': 'http://${_ipController.text}:${_portController.text}',
        'interval': _selectedInterval,
        'sector': _sectorController.text,
        'floor': _floorController.text,
        'token': _tokenController.text, // <-- ADICIONADO
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas! O agente está rodando em segundo plano.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          child: Column(
            children: [
              // Cabeçalho
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.blue, size: 32),
                    const SizedBox(width: 12),
                    Text(
                      'Agente de Monitoramento',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    // Indicador de status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _backgroundService.isRunning ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _backgroundService.isRunning ? Icons.check_circle : Icons.pause_circle,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _backgroundService.isRunning ? 'Ativo' : 'Parado',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Formulário
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Configuração do Servidor', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _ipController,
                                decoration: const InputDecoration(labelText: 'Endereço IP'),
                                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _portController,
                                decoration: const InputDecoration(labelText: 'Porta'),
                                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // <-- CAMPO DE TOKEN ADICIONADO -->
                        TextFormField(
                          controller: _tokenController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Token de Autenticação',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                        ),
                        // <-- FIM DO CAMPO DE TOKEN -->

                        const SizedBox(height: 16),
                        
                        Text('Módulo de Conexão', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedModuleId, // Alterado de initialValue para value
                                decoration: InputDecoration(
                                  labelText: 'Selecione o Módulo',
                                  prefixIcon: _isLoadingModules 
                                    ? Container(
                                        padding: const EdgeInsets.all(12.0), 
                                        child: const SizedBox(
                                          width: 20, 
                                          height: 20, 
                                          child: CircularProgressIndicator(strokeWidth: 2)
                                        )
                                      )
                                    : const Icon(Icons.apps),
                                ),
                                items: _availableModules.map((module) {
                                  return DropdownMenuItem(
                                    value: module.id,
                                    child: Text(module.name),
                                  );
                                }).toList(),
                                onChanged: _isLoadingModules ? null : (value) {
                                  setState(() {
                                    _selectedModuleId = value;
                                  });
                                },
                                validator: (v) => (v == null || v.isEmpty) ? 'Selecione um módulo' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              onPressed: _isLoadingModules ? null : _fetchModules,
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Buscar Módulos',
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        Text('Identificação Manual', style: theme.textTheme.titleMedium),
                        Text(
                          'Opcional. Preencha se a localização automática não for suficiente.', 
                          style: theme.textTheme.bodySmall
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _sectorController,
                                decoration: const InputDecoration(labelText: 'Setor'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _floorController,
                                decoration: const InputDecoration(labelText: 'Andar'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        Text('Configurações Gerais', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<int>(
                          value: _selectedInterval, // Alterado de initialValue para value
                          decoration: const InputDecoration(
                            labelText: 'Intervalo de Sincronização',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                          items: _intervalOptions.map((option) {
                            return DropdownMenuItem<int>(
                              value: option['value'],
                              child: Text(option['label']),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setState(() => _selectedInterval = newValue);
                            }
                          },
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),

              // Botão Salvar
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton.icon(
                  onPressed: _saveAndRestartService,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar e Ativar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

