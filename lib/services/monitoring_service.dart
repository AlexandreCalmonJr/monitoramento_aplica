// Ficheiro: lib/services/monitoring_service.dart
// DESCRIÇÃO: Detecção melhorada de impressoras Zebra e Bematech com múltiplos métodos

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
        
        debugPrint("--- LISTA DE PROGRAMAS ENCONTRADOS (${programs.length}) ---");
        for (var program in programs) {
          debugPrint("- $program");
        }
        debugPrint("--- FIM DA LISTA DE PROGRAMAS ---");

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
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Output "=== INICIANDO DETECÇÃO DE DISPOSITIVOS ==="
$zebraStatus = "Não detectado"
$bematechStatus = "Não detectado"
$biometricStatus = "Não detectado"

function Get-PrinterStatusString($status) {
    switch ($status) {
        0 { return "Parado" }
        1 { return "Outro" }
        2 { return "Desconhecido" }
        3 { return "Online" }
        4 { return "Imprimindo" }
        5 { return "Aquecendo" }
        6 { return "Parado" }
        7 { return "Offline" }
        default { return "Status $status" }
    }
}

# ========== MÉTODO 1: Get-Printer (Windows 10+) ==========
Write-Output "[INFO] Tentando método Get-Printer..."
try {
    $allPrinters = Get-Printer -ErrorAction Stop
    Write-Output "[INFO] Total de impressoras encontradas: $($allPrinters.Count)"
    
    foreach ($printer in $allPrinters) {
        Write-Output "[INFO] Impressora: $($printer.Name) | Status: $($printer.PrinterStatus)"
        
        if ($printer.Name -match "Zebra|ZDesigner|ZD") {
            $zebraStatus = "Conectado - $($printer.PrinterStatus)"
            Write-Output "[SUCESSO] Zebra detectada via Get-Printer: $($printer.Name)"
        }
        
        if ($printer.Name -match "Bematech|MP-4200|MP4200") {
            $bematechStatus = "Conectado - $($printer.PrinterStatus)"
            Write-Output "[SUCESSO] Bematech detectada via Get-Printer: $($printer.Name)"
        }
    }
} catch {
    Write-Output "[ERRO] Falha no Get-Printer: $_"
}

# ========== MÉTODO 2: WMI Win32_Printer ==========
Write-Output "[INFO] Tentando método WMI Win32_Printer..."
try {
    $wmiPrinters = Get-WmiObject -Class Win32_Printer -ErrorAction Stop
    Write-Output "[INFO] WMI retornou $($wmiPrinters.Count) impressoras"
    
    foreach ($printer in $wmiPrinters) {
        Write-Output "[INFO] WMI Impressora: $($printer.Name) | Status: $($printer.PrinterStatus)"
        
        if ($printer.Name -match "Zebra|ZDesigner|ZD" -and $zebraStatus -eq "Não detectado") {
            $statusStr = Get-PrinterStatusString -status $printer.PrinterStatus
            $zebraStatus = "Conectado - $statusStr"
            Write-Output "[SUCESSO] Zebra detectada via WMI: $($printer.Name)"
        }
        
        if ($printer.Name -match "Bematech|MP-4200|MP4200" -and $bematechStatus -eq "Não detectado") {
            $statusStr = Get-PrinterStatusString -status $printer.PrinterStatus
            $bematechStatus = "Conectado - $statusStr"
            Write-Output "[SUCESSO] Bematech detectada via WMI: $($printer.Name)"
        }
    }
} catch {
    Write-Output "[ERRO] Falha no WMI: $_"
}

# ========== MÉTODO 3: Dispositivos USB (PnP) ==========
Write-Output "[INFO] Verificando dispositivos USB..."
try {
    $usbDevices = Get-PnpDevice -Class "Printer","USB" -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne "Unknown" }
    
    foreach ($device in $usbDevices) {
        Write-Output "[INFO] Dispositivo USB: $($device.FriendlyName) | Status: $($device.Status)"
        
        if ($device.FriendlyName -match "Zebra|ZDesigner|ZD" -and $zebraStatus -eq "Não detectado") {
            $zebraStatus = if ($device.Status -eq "OK") { "Conectado - USB" } else { "Detectado - USB ($($device.Status))" }
            Write-Output "[SUCESSO] Zebra detectada via USB: $($device.FriendlyName)"
        }
        
        if ($device.FriendlyName -match "Bematech|MP-4200|MP4200" -and $bematechStatus -eq "Não detectado") {
            $bematechStatus = if ($device.Status -eq "OK") { "Conectado - USB" } else { "Detectado - USB ($($device.Status))" }
            Write-Output "[SUCESSO] Bematech detectada via USB: $($device.FriendlyName)"
        }
    }
} catch {
    Write-Output "[ERRO] Falha ao verificar USB: $_"
}

# ========== MÉTODO 4: Registro do Windows ==========
Write-Output "[INFO] Verificando registro do Windows..."
try {
    $regPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\*",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers\*"
    )
    
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $printers = Get-ItemProperty $path -ErrorAction SilentlyContinue
            foreach ($printer in $printers) {
                $printerName = $printer.PSChildName
                if ($printerName) {
                    Write-Output "[INFO] Registro: $printerName"
                    
                    if ($printerName -match "Zebra|ZDesigner|ZD" -and $zebraStatus -eq "Não detectado") {
                        $zebraStatus = "Detectado - Registro"
                        Write-Output "[SUCESSO] Zebra no registro: $printerName"
                    }
                    
                    if ($printerName -match "Bematech|MP-4200|MP4200" -and $bematechStatus -eq "Não detectado") {
                        $bematechStatus = "Detectado - Registro"
                        Write-Output "[SUCESSO] Bematech no registro: $printerName"
                    }
                }
            }
        }
    }
} catch {
    Write-Output "[ERRO] Falha ao verificar registro: $_"
}

# ========== LEITOR BIOMÉTRICO ==========
Write-Output "[INFO] Procurando leitor biométrico..."
try {
    $biometricDevice = Get-PnpDevice -Class "Biometric" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($biometricDevice) {
        Write-Output "[INFO] Leitor encontrado por classe: $($biometricDevice.FriendlyName) | Status: $($biometricDevice.Status)"
        $biometricStatus = if ($biometricDevice.Status -eq "OK") { "Conectado" } else { "Detectado - $($biometricDevice.Status)" }
    } else {
        Write-Output "[INFO] Buscando por nome específico..."
        $biometricDeviceByName = Get-PnpDevice | Where-Object { $_.FriendlyName -match "U are U|Digital Persona|Fingerprint|Biometric" } | Select-Object -First 1
        if ($biometricDeviceByName) {
            Write-Output "[INFO] Leitor encontrado: $($biometricDeviceByName.FriendlyName) | Status: $($biometricDeviceByName.Status)"
            $biometricStatus = if ($biometricDeviceByName.Status -eq "OK") { "Conectado" } else { "Detectado - $($biometricDeviceByName.Status)" }
        } else {
            Write-Output "[INFO] Leitor biométrico não encontrado"
        }
    }
} catch {
    Write-Output "[ERRO] Falha ao procurar leitor biométrico: $_"
}

Write-Output "=== RESULTADOS FINAIS ==="
Write-Output "RESULT_ZEBRA:$zebraStatus"
Write-Output "RESULT_BEMATECH:$bematechStatus"
Write-Output "RESULT_BIOMETRIC:$biometricStatus"
''';

    final tempDir = Directory.systemTemp;
    final scriptFile = File('${tempDir.path}\\monitor_device_detection.ps1');
    
    try {
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);

      debugPrint("=== EXECUTANDO SCRIPT DE DETECÇÃO ===");
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );
      
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      debugPrint("=== SAÍDA DO SCRIPT ===");
      debugPrint(stdoutString);
      if (stderrString.isNotEmpty) {
        debugPrint("=== ERROS DO SCRIPT ===");
        debugPrint(stderrString);
      }

      Map<String, String> statuses = {
        'zebra': 'Não detectado',
        'bematech': 'Não detectado',
        'biometric': 'Não detectado'
      };
      
      final lines = stdoutString.split('\n');
      for (String line in lines) {
        final trimmedLine = line.trim();
        
        if (trimmedLine.startsWith('RESULT_ZEBRA:')) {
          statuses['zebra'] = trimmedLine.substring('RESULT_ZEBRA:'.length).trim();
          debugPrint(">>> Zebra Status: ${statuses['zebra']}");
        } else if (trimmedLine.startsWith('RESULT_BEMATECH:')) {
          statuses['bematech'] = trimmedLine.substring('RESULT_BEMATECH:'.length).trim();
          debugPrint(">>> Bematech Status: ${statuses['bematech']}");
        } else if (trimmedLine.startsWith('RESULT_BIOMETRIC:')) {
          statuses['biometric'] = trimmedLine.substring('RESULT_BIOMETRIC:'.length).trim();
          debugPrint(">>> Biometric Status: ${statuses['biometric']}");
        }
      }
      
      debugPrint("=== STATUS FINAL ===");
      debugPrint("Zebra: ${statuses['zebra']}");
      debugPrint("Bematech: ${statuses['bematech']}");
      debugPrint("Biométrico: ${statuses['biometric']}");
      
      return statuses;
    } catch (e) {
      debugPrint("=== EXCEÇÃO FATAL ===");
      debugPrint("Erro: $e");
      return {
        'zebra': 'Erro ao detectar',
        'bematech': 'Erro ao detectar',
        'biometric': 'Erro ao detectar'
      };
    } finally {
      try {
        if (await scriptFile.exists()) {
          await scriptFile.delete();
        }
      } catch (e) {
        debugPrint("Erro ao deletar arquivo temporário: $e");
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
    debugPrint('=== INICIANDO COLETA DE DADOS ===');
    debugPrint('Servidor: $serverUrl');

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
      String biometricStatus = deviceStatuses['biometric'] ?? 'Não detectado';
      String zebraStatus = deviceStatuses['zebra'] ?? 'Não detectado';
      String bematechStatus = deviceStatuses['bematech'] ?? 'Não detectado';
      
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

      debugPrint('=== DADOS A ENVIAR ===');
      debugPrint('Hostname: $hostname');
      debugPrint('Serial: $serialNumber');
      debugPrint('Modelo: $model');
      debugPrint('Zebra: $zebraStatus');
      debugPrint('Bematech: $bematechStatus');
      debugPrint('Biométrico: $biometricStatus');
      debugPrint('Tipo Totem: $totemType');

      statusNotifier.value = 'A enviar dados...';
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(systemData),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        statusNotifier.value = 'Ativo';
        lastUpdateNotifier.value = 'Último envio: ${DateTime.now().toLocal().toString().substring(0, 19)}';
        errorNotifier.value = '';
        debugPrint('=== DADOS ENVIADOS COM SUCESSO ===');
      } else {
        debugPrint('=== ERRO HTTP ===');
        debugPrint('Status: ${response.statusCode}');
        debugPrint('Resposta: ${response.body}');
        throw Exception('Falha ao enviar dados. Status: ${response.statusCode}');
      }
    } catch (e) {
      statusNotifier.value = 'Erro';
      errorNotifier.value = e.toString().replaceAll('Exception: ', '');
      debugPrint('=== EXCEÇÃO CAPTURADA ===');
      debugPrint('Erro: $e');
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
    debugPrint('=== SERVIÇO INICIADO ===');
    debugPrint('URL: $url');
    debugPrint('Intervalo: ${intervalInSeconds}s');
    debugPrint('Tipo Totem: $newTotemType');
    
    collectAndSendData(url);
    _timer = Timer.periodic(Duration(seconds: intervalInSeconds), (timer) {
      collectAndSendData(url);
    });
    statusNotifier.value = 'Ativo';
  }

  void stop() {
    _timer?.cancel();
    statusNotifier.value = 'Inativo';
    debugPrint('=== SERVIÇO PARADO ===');
  }

  void dispose() {
    stop();
    statusNotifier.dispose();
    lastUpdateNotifier.dispose();
    errorNotifier.dispose();
  }
}