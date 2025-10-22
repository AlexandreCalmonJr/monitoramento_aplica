// File: lib/services/monitoring_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MonitoringService {
  
  String _decodeOutput(dynamic output) {
    if (output is List<int>) {
      return latin1.decode(output, allowInvalid: true);
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
        debugPrint("Erro no comando '$command ${args.join(' ')}': $stderrString");
        return "";
      }
    } catch (e) {
      debugPrint("Exceção no comando '$command ${args.join(' ')}': $e");
      return "";
    }
  }
  
  // --- Funções de Coleta de Dados ---
  // (Nenhuma alteração de _getHostname até _getAllDeviceStatus)

  Future<String> _getHostname() => _runCommand('hostname', []);

  Future<String> _getSerialNumber() async {
    final result = await _runCommand('wmic', ['bios', 'get', 'serialnumber']);
    return result.split('\n').last.trim();
  }

  Future<String> _getModel() async {
    final result = await _runCommand('wmic', ['computersystem', 'get', 'model']);
    return result.split('\n').last.trim();
  }

  Future<String> _getManufacturer() async {
    final result = await _runCommand('wmic', ['computersystem', 'get', 'manufacturer']);
    return result.split('\n').last.trim();
  }

  Future<String> _getProcessor() async {
    final result = await _runCommand('wmic', ['cpu', 'get', 'name']);
    return result.split('\n').last.trim();
  }

  Future<String> _getRam() async {
    final result = await _runCommand('powershell', [
      '-command',
      r'Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory | ForEach-Object { "$([math]::Round($_ / 1GB)) GB" }'
    ]);
    return result.isNotEmpty ? result : "N/A";
  }

  Future<String> _getStorage() async {
    final result = await _runCommand('powershell', [
      '-command',
      r'Get-Volume -DriveLetter C | ForEach-Object { "Total: " + [math]::Round($_.Size / 1GB) + " GB" }'
    ]);
    return result.isNotEmpty ? result : "N/A";
  }

  Future<Map<String, String>> _getNetworkInfo() async {
    final result = await _runCommand('powershell', [
      '-command',
      r'Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias (Get-NetConnectionProfile).InterfaceAlias | Select-Object -First 1 | ForEach-Object { $_.IPAddress + ";" + (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).MacAddress }'
    ]);
    if (result.contains(';')) {
      final parts = result.split(';');
      return {'ipAddress': parts[0], 'macAddress': parts[1]};
    }
    return {'ipAddress': 'N/A', 'macAddress': 'N/A'};
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
    
    debugPrint("Não foi possível listar programas, retornando lista vazia");
    return [];
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

  // --- Método Principal de Coleta e Envio ---

  Future<void> collectAndSendData({
    required String moduleId,
    required String serverUrl,
    required String? token, // <-- ADICIONADO
    String? manualSector,
    String? manualFloor,
  }) async {
    // MODIFICADO: Adiciona verificação de token
    if (serverUrl.isEmpty || moduleId.isEmpty || token == null || token.isEmpty) {
      debugPrint('Servidor, Módulo ou Token não configurado. Abortando envio.');
      return;
    }

    debugPrint('Coletando dados para o módulo $moduleId...');

    try {
      // Coleta os dados base
      final serialNumber = await _getSerialNumber();
      if (serialNumber.isEmpty || serialNumber.toLowerCase().contains('error')) {
        throw Exception('Não foi possível obter o número de série. Verifique as permissões.');
      }

      final networkInfo = await _getNetworkInfo();

      // Monta o payload base
      Map<String, dynamic> payload = {
        'asset_name': await _getHostname(),
        'serial_number': serialNumber,
        'ip_address': networkInfo['ipAddress'],
        'mac_address': networkInfo['macAddress'],
        'location': '', // Deixamos o backend mapear, mas enviamos setor/andar
        'assigned_to': await _runCommand('whoami', []),
        'custom_data': {
          'sector': manualSector,
          'floor': manualFloor,
        }
      };
      
      // Adiciona dados específicos do Desktop/Notebook
      // MODIFICADO: Corresponde ao endpoint POST /api/modules/:moduleId/assets
      payload.addAll({
        'hostname': payload['asset_name'],
        'model': await _getModel(),
        'manufacturer': await _getManufacturer(),
        'processor': await _getProcessor(),
        'ram': await _getRam(),
        'storage': await _getStorage(),
        'operating_system': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
      });

      debugPrint('Enviando dados para $serverUrl/api/modules/$moduleId/assets');

      // MODIFICADO: Adiciona cabeçalho (Header) de autenticação
      final response = await http.post(
        Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
        headers: {
          'Content-Type': 'application/json',
          'AUTH_TOKEN': token, // <-- ALTERADO PARA AUTH_TOKEN
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Dados enviados com sucesso! Resposta: ${response.body}');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('Falha ao enviar dados. Token inválido ou expirado.');
        throw Exception('Erro do servidor: Token inválido (${response.statusCode})');
      } else {
        debugPrint('Falha ao enviar dados. Status: ${response.statusCode}, Corpo: ${response.body}');
        throw Exception('Erro do servidor: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ERRO no ciclo de monitoramento: $e');
    }
  }
}

