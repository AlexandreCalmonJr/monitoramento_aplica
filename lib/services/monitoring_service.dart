// Ficheiro: lib/services/monitoring_service.dart
// DESCRIÇÃO: Modificado para que o tipo de totem seja definido pelo usuário ao iniciar o serviço,
// utilizando a variável newTotemType.

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

  // Propriedade para armazenar o tipo de totem definido pelo usuário
  String _newTotemType = 'N/A';

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
    // A implementação de _getInstalledPrograms permanece a mesma...
    debugPrint("--- INICIANDO COLETA DE PROGRAMAS ---");
    
    // Usando o método mais confiável e rápido (Registry) como principal.
    try {
      const command = 'powershell';
      const script = r'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -ne $null } | Select-Object DisplayName, DisplayVersion | ForEach-Object { "$($_.DisplayName) version $($_.DisplayVersion)" } | Sort-Object -Unique';
      
      debugPrint("Tentativa principal: Usando Get-ItemProperty (Registry)");
      final result = await Process.run(command, ['-command', script], runInShell: true);
      
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        debugPrint("Método principal bem-sucedido");
        return result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty).toList();
      }
      debugPrint("Método principal falhou: código ${result.exitCode}, erro: ${result.stderr}");
    } catch (e) {
      debugPrint("Método principal gerou exceção: $e");
    }
    
    debugPrint("Não foi possível listar programas, retornando mensagem de erro");
    return ["Não foi possível listar programas instalados"];
  }

  Future<String> _getZebraStatus() async {
    // A implementação de _getZebraStatus permanece a mesma...
    try {
      const command = 'powershell';
      const script = r'''
$devices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*Zebra*" -or $_.DriverName -like "*Zebra*" }
if ($devices) {
    if ($devices | Where-Object { $_.PrinterStatus -eq 3 }) { "Online" }
    elseif ($devices | Where-Object { $_.PrinterStatus -eq 5 }) { "Erro" }
    else { "Offline" }
} else { "N/A" }
''';
      
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao verificar impressora Zebra: $e");
      return "N/A";
    }
  }

  Future<String> _getBematechStatus() async {
    // A implementação de _getBematechStatus permanece a mesma...
    try {
      const command = 'powershell';
      const script = r'''
$devices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*Bematech*" -or $_.DriverName -like "*Bematech*" }
if ($devices) {
    if ($devices | Where-Object { $_.PrinterStatus -eq 3 }) { "Online" }
    elseif ($devices | Where-Object { $_.PrinterStatus -eq 5 }) { "Erro" }
    else { "Offline" }
} else { "N/A" }
''';
      
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao verificar impressora Bematech: $e");
      return "N/A";
    }
  }

  Future<String> _getBiometricReaderStatus() async {
    // A implementação de _getBiometricReaderStatus permanece a mesma...
    try {
      const command = 'powershell';
      const script = r'''
$biometricDevice = Get-PnpDevice -Class "Biometric" -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "OK" }
$bioService = Get-Service -Name "WbioSrvc" -ErrorAction SilentlyContinue
if ($biometricDevice -or ($bioService -and $bioService.Status -eq "Running")) {
    "Conectado"
} else {
    "N/A"
}
''';
      
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim() == "Conectado") {
        return "Conectado";
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao verificar leitor biométrico: $e");
      return "N/A";
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
      
      // Coletas de dados específicas
      String biometricStatus = await _getBiometricReaderStatus();
      String zebraStatus = await _getZebraStatus();
      String bematechStatus = await _getBematechStatus();
      
      // **ALTERAÇÃO AQUI**: Usa o valor armazenado na propriedade da classe
      String totemType = _newTotemType;

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
        'zebraStatus': zebraStatus,
        'bematechStatus': bematechStatus,
        // **ALTERAÇÃO AQUI**: Envia o tipo de totem correto
        'totemType': totemType,
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
        debugPrint('Status dos dispositivos:');
        debugPrint('- Zebra: $zebraStatus');
        debugPrint('- Bematech: $bematechStatus');
        debugPrint('- Biométrico: $biometricStatus');
        debugPrint('- Tipo de Totem: $totemType');
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

  // **MÉTODO START MODIFICADO**
  void start(String serverAddress, int intervalInSeconds, String newTotemType) {
    stop();
    if (serverAddress.isEmpty) {
      statusNotifier.value = 'Inativo (Configure o servidor)';
      return;
    }
    
    // Armazena o tipo de totem informado
    _newTotemType = newTotemType;
    
    final url = 'http://$serverAddress/api/monitor';
    collectAndSendData(url);
    _timer = Timer.periodic(Duration(seconds: intervalInSeconds), (timer) {
      collectAndSendData(url);
    });
    statusNotifier.value = 'Ativo';
  }

  void stop() {
    _timer?.cancel();
    statusNotifier.value = 'Inativo';
  }
  
  // A função _getTotemType() foi completamente removida.
}