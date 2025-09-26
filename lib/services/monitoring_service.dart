// Ficheiro: lib/services/monitoring_service.dart
// DESCRIÇÃO: Corrigido definitivamente o erro 'EmptyPipeElement' usando múltiplas abordagens alternativas.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MonitoringService {
  Timer? _timer;
  final ValueNotifier<String> statusNotifier = ValueNotifier('Inativo');
  final ValueNotifier<String> lastUpdateNotifier = ValueNotifier('Nenhuma');
  final ValueNotifier<String> errorNotifier = ValueNotifier('');

  Future<String> _runCommand(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args, runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      } else {
        return "Erro ao executar comando: ${result.stderr}";
      }
    } catch (e) {
      return "Exceção no comando: $e";
    }
  }
  
  Future<List<String>> _getInstalledPrograms() async {
    debugPrint("--- INICIANDO COLETA DE PROGRAMAS ---");
    
    // Método 1: Comando PowerShell simplificado
    try {
      const command = 'powershell';
      const script = r'Get-WmiObject -Class Win32_Product | Select-Object Name, Version | ForEach-Object { "$($_.Name) version $($_.Version)" }';
      
      debugPrint("Tentativa 1: Usando Win32_Product");
      final result = await Process.run(command, ['-command', script], runInShell: true);
      
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        debugPrint("Método 1 bem-sucedido");
        return result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty).toList();
      }
      debugPrint("Método 1 falhou: código ${result.exitCode}, erro: ${result.stderr}");
    } catch (e) {
      debugPrint("Método 1 gerou exceção: $e");
    }
    
    // Método 2: Comando Registry direto sem pipeline complexo
    try {
      const command = 'powershell';
      const script = r'''
$uninstall32 = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
$uninstall64 = Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
$programs = @()
foreach ($item in $uninstall32) { if ($item.DisplayName) { $programs += "$($item.DisplayName) version $($item.DisplayVersion)" } }
foreach ($item in $uninstall64) { if ($item.DisplayName) { $programs += "$($item.DisplayName) version $($item.DisplayVersion)" } }
$programs | Sort-Object -Unique
''';
      
      debugPrint("Tentativa 2: Usando foreach loops");
      final result = await Process.run(command, ['-command', script], runInShell: true);
      
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        debugPrint("Método 2 bem-sucedido");
        return result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty).toList();
      }
      debugPrint("Método 2 falhou: código ${result.exitCode}, erro: ${result.stderr}");
    } catch (e) {
      debugPrint("Método 2 gerou exceção: $e");
    }
    
    // Método 3: Comando CMD usando reg query
    try {
      debugPrint("Tentativa 3: Usando comando reg query");
      final result1 = await Process.run('cmd', ['/c', 'reg query "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall" /s /v DisplayName'], runInShell: true);
      final result2 = await Process.run('cmd', ['/c', 'reg query "HKLM\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall" /s /v DisplayName'], runInShell: true);
      
      List<String> programs = [];
      
      if (result1.exitCode == 0) {
        final lines = result1.stdout.toString().split('\n');
        for (String line in lines) {
          if (line.contains('DisplayName') && line.contains('REG_SZ')) {
            final parts = line.split('REG_SZ');
            if (parts.length > 1) {
              final programName = parts[1].trim();
              if (programName.isNotEmpty) {
                programs.add(programName);
              }
            }
          }
        }
      }
      
      if (result2.exitCode == 0) {
        final lines = result2.stdout.toString().split('\n');
        for (String line in lines) {
          if (line.contains('DisplayName') && line.contains('REG_SZ')) {
            final parts = line.split('REG_SZ');
            if (parts.length > 1) {
              final programName = parts[1].trim();
              if (programName.isNotEmpty && !programs.contains(programName)) {
                programs.add(programName);
              }
            }
          }
        }
      }
      
      if (programs.isNotEmpty) {
        debugPrint("Método 3 bem-sucedido - encontrados ${programs.length} programas");
        return programs;
      }
      debugPrint("Método 3 não encontrou programas");
    } catch (e) {
      debugPrint("Método 3 gerou exceção: $e");
    }
    
    // Método 4: PowerShell mais simples ainda
    try {
      const command = 'powershell';
      const script = r'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where DisplayName | Select DisplayName | Format-Table -HideTableHeaders';
      
      debugPrint("Tentativa 4: PowerShell simplificado");
      final result = await Process.run(command, ['-command', script], runInShell: true);
      
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        debugPrint("Método 4 bem-sucedido");
        final programs = result.stdout.toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('-'))
            .toList();
        return programs;
      }
      debugPrint("Método 4 falhou: código ${result.exitCode}, erro: ${result.stderr}");
    } catch (e) {
      debugPrint("Método 4 gerou exceção: $e");
    }
    
    // Se todos os métodos falharam, retorna uma mensagem informativa
    debugPrint("Todos os métodos falharam, retornando lista com mensagem de erro");
    return ["Não foi possível listar programas instalados"];
  }

  Future<String> _getBiometricReaderStatus() async {
    const command = 'powershell';
    const args = [
      '-command',
      r"if ((Get-PnpDevice -Class 'Biometric' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })) { 'Conectado' } else { 'N/A' }"
    ];
    
    try {
      final result = await Process.run(command, args, runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      } else {
        return 'N/A';
      }
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> collectAndSendData(String serverUrl) async {
    if (serverUrl.isEmpty) {
      errorNotifier.value = 'URL do servidor não configurada.';
      return;
    }

    statusNotifier.value = 'A recolher dados...';
    errorNotifier.value = '';
    debugPrint('A tentar enviar dados para: $serverUrl');

    try {
      String hostname = await _runCommand('hostname', []);
      String serialNumberRaw = await _runCommand('wmic', ['bios', 'get', 'serialnumber']);
      String modelRaw = await _runCommand('wmic', ['computersystem', 'get', 'model']);
      List<String> installedPrograms = await _getInstalledPrograms();
      String printersRaw = await _runCommand('wmic', ['printer', 'get', 'name,status']);
      String biometricStatus = await _getBiometricReaderStatus();

      final serialNumber = serialNumberRaw.split('\n').last.trim();
      final model = modelRaw.split('\n').last.trim();

      if (serialNumber.isEmpty || serialNumber.toLowerCase().contains('error')) {
        throw Exception('Não foi possível obter o número de série.');
      }

      Map<String, dynamic> systemData = {
        'hostname': hostname,
        'serialNumber': serialNumber,
        'model': model,
        'serviceTag': serialNumber,
        'installedPrograms': installedPrograms,
        'printerStatus': printersRaw,
        'biometricReaderStatus': biometricStatus,
      };

      statusNotifier.value = 'A enviar dados...';
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(systemData),
      );

      if (response.statusCode == 200) {
        statusNotifier.value = 'Ativo';
        lastUpdateNotifier.value = 'Último envio: ${DateTime.now().toLocal().toString().substring(0, 19)}';
        errorNotifier.value = '';
        debugPrint('Dados enviados com sucesso.');
        debugPrint('Programas coletados: ${installedPrograms.length} itens');
      } else {
        debugPrint('Erro HTTP: ${response.statusCode}, Corpo: ${response.body}');
        throw Exception('Falha ao enviar dados. Status: ${response.statusCode}');
      }
    } catch (e) {
      statusNotifier.value = 'Erro';
      errorNotifier.value = e.toString().replaceAll('Exception: ', '');
      debugPrint('Exceção capturada em collectAndSendData: $e');
    }
  }

  void start(String serverAddress, int intervalInSeconds) {
    stop();
    if (serverAddress.isEmpty) {
      statusNotifier.value = 'Inativo (Configure o servidor)';
      return;
    }
    
    final url = 'http://$serverAddress/api/monitor';
    collectAndSendData(url);
    _timer = Timer.periodic(const Duration(seconds: 60), (timer) {
      collectAndSendData(url);
    });
    statusNotifier.value = 'Ativo';
  }

  void stop() {
    _timer?.cancel();
    statusNotifier.value = 'Inativo';
  }
}