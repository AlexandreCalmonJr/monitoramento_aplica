// File: lib/services/monitoring_service.dart
// (ARQUIVO COMPLETO - PASSO 2)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class MonitoringService {
  final Logger _logger;
  final AuthService _authService;
  final ModuleStructureService _moduleStructureService;

  MonitoringService(this._logger, this._authService, this._moduleStructureService) {
    _logger.i('MonitoringService inicializado');
  }
  
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
        _logger.w("Erro no comando '$command ${args.join(' ')}': $stderrString");
        return "";
      }
    } catch (e) {
      _logger.e("Exceção no comando '$command ${args.join(' ')}': $e");
      return "";
    }
  }
  
  // === NOVOS MÉTODOS DE COLETA OTIMIZADOS ===

  /// Executa um script PowerShell consolidado para obter informações do sistema.
  /// Isso substitui 10-12 chamadas de processo separadas.
  Future<Map<String, dynamic>> _getCoreSystemInfo() async {
    const String scriptContent = r'''
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version
$cs = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object Model, Manufacturer, TotalPhysicalMemory
$bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object SerialNumber
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 | Select-Object Name
$volC = Get-Volume -DriveLetter C
$disk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 } | Select-Object -First 1
$net = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias (Get-NetConnectionProfile).InterfaceAlias | Select-Object -First 1
$mac = if ($net) { (Get-NetAdapter -InterfaceIndex $net.InterfaceIndex).MacAddress } else { $null }
$av = Get-MpComputerStatus | Select-Object AntivirusEnabled, AMProductVersion
$bitlocker = Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty ProtectionStatus
$bssid = $null
try {
    $wifiProfile = (netsh wlan show interfaces) | Select-String "BSSID"
    if ($wifiProfile) {
        $bssid = ($wifiProfile -split ":")[1].Trim()
    }
} catch {}

# Funções auxiliares para buscar no registro
function Get-RegValue {
    param($path, $name)
    (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
}

$javaVersion = Get-RegValue -path "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment" -name "CurrentVersion"
if ($javaVersion) {
    $javaVersionPath = "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\$javaVersion"
    $javaVersion = Get-RegValue -path $javaVersionPath -name "JavaVersion"
}

$chromeVersion = (Get-RegValue -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -name "(default)" | Get-Item -ErrorAction SilentlyContinue).VersionInfo.ProductVersion


$data = [PSCustomObject]@{
    hostname           = $env:COMPUTERNAME
    serial_number      = $bios.SerialNumber
    model              = $cs.Model
    manufacturer       = $cs.Manufacturer
    processor          = $cpu.Name
    ram                = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB"
    storage            = "$([math]::Round($volC.Size / 1GB, 2)) GB"
    storage_type       = $disk.MediaType
    operating_system   = $os.Caption
    os_version         = $os.Version
    ip_address         = $net.IPAddress
    mac_address        = $mac
    mac_address_radio  = $bssid
    antivirus_status   = $av.AntivirusEnabled
    antivirus_version  = $av.AMProductVersion
    is_encrypted       = if ($bitlocker -eq "On") { $true } else { $false }
    java_version       = $javaVersion
    browser_version    = "Chrome $chromeVersion"
}

# Converte o objeto para JSON
$data | ConvertTo-Json -Depth 2
''';

    final tempDir = Directory.systemTemp;
    final scriptFile = File('${tempDir.path}\\monitor_core.ps1');
    
    try {
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);

      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );
      
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0 && stdoutString.isNotEmpty) {
        final decodedJson = json.decode(stdoutString);
        _logger.i('✅ Informações do sistema coletadas via script consolidado');
        return decodedJson;
      } else {
        _logger.e('Erro ao executar script consolidado: $stderrString');
        return {};
      }
    } catch (e) {
      _logger.e("❌ Exceção ao executar script consolidado: $e");
      return {};
    } finally {
      try {
        if (await scriptFile.exists()) await scriptFile.delete();
      } catch (_) {}
    }
  }

  /// Coleta programas instalados (script separado, pois pode ser lento)
  Future<List<String>> _getInstalledPrograms() async {
    _logger.i("--- Iniciando coleta de programas ---");
    try {
      const command = 'powershell';
      const script = r'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -ne $null } | Select-Object DisplayName, DisplayVersion | ForEach-Object { "$($_.DisplayName) version $($_.DisplayVersion)" } | Sort-Object -Unique';
      
      final result = await _runCommand(command, ['-command', script]);
      if (result.isNotEmpty && !result.startsWith("Erro")) {
        final programs = result.split('\n').where((s) => s.trim().isNotEmpty).toList();
        _logger.i("✅ ${programs.length} programas encontrados");
        return programs;
      }
    } catch (e) {
      _logger.e("❌ Erro ao coletar programas: $e");
    }
    return [];
  }

  /// Notebook: Bateria (script separado, pois é WMI e específico)
  Future<Map<String, dynamic>> _getBatteryInfo() async {
    try {
      final result = await _runCommand('powershell', [
        '-command',
        r'''
        $battery = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue
        if ($battery) {
          $level = $battery.EstimatedChargeRemaining
          $health = if ($battery.BatteryStatus -eq 2) { "Carregando" } else { "OK" }
          Write-Output "$level;$health"
        }
        '''
      ]);
      
      if (result.contains(';')) {
        final parts = result.split(';');
        _logger.i('✅ Informações da bateria coletadas');
        return {
          'battery_level': int.tryParse(parts[0]),
          'battery_health': parts[1],
        };
      }
    } catch (e) {
      _logger.e("Erro ao coletar informações da bateria: $e");
    }
    return {'battery_level': null, 'battery_health': 'N/A'};
  }

  /// Desktop: Periféricos (script separado e complexo)
  Future<Map<String, String>> _getPeripherals() async {
    _logger.i("--- Iniciando coleta de periféricos ---");
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
      _logger.i('✅ Periféricos verificados');
      return devices;
    } catch (e) {
      _logger.e("❌ Erro ao detectar periféricos: $e");
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
      _logger.w('❌ Configurações incompletas. Abortando envio.');
      return;
    }

    _logger.i('🔄 INICIANDO CICLO DE MONITORAMENTO');
    _logger.d('📋 Módulo: $moduleId');

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

      _logger.i('📦 Tipo do módulo: ${structure.type}');

      // 2. Coletar dados base (comuns a todos)
      // Executa o script consolidado
      Map<String, dynamic> coreInfo = await _getCoreSystemInfo();

      if (coreInfo.isEmpty || (coreInfo['serial_number'] as String?).toString().isEmpty) {
        throw Exception('Não foi possível obter informações do sistema (serial number nulo)');
      }

      // Preenche o payload inicial com dados do script
      Map<String, dynamic> payload = {
        'asset_name': coreInfo['hostname'] ?? 'N/A',
        'serial_number': coreInfo['serial_number'] ?? 'N/A',
        'ip_address': coreInfo['ip_address'] ?? 'N/A',
        'mac_address': coreInfo['mac_address'] ?? 'N/A',
        'mac_address_radio': coreInfo['mac_address_radio'] ?? 'N/A',
        'location': coreInfo['location'] ?? 'N/A',
        'assigned_by': await _runCommand('whoami', []),
        // Mantém separado, é rápido
        'assigned_to': await _runCommand('whoami', []), // Mantém separado, é rápido
        'hostname': coreInfo['hostname'] ?? 'N/A',
        'model': coreInfo['model'] ?? 'N/A',
        'manufacturer': coreInfo['manufacturer'] ?? 'N/A',
        'operating_system': coreInfo['operating_system'] ?? Platform.operatingSystem,
        'os_version': coreInfo['os_version'] ?? Platform.operatingSystemVersion,
        
        // Adiciona dados que já foram coletados pelo script
        'processor': coreInfo['processor'] ?? 'N/A',
        'ram': coreInfo['ram'] ?? 'N/A',
        'storage': coreInfo['storage'] ?? 'N/A',
        'storage_type': coreInfo['storage_type'] ?? 'N/A',
        'antivirus_status': coreInfo['antivirus_status'] ?? false,
        'antivirus_version': coreInfo['antivirus_version'] ?? 'N/A',
        'is_encrypted': coreInfo['is_encrypted'] ?? false,
        'java_version': coreInfo['java_version'] ?? 'N/A',
        'browser_version': coreInfo['browser_version'] ?? 'N/A',

        'custom_data': {
          'sector': manualSector,
          'floor': manualFloor,
        }
      };

      // 3. Coletar dados específicos baseado no tipo
      switch (structure.type.toLowerCase()) {
        case 'desktop':
          _logger.i('💻 Coletando dados específicos de Desktop...');
          
          // Coleta programas (lento, por isso separado)
          payload['installed_software'] = await _getInstalledPrograms();

          // Coleta periféricos (script separado)
          final peripherals = await _getPeripherals();
          payload['biometric_reader'] = peripherals['biometric'];
          payload['connected_printer'] = '${peripherals['zebra']} / ${peripherals['bematech']}';
          break;

        case 'notebook':
          _logger.i('💼 Coletando dados específicos de Notebook...');
          
          // Coleta programas (lento, por isso separado)
          payload['installed_software'] = await _getInstalledPrograms();

          // Coleta bateria (separado)
          final batteryInfo = await _getBatteryInfo();
          payload.addAll(batteryInfo);
          break;

        case 'panel':
          _logger.i('📺 Coletando dados de Panel...');
          payload.addAll({
            'is_online': true,
            'screen_size': 'N/A',
            'resolution': 'N/A',
            'firmware_version': 'N/A',
          });
          break;

        case 'printer':
          _logger.i('🖨️  Coletando dados de Printer...');
          payload.addAll({
            'connection_type': 'network',
            'printer_status': 'unknown',
          });
          break;

        default:
          _logger.i('📦 Módulo customizado: apenas dados base e do script principal');
      }

      // 4. Validar dados antes de enviar
      if (!_moduleStructureService.validateData(payload, structure.type)) {
        _logger.w('⚠️  Alguns campos obrigatórios estão ausentes');
      }

      // 5. Enviar dados para o servidor
      _logger.i('📤 Enviando dados para $serverUrl/api/modules/$moduleId/assets');

      // Usa os headers do AuthService (JWT ou Legacy Token)
      final headers = _authService.getHeaders();
      
      final response = await http.post(
        Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
        headers: headers,
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.i('✅ Dados enviados com sucesso!');
        _logger.d('📊 Resposta: ${response.body}');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.w('❌ Token inválido ou expirado');
        throw Exception('Token inválido ou expirado');
      } else {
        _logger.e('❌ Erro ao enviar: ${response.statusCode}');
        _logger.e('   Corpo: ${response.body}');
        throw Exception('Erro do servidor: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('❌ ERRO no ciclo de monitoramento: $e');
      rethrow;
    }

    _logger.i('✅ CICLO DE MONITORAMENTO CONCLUÍDO\n');
  }
}