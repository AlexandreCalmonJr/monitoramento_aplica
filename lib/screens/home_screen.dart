// File: lib/screens/home_screen.dart
import 'dart:convert';

import 'package:agent_windows/background_service.dart';
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ModuleInfo {
  final String id;
  final String name;
  final String type;
  final String description;
  final int assetCount;

  ModuleInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.assetCount,
  });

  factory ModuleInfo.fromJson(Map<String, dynamic> json) {
    return ModuleInfo(
      id: json['_id'] ?? json['id'],
      name: json['name'],
      type: json['type'],
      description: json['description'] ?? '',
      assetCount: json['asset_count'] ?? 0,
    );
  }

  // Ícone baseado no tipo
  IconData get icon {
    switch (type.toLowerCase()) {
      case 'desktop':
        return Icons.computer;
      case 'notebook':
        return Icons.laptop;
      case 'panel':
        return Icons.tv;
      case 'printer':
        return Icons.print;
      case 'mobile':
        return Icons.smartphone;
      case 'totem':
        return Icons.account_box;
      default:
        return Icons.device_unknown;
    }
  }

  // Cor baseada no tipo
  Color get color {
    switch (type.toLowerCase()) {
      case 'desktop':
        return Colors.blue;
      case 'notebook':
        return Colors.purple;
      case 'panel':
        return Colors.orange;
      case 'printer':
        return Colors.green;
      case 'mobile':
        return Colors.teal;
      case 'totem':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
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
  final _moduleStructureService = ModuleStructureService();
  final _authService = AuthService();
  
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _sectorController = TextEditingController();
  final _floorController = TextEditingController();
  final _tokenController = TextEditingController();
  
  List<ModuleInfo> _availableModules = [];
  String? _selectedModuleId;
  ModuleInfo? _selectedModule;
  ModuleStructure? _selectedModuleStructure;
  bool _isLoadingModules = false;
  bool _isLoadingStructure = false;

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
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await _settingsService.loadSettings();
    await _authService.loadTokens();
    
    _ipController.text = _settingsService.ip;
    _portController.text = _settingsService.port;
    _sectorController.text = _settingsService.sector;
    _floorController.text = _settingsService.floor;
    _tokenController.text = _settingsService.token;
    _selectedInterval = _settingsService.interval;
    _selectedModuleId = _settingsService.moduleId;

    if (_ipController.text.isNotEmpty && 
        _portController.text.isNotEmpty &&
        _tokenController.text.isNotEmpty) {
      // Configura o AuthService com o legacy token
      await _authService.saveLegacyToken(_tokenController.text);
      await _fetchModules();
    }
    setState(() {});
  }

  Future<void> _fetchModules() async {
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
      final token = _tokenController.text;

      // Atualiza o AuthService
      await _authService.saveLegacyToken(token);
      
      // Usa os headers do AuthService
      final headers = _authService.getHeaders();

      final response = await http.get(
        Uri.parse('$serverUrl/api/modules'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> modulesJson = data['modules']; 
        
        if (mounted) {
          setState(() {
            _availableModules = modulesJson
                .map((json) => ModuleInfo.fromJson(json))
                .toList();
            
            // Restaura o módulo selecionado se ainda existe
            if (_selectedModuleId != null) {
              final existingModule = _availableModules.firstWhere(
                (m) => m.id == _selectedModuleId,
                orElse: () => _availableModules.first,
              );
              _selectedModuleId = existingModule.id;
              _selectedModule = existingModule;
              _loadModuleStructure();
            }
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Token inválido ou expirado.');
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

  Future<void> _loadModuleStructure() async {
    if (_selectedModuleId == null || _selectedModuleId!.isEmpty) {
      return;
    }

    setState(() => _isLoadingStructure = true);

    try {
      final serverUrl = 'http://${_ipController.text}:${_portController.text}';
      final structure = await _moduleStructureService.fetchModuleStructure(
        serverUrl: serverUrl,
        token: _tokenController.text,
        moduleId: _selectedModuleId!,
      );

      if (mounted) {
        setState(() {
          _selectedModuleStructure = structure;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar estrutura do módulo: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingStructure = false);
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

      // Salva o token no AuthService
      await _authService.saveLegacyToken(_tokenController.text);
      
      await _settingsService.saveSettings(
        newIp: _ipController.text,
        newPort: _portController.text,
        newInterval: _selectedInterval,
        newModuleId: _selectedModuleId!,
        newSector: _sectorController.text,
        newFloor: _floorController.text,
        newToken: _tokenController.text,
      );

      await _backgroundService.updateSettings({
        'moduleId': _selectedModuleId,
        'serverUrl': 'http://${_ipController.text}:${_portController.text}',
        'interval': _selectedInterval,
        'sector': _sectorController.text,
        'floor': _floorController.text,
        'token': _tokenController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Configurações salvas com sucesso!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Módulo ${_selectedModule?.name} ativo',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
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
          width: 600,
          child: Column(
            children: [
              // Cabeçalho
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.1),
                      theme.scaffoldBackgroundColor,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shield_outlined, 
                        color: theme.colorScheme.primary, 
                        size: 32
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agente de Monitoramento',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sistema de coleta automática de dados',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Indicador de status
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, 
                        vertical: 8
                      ),
                      decoration: BoxDecoration(
                        color: _backgroundService.isRunning 
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _backgroundService.isRunning 
                            ? Colors.green 
                            : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _backgroundService.isRunning 
                              ? Icons.check_circle 
                              : Icons.pause_circle,
                            size: 18,
                            color: _backgroundService.isRunning 
                              ? Colors.green 
                              : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _backgroundService.isRunning ? 'Ativo' : 'Parado',
                            style: TextStyle(
                              color: _backgroundService.isRunning 
                                ? Colors.green 
                                : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
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
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Seção: Configuração do Servidor
                        _buildSectionHeader(
                          icon: Icons.dns_outlined,
                          title: 'Configuração do Servidor',
                          subtitle: 'Endereço e credenciais de acesso',
                        ),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _ipController,
                                decoration: const InputDecoration(
                                  labelText: 'Endereço IP',
                                  prefixIcon: Icon(Icons.router_outlined),
                                ),
                                validator: (v) => (v == null || v.isEmpty) 
                                  ? 'Obrigatório' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: 'Porta',
                                  prefixIcon: Icon(Icons.settings_ethernet),
                                ),
                                validator: (v) => (v == null || v.isEmpty) 
                                  ? 'Obrigatório' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _tokenController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Token de Autenticação',
                            prefixIcon: Icon(Icons.key_outlined),
                            helperText: 'Token fornecido pelo administrador',
                          ),
                          validator: (v) => (v == null || v.isEmpty) 
                            ? 'Obrigatório' : null,
                        ),

                        const SizedBox(height: 32),
                        
                        // Seção: Módulo de Conexão
                        _buildSectionHeader(
                          icon: Icons.extension_outlined,
                          title: 'Módulo de Conexão',
                          subtitle: 'Selecione o tipo de ativo a monitorar',
                        ),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedModuleId,
                                decoration: InputDecoration(
                                  labelText: 'Selecione o Módulo',
                                  prefixIcon: _isLoadingModules 
                                    ? Container(
                                        padding: const EdgeInsets.all(12.0), 
                                        child: const SizedBox(
                                          width: 20, 
                                          height: 20, 
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2
                                          ),
                                        ),
                                      )
                                    : Icon(_selectedModule?.icon ?? Icons.apps),
                                ),
                                items: _availableModules.map((module) {
                                  return DropdownMenuItem(
                                    value: module.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          module.icon, 
                                          size: 20, 
                                          color: module.color
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: 
                                              CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                module.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (module.description.isNotEmpty)
                                                Text(
                                                  module.description,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[400],
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: _isLoadingModules ? null : (value) {
                                  setState(() {
                                    _selectedModuleId = value;
                                    _selectedModule = _availableModules
                                      .firstWhere((m) => m.id == value);
                                  });
                                  _loadModuleStructure();
                                },
                                validator: (v) => (v == null || v.isEmpty) 
                                  ? 'Selecione um módulo' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              onPressed: _isLoadingModules ? null : _fetchModules,
                              icon: Icon(
                                _isLoadingModules 
                                  ? Icons.hourglass_empty 
                                  : Icons.refresh
                              ),
                              tooltip: 'Buscar Módulos',
                              style: IconButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary
                                  .withOpacity(0.1),
                              ),
                            ),
                          ],
                        ),

                        // Info do módulo selecionado
                        if (_selectedModule != null) ...[
                          const SizedBox(height: 16),
                          _buildModuleInfoCard(_selectedModule!),
                        ],

                        const SizedBox(height: 32),
                        
                        // Seção: Identificação Manual
                        _buildSectionHeader(
                          icon: Icons.location_on_outlined,
                          title: 'Identificação Manual',
                          subtitle: 'Opcional: Localização física do dispositivo',
                        ),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _sectorController,
                                decoration: const InputDecoration(
                                  labelText: 'Setor',
                                  prefixIcon: Icon(Icons.business_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _floorController,
                                decoration: const InputDecoration(
                                  labelText: 'Andar',
                                  prefixIcon: Icon(Icons.stairs_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        
                        // Seção: Configurações Gerais
                        _buildSectionHeader(
                          icon: Icons.settings_outlined,
                          title: 'Configurações Gerais',
                          subtitle: 'Frequência de sincronização',
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<int>(
                          value: _selectedInterval,
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
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _saveAndRestartService,
                  icon: const Icon(Icons.save_outlined, size: 20),
                  label: const Text('Salvar e Ativar Serviço'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModuleInfoCard(ModuleInfo module) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: module.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: module.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(module.icon, color: module.color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tipo: ${module.type}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: module.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${module.assetCount} ativos',
                  style: TextStyle(
                    color: module.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          
          if (_isLoadingStructure) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Carregando estrutura do módulo...',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
              ),
            ),
          ] else if (_selectedModuleStructure != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Campos Coletados:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 8),
            _buildFieldsList(module.type),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldsList(String moduleType) {
    final fields = _moduleStructureService
      .getRequiredFieldsByType(moduleType)
      .keys
      .toList();

    // Mostra apenas os primeiros 8 campos
    final displayFields = fields.take(8).toList();
    final hasMore = fields.length > 8;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...displayFields.map((field) => Chip(
          label: Text(
            field,
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: Colors.grey[800],
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )),
        if (hasMore)
          Chip(
            label: Text(
              '+${fields.length - 8} mais',
              style: const TextStyle(fontSize: 10),
            ),
            backgroundColor: Colors.blue.withOpacity(0.3),
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}