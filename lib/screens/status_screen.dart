// File: lib/screens/status_screen.dart (REVISADO)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/utils/app_logger.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
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

  Future<Map<String, String>>? _networkInfoFuture;

  @override
  void initState() {
    super.initState();
    _networkInfoFuture = _getNetworkInfo();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _refreshNetworkInfo() {
    setState(() {
      _logger.i('Atualizando informações de rede manualmente...');
      _networkInfoFuture = _getNetworkInfo();
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

    // Evita mostrar minutos negativos se estiver atrasado
    if (diff.inSeconds < 0) return "Agora...";

    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds.remainder(60);
    return "Em ${minutes}m ${seconds}s";
  }

  void _showSystemInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Row(
          children: [
            Icon(Icons.computer, color: Colors.blue),
            SizedBox(width: 12),
            Text('Informações do Sistema'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: FutureBuilder<Map<String, String>>(
              future: _getSystemInfo(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Text('Erro: ${snapshot.error}');
                }

                final info = snapshot.data ?? {};

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: info.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              '${entry.key}:',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
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

  Future<Map<String, String>> _getSystemInfo() async {
    return {
      'Nome do Computador': Platform.environment['COMPUTERNAME'] ?? 'N/A',
      'Usuário': Platform.environment['USERNAME'] ?? 'N/A',
      'Sistema Operacional': Platform.operatingSystem,
      'Versão do SO': Platform.operatingSystemVersion,
      'Número de Processadores': Platform.numberOfProcessors.toString(),
      'Arquitetura': Platform.version,
    };
  }

  void _showLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('Logs Recentes'),
        content: SizedBox(
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

  String _decodeOutput(dynamic output) {
    if (output is List<int>) {
      return latin1.decode(output, allowInvalid: true);
    }
    return output.toString();
  }

  Future<Map<String, String>> _getNetworkInfo() async {
    final scriptName =
        'get_core_system_info_${DateTime.now().millisecondsSinceEpoch}.ps1';
    final tempDir = Directory.systemTemp;
    final scriptFile = File(p.join(tempDir.path, scriptName));

    try {
      final scriptContent = await rootBundle
          .loadString('assets/scripts/get_core_system_info.ps1');
      await scriptFile.writeAsString(scriptContent,
          flush: true, encoding: utf8);

      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );

      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode != 0) {
        _logger
            .e('Erro no script: $stderrString (Arquivo: ${scriptFile.path})');
        throw Exception('Erro no script: $stderrString');
      }

      if (stdoutString.isEmpty) {
        throw Exception('Script não retornou nada');
      }

      final Map<String, dynamic> data = json.decode(stdoutString);

      final Map<String, String> info = {
        'connection_type': data['connection_type']?.toString() ?? 'N/A',
        'ip': data['ip_address']?.toString() ?? 'N/A',
        'mac': data['mac_address']?.toString() ?? 'N/A',
        'bssid': data['mac_address_radio']?.toString() ?? 'N/A',
        'wifi_ssid': data['wifi_ssid']?.toString() ?? 'N/A',
        'signal': data['wifi_signal']?.toString() ?? 'N/A',
      };

      info.forEach((key, value) {
        if (value.trim().isEmpty || value.toLowerCase() == 'null') {
          info[key] = 'N/A';
        }
      });

      return info;
    } catch (e) {
      _logger.e('Erro ao obter informações de rede (get_core_system_info): $e');
      return {'connection_type': 'Erro', 'ip': 'N/A', 'mac': 'N/A'};
    } finally {
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (e) {
        _logger.w('Falha ao deletar script temporário: ${scriptFile.path}, $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();
    final theme = Theme.of(context);
    final moduleName = provider.selectedModule?.name ?? "N/A";
    final serverUrl =
        'http://${provider.ipController.text}:${provider.portController.text}';

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 800, // <-- Aumentei a largura do painel
          child: Column(
            children: [
              _buildHeader(theme, _backgroundService.isRunning),

              // === INÍCIO DA REORGANIZAÇÃO DA UI ===
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Linha 1: Estatísticas
                      _buildSyncStats(context, _backgroundService),
                      const SizedBox(height: 16),

                      // Linha 2: Duas Colunas
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Coluna 1: Status e Configuração
                          Expanded(
                            flex: 3, // 3/5 do espaço
                            child: Column(
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
                                  content: _buildConnectionConfig(
                                      provider, serverUrl, moduleName),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Coluna 2: Rede e Logs
                          Expanded(
                            flex: 2, // 2/5 do espaço
                            child: Column(
                              children: [
                                _buildStatusCard(
                                    theme: theme,
                                    title: 'Informações de Rede',
                                    icon: Icons.wifi,
                                    content: _buildNetworkInfo(),
                                    trailing: IconButton(
                                      // Botão de refresh
                                      icon: const Icon(Icons.refresh,
                                          size: 18, color: Colors.grey),
                                      onPressed: _refreshNetworkInfo,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Atualizar informações de rede',
                                    )),
                                const SizedBox(height: 16),
                                _buildStatusCard(
                                  theme: theme,
                                  title: 'Logs Recentes',
                                  icon: Icons.article_outlined,
                                  content: _buildLogs(theme),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // === FIM DA REORGANIZAÇÃO DA UI ===

              // Rodapé com Ações
              _buildFooterActions(theme, provider),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS REATORADOS ---

  Widget _buildServiceStatus() {
    final statusColor =
        _backgroundService.isRunning ? Colors.green : Colors.grey;
    final provider = context.watch<AgentProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _backgroundService.isRunning
                  ? Icons.check_circle
                  : Icons.pause_circle,
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
            const Spacer(),
            if (_backgroundService.lastRunStatus == "Sincronizando...")
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const Divider(height: 24),
        _buildInfoRow('Última Sincronização:',
            _formatDateTime(_backgroundService.lastRunTime)),
        const SizedBox(height: 8),
        _buildInfoRow('Status:', _backgroundService.lastRunStatus),
        const SizedBox(height: 8),
        _buildInfoRow('Próxima Sincronização:',
            _formatNextRun(_backgroundService.nextRunTime)),
        const SizedBox(height: 8),
        _buildInfoRow(
            'Intervalo:', '${provider.selectedInterval ~/ 60} minutos'),
      ],
    );
  }

  Widget _buildConnectionConfig(
      AgentProvider provider, String serverUrl, String moduleName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Servidor:', serverUrl),
        const SizedBox(height: 8),
        _buildInfoRow('Módulo:', moduleName),
        const SizedBox(height: 8),
        _buildInfoRow(
            'Nome do Ativo:',
            provider.assetNameController.text.isEmpty
                ? 'Automático (Nome do PC)'
                : provider.assetNameController.text),
        const SizedBox(height: 8),
        _buildInfoRow(
            'Setor:',
            provider.sectorController.text.isEmpty
                ? 'Não definido'
                : provider.sectorController.text),
        const SizedBox(height: 8),
        _buildInfoRow(
            'Andar:',
            provider.floorController.text.isEmpty
                ? 'Não definido'
                : provider.floorController.text),
      ],
    );
  }

  Widget _buildNetworkInfo() {
    return FutureBuilder<Map<String, String>>(
      future: _networkInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }

        if (snapshot.hasError) {
          return _buildInfoRow('Erro:', 'Falha ao carregar');
        }

        if (snapshot.hasData) {
          final info = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info['connection_type'] == 'WiFi') ...[
                _buildInfoRow('Tipo:', '📶 WiFi'),
                const SizedBox(height: 8),
                _buildInfoRow('SSID:', info['wifi_ssid'] ?? 'N/A'),
                const SizedBox(height: 8),
                _buildInfoRow('BSSID:', info['bssid'] ?? 'N/A'),
                const SizedBox(height: 8),
                _buildInfoRow('Sinal:', info['signal'] ?? 'N/A'),
              ] else ...[
                _buildInfoRow(
                    'Tipo:', '🔌 ${info['connection_type'] ?? 'N/A'}'),
              ],
              const SizedBox(height: 8),
              _buildInfoRow('IP:', info['ip'] ?? 'N/A'),
              const SizedBox(height: 8),
              _buildInfoRow('MAC:', info['mac'] ?? 'N/A'),
            ],
          );
        }
        return const Center(
            child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ));
      },
    );
  }

  Widget _buildLogs(ThemeData theme) {
    return Column(
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
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showLogs(context),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Ver Logs Completos'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Limpar logs',
              color: Colors.red.withOpacity(0.8),
              onPressed: () {
                AppLogger.logHistory.clear();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs limpos')),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterActions(ThemeData theme, AgentProvider provider) {
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                    backgroundColor: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _backgroundService.isRunning
                      ? () {
                          _backgroundService.stop();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Serviço pausado')),
                          );
                        }
                      : () {
                          _backgroundService.start();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Serviço retomado')),
                          );
                        },
                  icon: Icon(
                    _backgroundService.isRunning
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 20,
                  ),
                  label:
                      Text(_backgroundService.isRunning ? 'Pausar' : 'Retomar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _backgroundService.isRunning
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showSystemInfo(context),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Info do Sistema'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      context.read<AgentProvider>().enterReconfiguration(),
                  icon: const Icon(Icons.replay_outlined, size: 20),
                  label: const Text('Reconfigurar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Helper: Linha de Informação
Widget _buildInfoRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 130, // Largura fixa para alinhamento
        child: Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value.isEmpty ? "N/D" : value, // Garante que não fique vazio
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
    ],
  );
}

// Helper: Card de Status (base para os outros)
Widget _buildStatusCard({
  required ThemeData theme,
  required String title,
  required IconData icon,
  required Widget content,
  Widget? trailing, // Novo: widget opcional no final do header
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
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (trailing != null) trailing, // Adiciona o widget extra
          ],
        ),
        const SizedBox(height: 16),
        content,
      ],
    ),
  );
}

// Helper: Header
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
          child: Icon(Icons.shield_outlined,
              color: theme.colorScheme.primary, size: 32),
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

// Helper: Stats
Widget _buildSyncStats(
    BuildContext context, BackgroundService backgroundService) {
  final theme = Theme.of(context);
  return Row(
    children: [
      Expanded(
        child: _buildStatCard(
          theme: theme,
          icon: Icons.check_circle_outline,
          label: 'Sincronizações',
          value: '${backgroundService.syncCount}',
          color: Colors.green,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          theme: theme,
          icon: Icons.error_outline,
          label: 'Erros',
          value: '${backgroundService.errorCount}',
          color: Colors.red,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          theme: theme,
          icon: Icons.schedule,
          label: 'Uptime',
          value: _formatUptime(backgroundService.startTime),
          color: Colors.blue,
        ),
      ),
    ],
  );
}

Widget _buildStatCard({
  required ThemeData theme,
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

String _formatUptime(DateTime? startTime) {
  if (startTime == null) return "N/A";
  final duration = DateTime.now().difference(startTime);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return "${hours}h ${minutes}m";
}
