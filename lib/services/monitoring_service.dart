// File: lib/services/monitoring_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MonitoringService {
  final ModuleStructureService _moduleStructureService = ModuleStructureService();
  final AuthService _authService = AuthService();
  
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
  
  // === COLETA DE DADOS BASE (COMUM A TODOS OS MÓDULOS) ===
  
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

  Future<Map<String, String>> _getStorage() async {
    final result = await _runCommand('powershell', [
      '-command',
      r'''
      $disk = Get-Volume -DriveLetter C
      $totalGB = [math]::Round($disk.Size / 1GB, 2)
      $usedGB = [math]::Round(($disk.Size - $disk.SizeRemaining) / 1GB, 2)
      $type = (Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 }).MediaType
      Write-Output "$totalGB GB;$type"
      '''
    ]);
    
    if (result.contains(';')) {
      final parts = result.split(';');
      return {
        'storage': parts[0],
        'storage_type': parts[1].trim(),
      };
    }
    return {'storage': 'N/A', 'storage_type': 'N/A'};
  }

  Future<Map<String, String>> _getNetworkInfo() async {
    final result = await _runCommand('powershell', [
      '-command',
      r'Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias (Get-NetConnectionProfile).InterfaceAlias | Select-Object -First 1 | ForEach-Object { $_.IPAddress + ";" + (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex).MacAddress }'
    ]);
    if (result.contains(';')) {
      final parts = result.split(';');
      return {'ip_address': parts[0], 'mac_address': parts[1]};
    }
    return {'ip_address': 'N/A', 'mac_address': 'N/A'};
  }

  // === COLETA DE DADOS ESPECÍFICOS POR TIPO ===

  /// Desktop/Notebook: Software instalado
  Future<List<String>> _getInstalledPrograms() async {
    debugPrint("--- INICIANDO COLETA DE PROGRAMAS ---");
    try {
      const command = 'powershell';
      const script = r'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -ne $null } | Select-Object DisplayName, DisplayVersion | ForEach-Object { "$($_.DisplayName) version $($_.DisplayVersion)" } | Sort-Object -Unique';
      
      final result = await _runCommand(command, ['-command', script]);
      if (result.isNotEmpty && !result.startsWith("Erro")) {
        final programs = result.split('\n').where((s) => s.trim().isNotEmpty).toList();
        debugPrint("✅ ${programs.length} programas encontrados");
        return programs;
      }
    } catch (e) {
      debugPrint("❌ Erro ao coletar programas: $e");
    }
    return [];
  }

  /// Desktop: Versão do Java
  Future<String> _getJavaVersion() async {
    try {
      final result = await _runCommand('java', ['-version']);
      final lines = result.split('\n');
      if (lines.isNotEmpty) {
        return lines.first.trim();
      }
    } catch (e) {
      debugPrint("Java não instalado ou não encontrado no PATH");
    }
    return 'N/A';
  }

  /// Desktop: Versão do navegador
  Future<String> _getBrowserVersion() async {
    try {
      final result = await _runCommand('powershell', [
        '-command',
        r'''
        $chrome = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue).'(default)'
        if ($chrome) {
          (Get-Item $chrome).VersionInfo.FileVersion
        }
        '''
      ]);
      return result.isNotEmpty ? "Chrome $result" : 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }

  /// Desktop: Status do antivírus
  Future<Map<String, dynamic>> _getAntivirusStatus() async {
    try {
      final result = await _runCommand('powershell', [
        '-command',
        r'Get-MpComputerStatus | Select-Object AntivirusEnabled, AMProductVersion | ConvertTo-Json'
      ]);
      
      if (result.isNotEmpty) {
        final data = json.decode(result);
        return {
          'antivirus_status': data['AntivirusEnabled'] ?? false,
          'antivirus_version': data['AMProductVersion'] ?? 'N/A',
        };
      }
    } catch (e) {
      debugPrint("Erro ao coletar status do antivírus: $e");
    }
    return {'antivirus_status': false, 'antivirus_version': 'N/A'};
  }

  /// Notebook: Bateria
  Future<Map<String, dynamic>> _getBatteryInfo() async {
    try {
      final result = await _runCommand('powershell', [
        '-command',
        r'''
        $battery = Get-WmiObject Win32_Battery
        if ($battery) {
          $level = $battery.EstimatedChargeRemaining
          $health = if ($battery.BatteryStatus -eq 2) { "Carregando" } else { "OK" }
          Write-Output "$level;$health"
        }
        '''
      ]);
      
      if (result.contains(';')) {
        final parts = result.split(';');
        return {
          'battery_level': int.tryParse(parts[0]),
          'battery_health': parts[1],
        };
      }
    } catch (e) {
      debugPrint("Erro ao coletar informações da bateria: $e");
    }
    return {'battery_level': null, 'battery_health': 'N/A'};
  }

  /// Notebook: Status de criptografia (BitLocker)
  Future<bool> _isEncrypted() async {
    try {
      final result = await _runCommand('powershell', [
        '-command',
        'Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty ProtectionStatus'
      ]);
      return result.toLowerCase().contains('on');
    } catch (e) {
      return false;
    }
  }

  /// Desktop: Periféricos (Biométrico e Impressora)
  Future<Map<String, String>> _getPeripherals() async {
    const String scriptContent = r'''
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$zebraStatus = "Não detectado"
$bematechStatus = "Não detectado"
$biometricStatus = "Não detectado"

# Buscar impressoras
try {
    $allPrinters = Get-Printer -ErrorAction Stop
    foreach ($printer in $allPrinters) {
        if ($printer.Name -match "Zebra|ZDesigner|ZD") {
            $zebraStatus = "Conectado - $($printer.PrinterStatus)"
        }
        if ($printer.Name -match "Bematech|MP-4200|MP4200") {
            $bematechStatus = "Conectado - $($printer.PrinterStatus)"
        }
    }
} catch {}

# Buscar leitor biométrico
try {
    $biometricDevice = Get-PnpDevice -Class "Biometric" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($biometricDevice) {
        $biometricStatus = if ($biometricDevice.Status -eq "OK") { "Conectado" } else { "Detectado - $($biometricDevice.Status)" }
    }
} catch {}

Write-Output "ZEBRA:$zebraStatus"
Write-Output "BEMATECH:$bematechStatus"
Write-Output "BIOMETRIC:$biometricStatus"
''';

    final tempDir = Directory.systemTemp;
    final scriptFile = File('${tempDir.path}\\monitor_peripherals.ps1');
    
    try {
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);

      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );
      
      final stdoutString = _decodeOutput(result.stdout);

      Map<String, String> devices = {
        'zebra': 'Não detectado',
        'bematech': 'Não detectado',
        'biometric': 'Não detectado'
      };
      
      final lines = stdoutString.split('\n');
      for (String line in lines) {
        final trimmedLine = line.trim();
        
        if (trimmedLine.startsWith('ZEBRA:')) {
          devices['zebra'] = trimmedLine.substring('ZEBRA:'.length).trim();
        } else if (trimmedLine.startsWith('BEMATECH:')) {
          devices['bematech'] = trimmedLine.substring('BEMATECH:'.length).trim();
        } else if (trimmedLine.startsWith('BIOMETRIC:')) {
          devices['biometric'] = trimmedLine.substring('BIOMETRIC:'.length).trim();
        }
      }
      
      return devices;
    } catch (e) {
      debugPrint("❌ Erro ao detectar periféricos: $e");
      return {
        'zebra': 'Erro',
        'bematech': 'Erro',
        'biometric': 'Erro'
      };
    } finally {
      try {
        if (await scriptFile.exists()) await scriptFile.delete();
      } catch (_) {}
    }
  }

  // === MÉTODO PRINCIPAL: COLETA E ENVIA DADOS DINAMICAMENTE ===

  Future<void> collectAndSendData({
    required String moduleId,
    required String serverUrl,
    required String token,
    String? manualSector,
    String? manualFloor,
  }) async {
    if (serverUrl.isEmpty || moduleId.isEmpty || token.isEmpty) {
      debugPrint('❌ Configurações incompletas. Abortando envio.');
      return;
    }

    debugPrint('\n🔄 INICIANDO CICLO DE MONITORAMENTO');
    debugPrint('📋 Módulo: $moduleId');

    try {
      // 1. Buscar estrutura do módulo
      // Verifica e renova token se necessário
      await _authService.refreshTokenIfNeeded(serverUrl: serverUrl);
      
      final structure = await _moduleStructureService.fetchModuleStructure(
        serverUrl: serverUrl,
        token: token,
        moduleId: moduleId,
      );

      if (structure == null) {
        throw Exception('Não foi possível obter a estrutura do módulo');
      }

      debugPrint('📦 Tipo do módulo: ${structure.type}');

      // 2. Coletar dados base (comuns a todos)
      final serialNumber = await _getSerialNumber();
      if (serialNumber.isEmpty || serialNumber.toLowerCase().contains('error')) {
        throw Exception('Não foi possível obter o número de série');
      }

      final networkInfo = await _getNetworkInfo();
      final storageInfo = await _getStorage();

      Map<String, dynamic> payload = {
        'asset_name': await _getHostname(),
        'serial_number': serialNumber,
        'ip_address': networkInfo['ip_address'],
        'mac_address': networkInfo['mac_address'],
        'location': '',
        'assigned_to': await _runCommand('whoami', []),
        'hostname': await _getHostname(),
        'model': await _getModel(),
        'manufacturer': await _getManufacturer(),
        'operating_system': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'custom_data': {
          'sector': manualSector,
          'floor': manualFloor,
        }
      };

      // 3. Coletar dados específicos baseado no tipo
      switch (structure.type.toLowerCase()) {
        case 'desktop':
          debugPrint('💻 Coletando dados de Desktop...');
          
          payload.addAll({
            'processor': await _getProcessor(),
            'ram': await _getRam(),
            'storage': storageInfo['storage'],
            'storage_type': storageInfo['storage_type'],
            'installed_software': await _getInstalledPrograms(),
            'java_version': await _getJavaVersion(),
            'browser_version': await _getBrowserVersion(),
          });

          final antivirusInfo = await _getAntivirusStatus();
          payload.addAll(antivirusInfo);

          final peripherals = await _getPeripherals();
          payload['biometric_reader'] = peripherals['biometric'];
          payload['connected_printer'] = '${peripherals['zebra']} / ${peripherals['bematech']}';
          break;

        case 'notebook':
          debugPrint('💼 Coletando dados de Notebook...');
          
          payload.addAll({
            'processor': await _getProcessor(),
            'ram': await _getRam(),
            'storage': storageInfo['storage'],
            'installed_software': await _getInstalledPrograms(),
            'is_encrypted': await _isEncrypted(),
          });

          final antivirusInfo = await _getAntivirusStatus();
          payload.addAll(antivirusInfo);

          final batteryInfo = await _getBatteryInfo();
          payload.addAll(batteryInfo);
          break;

        case 'panel':
          debugPrint('📺 Coletando dados de Panel...');
          
          payload.addAll({
            'is_online': true,
            'screen_size': 'N/A', // Requer hardware específico
            'resolution': 'N/A',
            'firmware_version': 'N/A',
          });
          break;

        case 'printer':
          debugPrint('🖨️  Coletando dados de Printer...');
          
          // Impressoras requerem detecção específica via rede
          payload.addAll({
            'connection_type': 'network',
            'printer_status': 'unknown',
            'is_duplex': false,
            'is_color': false,
          });
          break;

        default:
          debugPrint('📦 Módulo customizado: apenas dados base');
      }

      // 4. Validar dados antes de enviar
      if (!_moduleStructureService.validateData(payload, structure.type)) {
        debugPrint('⚠️  Alguns campos obrigatórios estão ausentes');
      }

      // 5. Enviar dados para o servidor
      debugPrint('📤 Enviando dados para $serverUrl/api/modules/$moduleId/assets');

      // Usa os headers do AuthService (JWT ou Legacy Token)
      final headers = _authService.getHeaders();
      
      final response = await http.post(
        Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
        headers: headers,
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Dados enviados com sucesso!');
        debugPrint('📊 Resposta: ${response.body}');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('❌ Token inválido ou expirado');
        throw Exception('Token inválido ou expirado');
      } else {
        debugPrint('❌ Erro ao enviar: ${response.statusCode}');
        debugPrint('   Corpo: ${response.body}');
        throw Exception('Erro do servidor: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ ERRO no ciclo de monitoramento: $e');
      rethrow;
    }

    debugPrint('✅ CICLO DE MONITORAMENTO CONCLUÍDO\n');
  }
}