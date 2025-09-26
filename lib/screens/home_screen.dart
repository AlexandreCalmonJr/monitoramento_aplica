// Ficheiro: lib/screens/home_screen.dart
// DESCRIÇÃO: Adicionado um campo para selecionar o intervalo de sincronização.

import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter/material.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final MonitoringService _monitoringService = MonitoringService();
  final SettingsService _settingsService = SettingsService();

  // Opções para o intervalo de tempo
  final List<Map<String, dynamic>> _intervalOptions = [
    {'label': '1 Minuto', 'value': 60},
    {'label': '5 Minutos', 'value': 300},
    {'label': '15 Minutos', 'value': 900},
    {'label': '30 Minutos', 'value': 1800},
  ];
  late int _selectedInterval;

  @override
  void initState() {
    super.initState();
    _selectedInterval = _intervalOptions.first['value'];
    _loadSettingsAndStart();
  }

  Future<void> _loadSettingsAndStart() async {
    await _settingsService.loadSettings();
    _ipController.text = _settingsService.ip;
    _portController.text = _settingsService.port;
    
    // Atualiza a UI com o intervalo guardado
    setState(() {
      _selectedInterval = _settingsService.intervalInSeconds;
    });

    if (_settingsService.ip.isNotEmpty && _settingsService.port.isNotEmpty) {
      _monitoringService.start(
        '${_settingsService.ip}:${_settingsService.port}',
        _settingsService.intervalInSeconds,
      );
    }
  }

  void _saveAndRestart() {
    if (_formKey.currentState!.validate()) {
      final ip = _ipController.text;
      final port = _portController.text;
      final interval = _selectedInterval;

      _settingsService.saveSettings(ip, port, interval);
      _monitoringService.start('$ip:$port', interval);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas! O monitoramento foi iniciado/atualizado.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _monitoringService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agente de Monitoramento'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusPanel(),
            const SizedBox(height: 32),
            _buildSettingsPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status do Agente',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.statusNotifier,
              builder: (context, statusValue, child) {
                return Row(
                  children: [
                    Expanded(
                      child: _buildStatusRow(
                        'Status:',
                        statusValue,
                        _getStatusColor(statusValue),
                      ),
                    ),
                    if (statusValue.toLowerCase().contains('recolher') ||
                        statusValue.toLowerCase().contains('enviar'))
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.lastUpdateNotifier,
              builder: (context, lastUpdateValue, child) {
                return _buildStatusRow(
                  'Último Envio:',
                  lastUpdateValue,
                  Colors.grey.shade700,
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.errorNotifier,
              builder: (context, errorValue, child) {
                if (errorValue.isEmpty) return const SizedBox.shrink();
                return _buildStatusRow(
                  'Erro:',
                  errorValue,
                  Colors.red.shade700,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Configuração do Servidor',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Endereço IP do Servidor',
              hintText: 'ex: 192.168.1.10',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
            keyboardType: TextInputType.url,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor, insira o IP do servidor.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Porta do Servidor',
              hintText: 'ex: 3000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.power),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor, insira a porta.';
              }
              if (int.tryParse(value) == null) {
                return 'A porta deve ser um número.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // NOVO CAMPO DE SELEÇÃO DE INTERVALO
          DropdownButtonFormField<int>(
            value: _selectedInterval,
            decoration: const InputDecoration(
              labelText: 'Intervalo de Sincronização',
              border: OutlineInputBorder(),
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
                setState(() {
                  _selectedInterval = newValue;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saveAndRestart,
            icon: const Icon(Icons.save),
            label: const Text('Salvar e Iniciar Monitoramento'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 16,
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativo':
        return Colors.green.shade600;
      case 'erro':
        return Colors.red.shade700;
      case 'inativo':
        return Colors.grey.shade600;
      default:
        return Colors.orange.shade700;
    }
  }
}

