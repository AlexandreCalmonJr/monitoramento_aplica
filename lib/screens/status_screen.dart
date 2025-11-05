// File: lib/screens/status_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/services/background_service.dart';
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

  Future<Map<String, String>> _getNetworkInfo() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-command',
          r'''
          $wifiAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and ($_.InterfaceDescription -match "Wi-Fi|Wireless") } | Select-Object -First 1
          $ethernetAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Wi-Fi|Wireless|Virtual" } | Select-Object -First 1
          $activeAdapter = if ($wifiAdapter) { $wifiAdapter } else { $ethernetAdapter }
          $net = if ($activeAdapter) { Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $activeAdapter.InterfaceIndex | Select-Object -First 1 } else { $null }
          
          $bssid = $null; $ssid = $null; $signal = $null
          if ($wifiAdapter) {
              $wlanInfo = netsh wlan show interfaces | Select-String "BSSID", "SSID", "Signal"
              foreach ($line in $wlanInfo) {
                  $lineStr = $line.ToString().Trim()
                  if ($lineStr -match "BSSID\s+:\s+(.+)") { $bssid = $Matches[1].Trim() }
                  if ($lineStr -match "SSID\s+:\s+(.+)" -and $lineStr -notmatch "BSSID") { $ssid = $Matches[1].Trim() }
                  if ($lineStr -match "Signal\s+:\s+(\d+)%") { $signal = $Matches[1].Trim() + "%" }
              }
          }
          
          $connectionType = if ($wifiAdapter -and $wifiAdapter.Status -eq "Up") { "WiFi" } else { "Ethernet" }
          
          Write-Output "TYPE:$connectionType"
          Write-Output "IP:$($net.IPAddress)"
          Write-Output "MAC:$($activeAdapter.MacAddress)"
          if ($bssid) { Write-Output "BSSID:$bssid" }
          if ($ssid) { Write-Output "SSID:$ssid" }
          if ($signal) { Write-Output "SIGNAL:$signal" }
          '''
        ],
        runInShell: true,
      );

      final Map<String, String> info = {};
      final lines = result.stdout.toString().split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('TYPE:')) {
          info['connection_type'] = trimmed.substring(5);
        } else if (trimmed.startsWith('IP:')) {
          info['ip'] = trimmed.substring(3);
        } else if (trimmed.startsWith('MAC:')) {
          info['mac'] = trimmed.substring(4);
        } else if (trimmed.startsWith('BSSID:')) {
          info['bssid'] = trimmed.substring(6);
        } else if (trimmed.startsWith('SSID:')) {
          info['wifi_ssid'] = trimmed.substring(5);
        } else if (trimmed.startsWith('SIGNAL:')) {
          info['signal'] = trimmed.substring(7);
        }
      }

      return info;
    } catch (e) {
      _logger.e('Erro ao obter informações de rede: $e');
      return {'connection_type': 'Erro', 'ip': 'N/A', 'mac': 'N/A'};
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
          width: 600,
          child: Column(
            children: [
              _buildHeader(theme, _backgroundService.isRunning),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // NOVO: Card de Estatísticas
                      _buildSyncStats(context, _backgroundService),
                      const SizedBox(height: 16),

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
                            const SizedBox(height: 8),
                            
                            // <-- NOVO CAMPO ADICIONADO AQUI
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
                            const Divider(height: 24),
                            const Row(
                              children: [
                                Icon(Icons.wifi, size: 16, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  'Informações de Rede',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<Map<String, String>>(
                              future: _getNetworkInfo(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  final info = snapshot.data!;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (info['connection_type'] ==
                                          'WiFi') ...[
                                        _buildInfoRow('Tipo:', '📶 WiFi'),
                                        const SizedBox(height: 8),
                                        if (info['wifi_ssid'] != null)
                                          _buildInfoRow(
                                              'SSID:', info['wifi_ssid']!),
                                        const SizedBox(height: 8),
                                        if (info['bssid'] != null)
                                          _buildInfoRow(
                                              'BSSID:', info['bssid']!),
                                        const SizedBox(height: 8),
                                        if (info['signal'] != null)
                                          _buildInfoRow(
                                              'Sinal:', info['signal']!),
                                      ] else ...[
                                        _buildInfoRow('Tipo:',
                                            '🔌 ${info['connection_type'] ?? 'Ethernet'}'),
                                      ],
                                      const SizedBox(height: 8),
                                      _buildInfoRow('IP:', info['ip'] ?? 'N/A'),
                                      const SizedBox(height: 8),
                                      _buildInfoRow(
                                          'MAC:', info['mac'] ?? 'N/A'),
                                    ],
                                  );
                                }
                                return const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                );
                              },
                            )
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
                            // ##### INÍCIO DA ALTERAÇÃO 2 #####
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _showLogs(context),
                                    icon:
                                        const Icon(Icons.open_in_new, size: 16),
                                    label: const Text('Ver Logs Completos'),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            theme.colorScheme.secondary,
                                        textStyle:
                                            const TextStyle(fontSize: 12),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // MUDANÇA: Substituído ElevatedButton por IconButton
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Limpar logs',
                                  color: Colors.red.withOpacity(0.8),
                                  onPressed: () {
                                    AppLogger.logHistory.clear();
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Logs limpos')),
                                    );
                                  },
                                ),
                              ],
                            ),
                            // ##### FIM DA ALTERAÇÃO 2 #####
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Rodapé com Ações MELHORADO
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // PRIMEIRA LINHA DE BOTÕES
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
                                      const SnackBar(
                                          content: Text('Serviço pausado')),
                                    );
                                  }
                                : () {
                                    _backgroundService.start();
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Serviço retomado')),
                                    );
                                  },
                            icon: Icon(
                              _backgroundService.isRunning
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 20,
                            ),
                            label: Text(_backgroundService.isRunning
                                ? 'Pausar'
                                : 'Retomar'),
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
                    // SEGUNDA LINHA DE BOTÕES
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showSystemInfo(
                                context), // NOVO: Você vai criar esse método
                            icon: const Icon(Icons.info_outline, size: 18),
                            label: const Text('Info do Sistema'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context
                                .read<AgentProvider>()
                                .enterReconfiguration(),
                            icon: const Icon(Icons.settings_outlined, size: 20),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceStatus() {
    final statusColor =
        _backgroundService.isRunning ? Colors.green : Colors.grey;
    final provider = context.watch<AgentProvider>(); // ADICIONE

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Principal
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
            // NOVO: Indicador de progresso quando sincronizando
            if (_backgroundService.lastRunStatus == "Sincronizando...")
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const Divider(height: 24),

        // Informações detalhadas
        _buildInfoRow('Última Sincronização:',
            _formatDateTime(_backgroundService.lastRunTime)),
        const SizedBox(height: 8),
        _buildInfoRow('Status:', _backgroundService.lastRunStatus),
        const SizedBox(height: 8),
        _buildInfoRow('Próxima Sincronização:',
            _formatNextRun(_backgroundService.nextRunTime)),
        const SizedBox(height: 8),
        _buildInfoRow(
            'Intervalo:', '${provider.selectedInterval ~/ 60} minutos'), // NOVO
      ],
    );
  }
}

// ##### INÍCIO DA ALTERAÇÃO 1 #####
Widget _buildInfoRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // MUDANÇA: Adicionado um SizedBox para definir uma largura fixa para o rótulo.
      SizedBox(
        width: 120, // <-- Ajuste este valor se precisar de mais/menos espaço
        child: Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
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
// ##### FIM DA ALTERAÇÃO 1 #####

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
          value:
              '${backgroundService.syncCount}', // Você vai adicionar isso no BackgroundService
          color: Colors.green,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          theme: theme,
          icon: Icons.error_outline,
          label: 'Erros',
          value:
              '${backgroundService.errorCount}', // Você vai adicionar isso no BackgroundService
          color: Colors.red,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          theme: theme,
          icon: Icons.schedule,
          label: 'Uptime',
          value: _formatUptime(backgroundService
              .startTime), // Você vai adicionar isso no BackgroundService
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