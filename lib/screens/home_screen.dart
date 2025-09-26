// Ficheiro: lib/screens/home_screen.dart
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
  final _totemTypeController = TextEditingController(); // NOVO: Controlador para o tipo de totem
  final _formKey = GlobalKey<FormState>();

  final MonitoringService _monitoringService = MonitoringService();
  final SettingsService _settingsService = SettingsService();

  final List<Map<String, dynamic>> _intervalOptions = [
    {'label': '1 Minuto', 'value': 60},
    {'label': '5 Minutos', 'value': 300},
    {'label': '15 Minutos', 'value': 900},
    {'label': '30 Minutos', 'value': 1800},
    {'label': '1 Hora', 'value': 3600},
    {'label': '2 Horas', 'value': 7200},
    {'label': '5 Horas', 'value': 18000},
    {'label': '12 Horas', 'value': 43200},
    {'label': '24 Horas', 'value': 86400},
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
    _totemTypeController.text = _settingsService.totemType; // NOVO: Carrega o tipo de totem
    _selectedInterval = _settingsService.interval;

    if (_formKey.currentState?.validate() ?? false) {
      _monitoringService.start(
        '${_ipController.text}:${_portController.text}',
        _selectedInterval,
        _totemTypeController.text, // NOVO: Passa o tipo de totem
      );
    }
  }

  void _saveAndRestart() {
    if (_formKey.currentState!.validate()) {
      _settingsService.saveSettings(
        _ipController.text,
        _portController.text,
        _totemTypeController.text, // NOVO: Guarda o tipo de totem
        _selectedInterval,
      );
      _monitoringService.start(
        '${_ipController.text}:${_portController.text}',
        _selectedInterval,
        _totemTypeController.text, // NOVO: Passa o tipo de totem
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas e monitoramento reiniciado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agente de Monitoramento'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 20),
              _buildSettingsCard(),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveAndRestart,
                icon: const Icon(Icons.save),
                label: const Text('Salvar e Reiniciar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status Atual',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.statusNotifier,
              builder: (context, status, child) {
                return _buildStatusRow('Status:', status, _getStatusColor(status));
              },
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.lastUpdateNotifier,
              builder: (context, lastUpdate, child) {
                return _buildStatusRow('Última Atualização:', lastUpdate, Colors.black87);
              },
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: _monitoringService.errorNotifier,
              builder: (context, error, child) {
                if (error.isNotEmpty) {
                  return _buildStatusRow('Erro:', error, Colors.red.shade700);
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configurações',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Endereço IP do Servidor',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Porta do Servidor',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 16),
            // NOVO: Campo para o tipo de totem
            TextFormField(
              controller: _totemTypeController,
              decoration: const InputDecoration(
                labelText: 'Tipo de Totem',
                hintText: 'Ex: Atendimento, Autoatendimento',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedInterval,
              decoration: const InputDecoration(
                labelText: 'Intervalo de Sincronização',
                border: OutlineInputBorder(),
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
          ],
        ),
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
      case 'inativo (configure o servidor)':
      case 'inativo':
        return Colors.grey.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _totemTypeController.dispose(); // NOVO: Limpa o controlador
    _monitoringService.stop();
    super.dispose();
  }
}