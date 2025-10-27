// File: lib/screens/status_screen.dart
import 'dart:async';

import 'package:agent_windows/background_service.dart';
import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import for DateFormat
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final BackgroundService _backgroundService = locator<BackgroundService>();
  final Logger _logger = locator<Logger>();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Inicia um timer para atualizar a UI (status de tempo) a cada segundo
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return "N/A";
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
  }

  String _formatNextRun(DateTime? dt) {
    if (dt == null) return "N/A";
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return "Agora...";
    return "Em ${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s";
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Logs Recentes'),
        content: Container(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              AppLogger.getRecentLogs(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();
    final theme = Theme.of(context);
    final moduleName = provider.selectedModule?.name ?? "N/A";
    final serverUrl = 'http://${provider.ipController.text}:${provider.portController.text}';

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          child: Column(
            children: [
              // Cabeçalho
              _buildHeader(theme, _backgroundService.isRunning),
              
              // Corpo
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(
                        theme: theme,
                        title: 'Status do Serviço',
                        icon: Icons.sync,
                        content: _buildServiceStatus(),
                      ),
                      const SizedBox(height: 16),
                      _buildStatusCard(
                        theme: theme,
                        title: 'Configuração de Conexão',
                        icon: Icons.dns_outlined,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow('Servidor:', serverUrl),
                            const SizedBox(height: 8),
                            _buildInfoRow('Módulo:', moduleName),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStatusCard(
                        theme: theme,
                        title: 'Logs Recentes',
                        icon: Icons.article_outlined,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SingleChildScrollView(
                                reverse: true,
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  AppLogger.getRecentLogs(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showLogs(context),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Ver Logs Completos'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.secondary,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Rodapé com Ações
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
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _logger.i('Sincronização forçada pelo usuário');
                          _backgroundService.runCycle();
                          setState(() {});
                        },
                        icon: const Icon(Icons.sync_outlined, size: 20),
                        label: const Text('Forçar Sincronização'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => context.read<AgentProvider>().enterReconfiguration(),
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        label: const Text('Reconfigurar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceStatus() {
    final statusColor = _backgroundService.isRunning ? Colors.green : Colors.grey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _backgroundService.isRunning ? Icons.check_circle : Icons.pause_circle,
              size: 18,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Text(
              _backgroundService.isRunning ? 'Ativo' : 'Parado',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        _buildInfoRow('Última Sincronização:', _formatDateTime(_backgroundService.lastRunTime)),
        const SizedBox(height: 8),
        _buildInfoRow('Status:', _backgroundService.lastRunStatus),
        const SizedBox(height: 8),
        _buildInfoRow('Próxima Sincronização:', _formatNextRun(_backgroundService.nextRunTime)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isRunning) {
    final statusColor = isRunning ? Colors.green : Colors.grey;
    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRunning ? Icons.check_circle : Icons.pause_circle,
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? 'Ativo' : 'Parado',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}