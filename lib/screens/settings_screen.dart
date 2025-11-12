// File: lib/screens/settings_screen.dart
// Exemplo de tela de configurações com opção de sistema legado
import 'package:agent_windows/providers/agent_provider.dart'; // <-- ADICIONADO
import 'package:agent_windows/services/module_detection_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart'; // <-- ADICIONADO

class SettingsScreen extends StatefulWidget {
  final Logger logger;
  final ModuleDetectionService detectionService;

  const SettingsScreen({
    super.key,
    required this.logger,
    required this.detectionService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // bool _forceLegacyMode = false; // <-- REMOVIDO
  bool _isDetecting = false;
  SystemType? _detectedSystem;
  String? _detectionMessage;

  @override
  Widget build(BuildContext context) {
    // --- INÍCIO DA ADIÇÃO ---
    // Lê o provider para obter o estado atual
    final agentProvider = context.watch<AgentProvider>();
    final bool forceLegacyMode = agentProvider.forceLegacyMode;
    // --- FIM DA ADIÇÃO ---

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações de Monitoramento'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cartão de Detecção Automática
            _buildDetectionCard(),
            
            const SizedBox(height: 24),
            
            // Cartão de Modo Forçado
            // --- MUDANÇA ---
            _buildForceModeCard(agentProvider, forceLegacyMode),
            // --- FIM DA MUDANÇA ---
            
            const SizedBox(height: 24),
            
            // Cartão de Informações
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Detecção Automática',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Detecta automaticamente qual sistema de monitoramento está ativo no servidor.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            if (_detectedSystem != null) ...[
              _buildSystemIndicator(),
              const SizedBox(height: 12),
            ],
            
            if (_detectionMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _detectionMessage!,
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            ElevatedButton.icon(
              onPressed: _isDetecting ? null : _detectSystem,
              icon: _isDetecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isDetecting ? 'Detectando...' : 'Detectar Sistema'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemIndicator() {
    IconData icon;
    Color color;
    String title;
    String description;

    switch (_detectedSystem!) {
      case SystemType.newModules:
        icon = Icons.widgets;
        color = Colors.green;
        title = 'Sistema Novo';
        description = 'Módulos customizados detectados';
        break;
      case SystemType.legacyTotem:
        icon = Icons.desktop_windows;
        color = Colors.orange;
        title = 'Sistema Legado';
        description = 'Sistema de Totem detectado';
        break;
      case SystemType.both:
        icon = Icons.sync_alt;
        color = Colors.purple;
        title = 'Modo Híbrido';
        description = 'Ambos os sistemas estão ativos';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: color, size: 28),
        ],
      ),
    );
  }

  // --- MUDANÇA ---
  Widget _buildForceModeCard(AgentProvider provider, bool forceLegacyMode) {
  // --- FIM DA MUDANÇA ---
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Modo Forçado',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Força o uso do sistema legado de Totem, ignorando a detecção automática.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              // --- MUDANÇA ---
              value: forceLegacyMode, // Usa o valor do provider
              onChanged: (value) {
                // Chama o método do provider para salvar
                context.read<AgentProvider>().updateForceLegacyMode(value);
              },
              // --- FIM DA MUDANÇA ---
              title: const Text('Forçar Sistema Legado'),
              subtitle: Text(
                forceLegacyMode // Usa o valor do provider
                    ? 'Enviando apenas para sistema legado de Totem'
                    : 'Usando detecção automática',
                style: TextStyle(
                  color: forceLegacyMode ? Colors.orange : Colors.grey, // Usa o valor do provider
                ),
              ),
              activeColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            
            if (forceLegacyMode) // Usa o valor do provider
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modo legado ativo. Os dados serão enviados apenas para /api/monitoring/data',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Informações',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              icon: Icons.widgets,
              title: 'Sistema Novo',
              description: 'Usa módulos customizados (/api/modules)',
            ),
            const Divider(height: 24),
            _buildInfoRow(
              icon: Icons.desktop_windows,
              title: 'Sistema Legado',
              description: 'Usa sistema de Totem (/api/monitoring)',
            ),
            const Divider(height: 24),
            _buildInfoRow(
              icon: Icons.sync_alt,
              title: 'Modo Híbrido',
              description: 'Envia para ambos os sistemas simultaneamente',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.blue, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _detectSystem() async {
    setState(() {
      _isDetecting = true;
      _detectionMessage = null;
    });

    // --- INÍCIO DA MUDANÇA ---
    // Busca o provider para pegar IP e Token reais
    final agentProvider = context.read<AgentProvider>();
    final serverUrl = 'http://${agentProvider.ipController.text}:${agentProvider.portController.text}';
    final token = agentProvider.tokenController.text;
    
    // Validação básica
    if (agentProvider.ipController.text.isEmpty || agentProvider.tokenController.text.isEmpty) {
       setState(() {
        _isDetecting = false;
        _detectionMessage = 'Erro: IP do servidor ou Token não configurados na tela anterior.';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_detectionMessage!),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // --- FIM DA MUDANÇA ---
    
    // CORREÇÃO (Item 14): Adicionar validação de formato
    final ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!ipPattern.hasMatch(agentProvider.ipController.text)) {
      setState(() {
        _isDetecting = false;
        _detectionMessage = 'Erro: Formato de IP inválido.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_detectionMessage!),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final port = int.tryParse(agentProvider.portController.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _isDetecting = false;
        _detectionMessage = 'Erro: Porta inválida (deve ser 1-65535).';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_detectionMessage!),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // --- FIM DA CORREÇÃO ---

    try {
      final detection = await widget.detectionService.detectActiveSystem(
        serverUrl: serverUrl, // Usa o valor do provider
        token: token,       // Usa o valor do provider
      );

      setState(() {
        _detectedSystem = detection.systemType;
        _detectionMessage = _getDetectionMessage(detection);
        _isDetecting = false;
      });

      // Mostra notificação de sucesso
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_detectionMessage ?? 'Detecção concluída'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
        _detectionMessage = 'Erro na detecção: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao detectar sistema: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getDetectionMessage(ModuleDetectionResult detection) {
    switch (detection.systemType) {
      case SystemType.newModules:
        return 'Sistema novo detectado. Módulo: ${detection.primaryModuleType ?? "N/A"}';
      case SystemType.legacyTotem:
        return 'Sistema legado de Totem detectado';
      case SystemType.both:
        return 'Ambos os sistemas detectados. Dados serão enviados para ambos.';
    }
  }

  // Método para obter a configuração atual
  Map<String, dynamic> getConfiguration() {
    // Agora lê o valor real do provider
    final forceLegacyMode = context.read<AgentProvider>().forceLegacyMode;
    return {
      'forceLegacyMode': forceLegacyMode,
      'detectedSystem': _detectedSystem?.toString(),
    };
  }
}