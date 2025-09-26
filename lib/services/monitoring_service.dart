// Ficheiro: lib/services/monitoring_service.dart
// DESCRIÇÃO: Código melhorado com detecção mais robusta de dispositivos

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
  
  Future<String> _getRamInfo() async {
    try {
      const command = 'powershell';
      const script = r'Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory | ForEach-Object { "$([math]::Round($_ / 1GB)) GB" }';
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao obter informações de RAM: $e");
      return "N/A";
    }
  }

  Future<String> _getHdType() async {
    try {
      const command = 'powershell';
      const script = r'(Get-PhysicalDisk | Select-Object -First 1).MediaType';
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao obter o tipo de HD: $e");
      return "N/A";
    }
  }

  Future<String> _getHdStorageInfo() async {
    try {
      const command = 'powershell';
      const script = r'Get-Volume -DriveLetter C | ForEach-Object { "Total: " + [math]::Round($_.Size / 1GB) + " GB, Livre: " + [math]::Round($_.SizeRemaining / 1GB) + " GB" }';
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao obter informações de armazenamento do HD: $e");
      return "N/A";
    }
  }

  Future<List<String>> _getInstalledPrograms() async {
    debugPrint("--- INICIANDO COLETA DE PROGRAMAS ---");
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

  // --- MÉTODOS DE DETECÇÃO MELHORADOS ---

  Future<String> _getZebraStatus() async {
    try {
      const command = 'powershell';
      const script = r'''
$devices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*ZDesigner GC420t (EPL)*" }
if ($devices) {
    $device = $devices | Select-Object -First 1
    switch ($device.PrinterStatus) {
        1 { "Outro" }
        2 { "Desconhecido" }
        3 { "Online" }
        4 { "Offline" }
        5 { "Erro" }
        6 { "Teste" }
        7 { "Energia Baixa" }
        default { "Status: $($device.PrinterStatus)" }
    }
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
    try {
      const command = 'powershell';
      const script = r'''
$devices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*MP-4200 TH*" }
if ($devices) {
    $device = $devices | Select-Object -First 1
    switch ($device.PrinterStatus) {
        1 { "Outro" }
        2 { "Desconhecido" }
        3 { "Online" }
        4 { "Offline" }
        5 { "Erro" }
        6 { "Teste" }
        7 { "Energia Baixa" }
        default { "Status: $($device.PrinterStatus)" }
    }
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
    try {
      const command = 'powershell';
      const script = r'''
$biometricDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*U.are.U® 4500*" }
if ($biometricDevices) {
    $okDevices = $biometricDevices | Where-Object { $_.Status -eq "OK" }
    $unknownDevices = $biometricDevices | Where-Object { $_.Status -eq "Unknown" }
    
    if ($okDevices) {
        "Conectado (OK)"
    } elseif ($unknownDevices) {
        "Conectado (Unknown)"
    } else {
        $status = ($biometricDevices | Select-Object -First 1).Status
        "Conectado ($status)"
    }
} else {
    "N/A"
}
''';
      
      final result = await Process.run(command, ['-command', script], runInShell: true);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return result.stdout.toString().trim();
      }
      return "N/A";
    } catch (e) {
      debugPrint("Erro ao verificar leitor biométrico: $e");
      return "N/A";
    }
  }

  // Método adicional para verificar todos os dispositivos de uma só vez
  Future<Map<String, String>> _getAllDeviceStatus() async {
    try {
      const command = 'powershell';
      const script = r'''
# Verificar impressoras
$zebraStatus = "N/A"
$bematechStatus = "N/A"
$biometricStatus = "N/A"

# Zebra
$zebraDevices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*ZDesigner GC420t (EPL)*" }
if ($zebraDevices) {
    $device = $zebraDevices | Select-Object -First 1
    switch ($device.PrinterStatus) {
        3 { $zebraStatus = "Online" }
        4 { $zebraStatus = "Offline" }
        5 { $zebraStatus = "Erro" }
        default { $zebraStatus = "Status: $($device.PrinterStatus)" }
    }
}

# Bematech
$bematechDevices = Get-WmiObject -Class Win32_Printer | Where-Object { $_.Name -like "*MP-4200 TH*" }
if ($bematechDevices) {
    $device = $bematechDevices | Select-Object -First 1
    switch ($device.PrinterStatus) {
        3 { $bematechStatus = "Online" }
        4 { $bematechStatus = "Offline" }
        5 { $bematechStatus = "Erro" }
        default { $bematechStatus = "Status: $($device.PrinterStatus)" }
    }
}

# Biométrico
$biometricDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*U.are.U® 4500*" }
if ($biometricDevices) {
    $okDevices = $biometricDevices | Where-Object { $_.Status -eq "OK" }
    if ($okDevices) {
        $biometricStatus = "Conectado"
    } else {
        $biometricStatus = "Detectado (verificar status)"
    }
}

Write-Output "ZEBRA:$zebraStatus"
Write-Output "BEMATECH:$bematechStatus"
Write-Output "BIOMETRIC:$biometricStatus"
''';
      
      final result = await Process.run(command, ['-command', script], runInShell: true);
      
      Map<String, String> statuses = {
        'zebra': 'N/A',
        'bematech': 'N/A',
        'biometric': 'N/A',
      };
      
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        for (String line in lines) {
          if (line.startsWith('ZEBRA:')) {
            statuses['zebra'] = line.substring(6);
          } else if (line.startsWith('BEMATECH:')) {
            statuses['bematech'] = line.substring(9);
          } else if (line.startsWith('BIOMETRIC:')) {
            statuses['biometric'] = line.substring(10);
          }
        }
      }
      
      return statuses;
    } catch (e) {
      debugPrint("Erro ao verificar status de todos os dispositivos: $e");
      return {
        'zebra': 'N/A',
        'bematech': 'N/A', 
        'biometric': 'N/A',
      };
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
      
      String ramInfo = await _getRamInfo();
      String hdType = await _getHdType();
      String hdStorageInfo = await _getHdStorageInfo();

      // Usando o método otimizado para obter status de todos os dispositivos
      Map<String, String> deviceStatuses = await _getAllDeviceStatus();
      String biometricStatus = deviceStatuses['biometric'] ?? 'N/A';
      String zebraStatus = deviceStatuses['zebra'] ?? 'N/A';
      String bematechStatus = deviceStatuses['bematech'] ?? 'N/A';
      
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
        'ram': ramInfo,
        'hdType': hdType,
        'hdStorage': hdStorageInfo,
        'installedPrograms': installedPrograms,
        'printerStatus': printersRaw,
        'biometricReaderStatus': biometricStatus,
        'zebraStatus': zebraStatus,
        'bematechStatus': bematechStatus,
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
        debugPrint('- RAM: $ramInfo');
        debugPrint('- Tipo de HD: $hdType');
        debugPrint('- Armazenamento: $hdStorageInfo');
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

  void start(String serverAddress, int intervalInSeconds, String newTotemType) {
    stop();
    if (serverAddress.isEmpty) {
      statusNotifier.value = 'Inativo (Configure o servidor)';
      return;
    }
    
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
}