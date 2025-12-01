// File: lib/screens/status_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:agent_windows/widgets/app_card.dart';
import 'package:agent_windows/widgets/primary_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

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

    if (diff.inSeconds < 0) return "Agora...";

    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds.remainder(60);
    return "${minutes}m ${seconds}s";
  }

  void _showSystemInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        title: const Row(
          children: [
            Icon(Icons.computer, color: Color(0xFF2563EB)),
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
                              style: const TextStyle(
                                color: Color(0xFFA1A1AA),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: const TextStyle(color: Color(0xFFFAFAFA)),
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
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Logs Recentes'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              AppLogger.getRecentLogs(),
              style: GoogleFonts.firaCode(fontSize: 12, color: const Color(0xFFD4D4D8)),
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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SizedBox(
          width: 1000,
          child: Column(
            children: [
              _buildHeader(theme, _backgroundService.isRunning),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Stats Row
                      _buildSyncStats(context, _backgroundService),
                      const SizedBox(height: 24),

                      // Main Content
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                _buildStatusCard(
                                  theme: theme,
                                  title: 'Status do Serviço',
                                  icon: Icons.sync,
                                  content: _buildServiceStatus(),
                                ).animate().fadeIn(delay: 200.ms).slideX(),
                                const SizedBox(height: 16),
                                _buildStatusCard(
                                  theme: theme,
                                  title: 'Configuração',
                                  icon: Icons.settings_ethernet,
                                  content: _buildConnectionConfig(
                                      provider, serverUrl, moduleName),
                                ).animate().fadeIn(delay: 300.ms).slideX(),
                              ],
                            ),
                          ),

                          const SizedBox(width: 24),

                          // Right Column
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                _buildStatusCard(
                                  theme: theme,
                                  title: 'Rede',
                                  icon: Icons.wifi,
                                  content: _buildNetworkInfo(),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.refresh,
                                        size: 18, color: Color(0xFFA1A1AA)),
                                    onPressed: _refreshNetworkInfo,
                                    tooltip: 'Atualizar',
                                  ),
                                ).animate().fadeIn(delay: 400.ms).slideX(),
                                const SizedBox(height: 16),
                                _buildStatusCard(
                                  theme: theme,
                                  title: 'Logs',
                                  icon: Icons.terminal,
                                  content: _buildLogs(theme),
                                ).animate().fadeIn(delay: 500.ms).slideX(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _buildFooterActions(theme, provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceStatus() {
    final statusColor =
        _backgroundService.isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444); // Emerald 500 : Red 500
    final provider = context.watch<AgentProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _backgroundService.isRunning ? 'ATIVO' : 'PARADO',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
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
        const SizedBox(height: 24),
        _buildInfoRow('Última Sincronização',
            _formatDateTime(_backgroundService.lastRunTime)),
        const SizedBox(height: 12),
        _buildInfoRow('Status Atual', _backgroundService.lastRunStatus),
        const SizedBox(height: 12),
        _buildInfoRow('Próxima Execução',
            _formatNextRun(_backgroundService.nextRunTime)),
        const SizedBox(height: 12),
        _buildInfoRow(
            'Intervalo', '${provider.selectedInterval ~/ 60} minutos'),
      ],
    );
  }

  Widget _buildConnectionConfig(
      AgentProvider provider, String serverUrl, String moduleName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Servidor', serverUrl),
        const SizedBox(height: 12),
        _buildInfoRow('Módulo', moduleName),
        const SizedBox(height: 12),
        _buildInfoRow(
            'Ativo',
            provider.assetNameController.text.isEmpty
                ? 'Automático'
                : provider.assetNameController.text),
        const SizedBox(height: 12),
        _buildInfoRow(
            'Localização',
            '${provider.sectorController.text.isEmpty ? 'N/A' : provider.sectorController.text} - ${provider.floorController.text.isEmpty ? 'N/A' : provider.floorController.text}'),
      ],
    );
  }

  Widget _buildNetworkInfo() {
    return FutureBuilder<Map<String, String>>(
      future: _networkInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }

        if (snapshot.hasError) {
          return _buildInfoRow('Erro', 'Falha ao carregar');
        }

        if (snapshot.hasData) {
          final info = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Tipo', info['connection_type'] ?? 'N/A'),
              const SizedBox(height: 12),
              _buildInfoRow('IP', info['ip'] ?? 'N/A'),
              const SizedBox(height: 12),
              _buildInfoRow('MAC', info['mac'] ?? 'N/A'),
              if (info['wifi_ssid'] != 'N/A') ...[
                const SizedBox(height: 12),
                _buildInfoRow('SSID', info['wifi_ssid'] ?? 'N/A'),
                const SizedBox(height: 12),
                _buildInfoRow('Sinal', info['signal'] ?? 'N/A'),
              ]
            ],
          );
        }
        return const SizedBox();
      },
    );
  }

  Widget _buildLogs(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF09090B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF27272A)),
          ),
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.all(8),
            child: Text(
              AppLogger.getRecentLogs(),
              style: GoogleFonts.firaCode(
                fontSize: 11,
                color: const Color(0xFFD4D4D8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showLogs(context),
                child: const Text('Expandir', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Limpar logs',
              color: const Color(0xFFEF4444),
              onPressed: () {
                AppLogger.logHistory.clear();
                setState(() {});
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              onPressed: () {
                _logger.i('Sincronização forçada pelo usuário');
                _backgroundService.runCycle();
                setState(() {});
              },
              text: 'Sincronizar',
              icon: Icons.sync,
              backgroundColor: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: PrimaryButton(
              onPressed: _backgroundService.isRunning
                  ? () {
                      _backgroundService.stop();
                      setState(() {});
                    }
                  : () {
                      _backgroundService.start();
                      setState(() {});
                    },
              text: _backgroundService.isRunning ? 'Pausar' : 'Iniciar',
              icon: _backgroundService.isRunning
                  ? Icons.pause
                  : Icons.play_arrow,
              backgroundColor: _backgroundService.isRunning ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => _showSystemInfo(context),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Info do Sistema',
            color: const Color(0xFFA1A1AA),
          ),
          IconButton(
            onPressed: () =>
                context.read<AgentProvider>().enterReconfiguration(),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            color: const Color(0xFFA1A1AA),
          ),
        ],
      ),
    ).animate().slideY(begin: 1, end: 0, delay: 600.ms);
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? "N/D" : value,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFFFAFAFA)),
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
    Widget? trailing,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF2563EB)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 20),
          content,
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isRunning) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agente de Monitoramento',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFAFAFA),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sistema ativo e monitorando',
                  style: const TextStyle(
                    color: Color(0xFFA1A1AA),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.5, end: 0);
  }

  Widget _buildSyncStats(
      BuildContext context, BackgroundService backgroundService) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Último Ping',
            value: DateFormat('HH:mm').format(backgroundService.lastRunTime ?? DateTime.now()),
            icon: Icons.access_time,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Status',
            value: backgroundService.isRunning ? 'Online' : 'Offline',
            icon: Icons.wifi_tethering,
            valueColor: backgroundService.isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Falhas',
            value: '0', // Placeholder for now
            icon: Icons.warning_amber,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFA1A1AA), size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFFFAFAFA),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
