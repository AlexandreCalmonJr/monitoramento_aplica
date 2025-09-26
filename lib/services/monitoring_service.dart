// Ficheiro: lib/services/monitoring_service.dart
// DESCRIÇÃO: Adicionado log detalhado da lista de programas instalados para depuração.

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

  String _newTotemType = 'N/A';

  String _decodeOutput(dynamic output) {
    if (output is List<int>) {
      return latin1.decode(output);
    }
    return output.toString();
  }

  Future<String> _runCommand(String command, List<String> args) async {
    try {
      final result = await Process.run(command, args, runInShell: true);
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0) {
        return stdoutString.trim();
      } else {
        debugPrint("Erro ao executar comando: '$command ${args.join(' ')}'. Stderr: $stderrString");
        return "Erro ao executar comando: $stderrString";
      }
    } catch (e) {
      debugPrint("Exceção no comando: '$command ${args.join(' ')}'. Erro: $e");
      return "Exceção no comando: $e";
    }
  }
  
  Future<String> _getRamInfo() async {
    try {
      const command = 'powershell';
      const script = r'Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory | ForEach-Object { "$([math]::Round($_ / 1GB)) GB" }';
      final result = await _runCommand(command, ['-command', script]);
      return result.isNotEmpty ? result : "N/A";
    } catch (e) {
      debugPrint("Erro ao obter informações de RAM: $e");
      return "N/A";
    }
  }

  Future<String> _getHdType() async {
    try {
      const command = 'powershell';
      const script = r'(Get-PhysicalDisk | Select-Object -First 1).MediaType';
      final result = await _runCommand(command, ['-command', script]);
      return result.isNotEmpty ? result : "N/A";
    } catch (e) {
      debugPrint("Erro ao obter o tipo de HD: $e");
      return "N/A";
    }
  }

  Future<String> _getHdStorageInfo() async {
    try {
      const command = 'powershell';
      const script = r'Get-Volume -DriveLetter C | ForEach-Object { "Total: " + [math]::Round($_.Size / 1GB) + " GB, Livre: " + [math]::Round($_.SizeRemaining / 1GB) + " GB" }';
      final result = await _runCommand(command, ['-command', script]);
      return result.isNotEmpty ? result : "N/A";
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
      
      final result = await _runCommand(command, ['-command', script]);
      if (result.isNotEmpty && !result.startsWith("Erro")) {
        debugPrint("Método principal bem-sucedido");
        final programs = result.split('\n').where((s) => s.trim().isNotEmpty).toList();
        
        // --- AJUSTE AQUI ---
        debugPrint("--- LISTA DE PROGRAMAS ENCONTRADOS ---");
        for (var program in programs) {
          debugPrint("- $program");
        }
        debugPrint("--- FIM DA LISTA DE PROGRAMAS ---");
        // --- FIM DO AJUSTE ---

        return programs;
      }
    } catch (e) {
      debugPrint("Método principal gerou exceção: $e");
    }
    
    debugPrint("Não foi possível listar programas, retornando mensagem de erro");
    return ["Não foi possível listar programas instalados"];
  }

  Future<Map<String, String>> _getAllDeviceStatus() async {
    const String scriptContent = r'''
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Output "--- INICIANDO SCRIPT DE DETECÇÃO DE DISPOSITIVOS (V FINAL) ---"
$zebraStatus = "N/A"
$bematechStatus = "N/A"
$biometricStatus = "N/A"

function Get-PrinterStatusString($status) {
    switch ($status) {
        1 { return "Outro" }
        2 { return "Desconhecido" }
        3 { return "Online" }
        4 { return "Imprimindo" }
        5 { return "Aquecendo" }
        6 { return "Parado" }
        7 { return "Offline" }
        default { return "Status: $status" }
    }
}

try {
    Write-Output "---[LOG]--- Buscando impressoras..."
    $printers = Get-WmiObject -Class Win32_Printer -ErrorAction Stop
    if ($printers) {
        $zebraDevice = $printers | Where-Object { $_.Name -like "*ZDesigner*" } | Select-Object -First 1
        if ($zebraDevice) {
            $zebraStatus = Get-PrinterStatusString -status $zebraDevice.PrinterStatus
            Write-Output "---[LOG]--- Zebra encontrada: $($zebraDevice.Name), Status: $zebraStatus"
        } else { Write-Output "---[LOG]--- Nenhuma Zebra encontrada." }
        
        $bematechDevice = $printers | Where-Object { $_.Name -like "*MP-4200*" } | Select-Object -First 1
        if ($bematechDevice) {
            $bematechStatus = Get-PrinterStatusString -status $bematechDevice.PrinterStatus
            Write-Output "---[LOG]--- Bematech encontrada: $($bematechDevice.Name), Status: $bematechStatus"
        } else { Write-Output "---[LOG]--- Nenhuma Bematech encontrada." }
    } else { Write-Output "---[LOG]--- Nenhuma impressora retornada." }
} catch { Write-Output "---[ERRO]--- Falha ao buscar impressoras: $_" }

try {
    Write-Output "---[LOG]--- Buscando leitor biométrico..."
    $biometricDevice = Get-PnpDevice -Class "Biometric" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($biometricDevice) {
        Write-Output "---[LOG]--- Leitor encontrado por classe: $($biometricDevice.FriendlyName), Status: $($biometricDevice.Status)"
        $biometricStatus = if ($biometricDevice.Status -eq "OK") { "Conectado" } else { "Detectado" }
    } else {
        Write-Output "---[LOG]--- Não encontrado por classe. Buscando por nome..."
        $biometricDeviceByName = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*U are U*4500*" } | Select-Object -First 1
        if ($biometricDeviceByName) {
             Write-Output "---[LOG]--- Leitor encontrado por nome: $($biometricDeviceByName.FriendlyName), Status: $($biometricDeviceByName.Status)"
            $biometricStatus = if ($biometricDeviceByName.Status -eq "OK") { "Conectado" } else { "Detectado" }
        } else { Write-Output "---[LOG]--- Leitor não encontrado." }
    }
} catch { Write-Output "---[ERRO]--- Falha ao buscar leitor biométrico: $_" }

Write-Output "---[RESULT]---ZEBRA: $($zebraStatus)"
Write-Output "---[RESULT]---BEMATECH: $($bematechStatus)"
Write-Output "---[RESULT]---BIOMETRIC: $($biometricStatus)"
''';

    final tempDir = Directory.systemTemp;
    final scriptFile = File('${tempDir.path}\\monitor_script.ps1');
    
    try {
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);

      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
        runInShell: true,
      );
      
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      debugPrint("--- SAÍDA DO SCRIPT (DECODIFICADA) ---");
      debugPrint(stdoutString);
      if (stderrString.isNotEmpty) {
        debugPrint("--- ERROS DO SCRIPT (DECODIFICADOS) ---");
        debugPrint(stderrString);
      }
      debugPrint("--- FIM DA SAÍDA DO SCRIPT ---");

      Map<String, String> statuses = {'zebra': 'N/A', 'bematech': 'N/A', 'biometric': 'N/A'};
      
      final lines = stdoutString.trim().split('\n');
      for (String line in lines) {
        if (line.startsWith('---[RESULT]---')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            final keyPart = parts[0];
            final valuePart = parts.sublist(1).join(':').trim();

            if (keyPart.contains('ZEBRA')) {
              statuses['zebra'] = valuePart;
            } else if (keyPart.contains('BEMATECH')) {
              statuses['bematech'] = valuePart;
            } else if (keyPart.contains('BIOMETRIC')) {
              statuses['biometric'] = valuePart;
            }
          }
        }
      }
      return statuses;
    } catch (e) {
      debugPrint("Exceção fatal ao executar o script de dispositivos: $e");
      return {'zebra': 'N/A', 'bematech': 'N/A', 'biometric': 'N/A'};
    } finally {
      if (await scriptFile.exists()) {
        await scriptFile.delete();
      }
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