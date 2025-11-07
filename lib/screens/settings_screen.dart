import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class SettingsScreen extends StatefulWidget {
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // --- Variáveis Adicionadas ---
  // (Seus métodos dependiam delas, então eu as declarei)
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final Logger _logger = Logger();
  // --- Fim das Variáveis Adicionadas ---

  bool _isTesting = false;
  String? _testResult;

  // ✅ BOTÃO DE TESTE DE CONEXÃO
  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final serverUrl = 'http://${_ipController.text}:${_portController.text}';

      // Testa conectividade básica
      final response = await http
          .get(
            Uri.parse('$serverUrl/health'),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _testResult = '✅ Servidor Online\n'
              'Status: ${data['status']}\n'
              'MongoDB: ${data['mongodb']}\n'
              'Uptime: ${data['uptimeFormatted']}';
        });
      } else {
        setState(() {
          _testResult =
              '❌ Servidor respondeu com erro: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '❌ Falha na conexão:\n${e.toString()}';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  // ✅ AUTO-DETECÇÃO DE SERVIDOR NA REDE
  Future<void> _autoDetectServer() async {
    setState(() => _isTesting = true);

    try {
      // Obtém IP local
      final localIp = await _getLocalIp();
      final subnet = localIp.substring(0, localIp.lastIndexOf('.'));

      _logger.i('🔍 Procurando servidor na rede: $subnet.x');

      // Testa IPs .1 a .254 na subnet
      for (int i = 1; i <= 254; i++) {
        final testIp = '$subnet.$i';

        try {
          final response = await http
              .get(
                Uri.parse('http://$testIp:3000/health'),
              )
              .timeout(Duration(seconds: 2));

          if (response.statusCode == 200) {
            _logger.i('✅ Servidor encontrado: $testIp');
            setState(() {
              _ipController.text = testIp;
              _portController.text = '3000';
              _testResult = '✅ Servidor encontrado automaticamente!';
            });
            return;
          }
        } catch (e) {
          // Ignora erros e continua
        }
      }

      setState(() {
        _testResult = '❌ Nenhum servidor encontrado na rede';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<String> _getLocalIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '192.168.0.1';
  }

  // --- Método Build Adicionado ---
  // (Obrigatório para o Widget funcionar como uma tela)
  @override
  Widget build(BuildContext context) {
    // Você precisa adicionar sua UI (Widgets) aqui
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurações'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Exemplo de como usar os controllers
            TextField(
              controller: _ipController,
              decoration: InputDecoration(labelText: 'IP do Servidor'),
            ),
            TextField(
              controller: _portController,
              decoration: InputDecoration(labelText: 'Porta'),
            ),
            SizedBox(height: 20),
            _isTesting
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _testConnection,
                    child: Text('Testar Conexão'),
                  ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _autoDetectServer,
              child: Text('Auto-Detectar Servidor'),
            ),
            SizedBox(height: 20),
            if (_testResult != null) Text(_testResult!),
          ],
        ),
      ),
    );
  }
}