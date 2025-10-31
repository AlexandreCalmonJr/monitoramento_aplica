// File: lib/services/monitoring_service.dart
// (VERSÃO ATUALIZADA - CORREÇÃO NOTEBOOK + IMPRESSORA + HOSTNAME VAZIO)
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
  
  // === MÉTODOS DE COLETA OTIMIZADOS ===

  // ===================================================================
  // ✅ ATUALIZADO: SCRIPT DE COLETA DO HOST (Correção asset_name/hostname)
  // ===================================================================
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
    if ($wifiProfile) { $bssid = ($wifiProfile -split ":")[1].Trim() }
} catch {}
function Get-RegValue { param($path, $name) (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
$javaVersion = Get-RegValue -path "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment" -name "CurrentVersion"
if ($javaVersion) { $javaVersionPath = "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\$javaVersion"; $javaVersion = Get-RegValue -path $javaVersionPath -name "JavaVersion" }
$chromeVersion = (Get-RegValue -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -name "(default)" | Get-Item -ErrorAction SilentlyContinue).VersionInfo.ProductVersion

# --- ✅ INÍCIO DA CORREÇÃO (Hostname/Asset_name) ---
$hostname = $env:COMPUTERNAME
$serial = $bios.SerialNumber

# 1. Validar Hostname
if (-not $hostname -or $hostname.Trim() -eq "") {
    # Se hostname é inválido, usa o Serial como Hostname
    $hostname = $serial
}

# 2. Validar Serial (caso o hostname também fosse inválido)
if (-not $serial -or $serial.Trim() -eq "" -or $serial -match "000000" -or $serial -match "N/A") {
    # Se serial também é inválido, usa o hostname (que pode ser o serial, mas garante que não seja "N/A")
    $serial = $hostname
}

# 3. Fallback final (se ambos falharem, o que é quase impossível)
if (-not $hostname -or $hostname.Trim() -eq "") {
    $hostname = "HostDesconhecido"
}
if (-not $serial -or $serial.Trim() -eq "") {
    $serial = $hostname # Garante que serial e hostname sejam iguais se tudo falhar
}
# --- ✅ FIM DA CORREÇÃO ---

$data = [PSCustomObject]@{
    hostname           = $hostname.Trim() # <-- Usa a variável validada
    serial_number      = $serial.Trim()    # <-- Usa a variável validada
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

  Future<List<String>> _getInstalledPrograms() async {
    // ... (IDÊNTICO AO ANTERIOR)
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

  Future<Map<String, dynamic>> _getBatteryInfo() async {
    // ... (IDÊNTICO AO ANTERIOR)
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

  Future<Map<String, String>> _getPeripherals() async {
    // ... (IDÊNTICO AO ANTERIOR)
    _logger.i("--- Iniciando coleta de periféricos ---");
    const String scriptContent = r'''
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$zebraStatus = "Não detectado"; $bematechStatus = "Não detectado"; $biometricStatus = "Não detectado"
try {
    $allPrinters = Get-Printer -ErrorAction Stop
    foreach ($printer in $allPrinters) {
        if ($printer.Name -match "Zebra|ZDesigner|ZD") { $zebraStatus = "Conectado - $($printer.PrinterStatus)" }
        if ($printer.Name -match "Bematech|MP-4200|MP4200") { $bematechStatus = "Conectado - $($printer.PrinterStatus)" }
    }
} catch {}
try {
    $biometricDevice = Get-PnpDevice -Class "Biometric" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($biometricDevice) { $biometricStatus = if ($biometricDevice.Status -eq "OK") { "Conectado" } else { "Detectado - $($biometricDevice.Status)" } }
} catch {}
Write-Output "ZEBRA:$zebraStatus"; Write-Output "BEMATECH:$bematechStatus"; Write-Output "BIOMETRIC:$biometricStatus"
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

      Map<String, String> devices = {'zebra': 'Não detectado', 'bematech': 'Não detectado', 'biometric': 'Não detectado'};
      final lines = stdoutString.split('\n');
      for (String line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('ZEBRA:')) { devices['zebra'] = trimmedLine.substring('ZEBRA:'.length).trim(); }
        else if (trimmedLine.startsWith('BEMATECH:')) { devices['bematech'] = trimmedLine.substring('BEMATECH:'.length).trim(); }
        else if (trimmedLine.startsWith('BIOMETRIC:')) { devices['biometric'] = trimmedLine.substring('BIOMETRIC:'.length).trim(); }
      }
      _logger.i('✅ Periféricos verificados');
      return devices;
    } catch (e) {
      _logger.e("❌ Erro ao detectar periféricos: $e");
      return {'zebra': 'Erro', 'bematech': 'Erro', 'biometric': 'Erro'};
    } finally {
      try {
        if (await scriptFile.exists()) await scriptFile.delete();
      } catch (_) {}
    }
  }

  // ===================================================================
  // ✅ SCRIPT DE COLETA DE IMPRESSORAS (Correção asset_name)
  // ===================================================================
  Future<List<Map<String, dynamic>>> _getPrintersInfo() async {
    _logger.i("--- Iniciando coleta de impressoras ---");
    const String scriptContent = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
$netInfo = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias (Get-NetConnectionProfile).InterfaceAlias | Select-Object -First 1
$hostName = $env:COMPUTERNAME
$hostIp = $netInfo.IPAddress
$printersList = @()
$wmiPrinters = Get-CimInstance -ClassName Win32_Printer
if ($wmiPrinters -eq $null) { Write-Output "[]"; return }

foreach ($printer in $wmiPrinters) {
    $portName = $printer.PortName; $port = Get-PrinterPort -Name $portName
    $ip = $null; $usbPortName = $null; $connectionType = "unknown"
    $name = $printer.Name; $serial = $printer.SerialNumber

    if (-not $name -or $name.Trim() -eq "") {
        if ($serial -and $serial.Trim() -ne "" -and $serial -notmatch "000000" -and $serial -notmatch "N/A") { $name = $serial.Trim() }
        else { continue }
    }
    if (-not $serial -or $serial -match "000000" -or $serial -match "N/A" -or $serial.Trim() -eq "") {
        $serial = "$hostName-$($name.Trim())" 
    }

    if ($port.PortType -eq "Usb") { $connectionType = "usb"; $usbPortName = $portName }
    elseif ($port.PortType -eq "Tcp" -and $port.HostAddress) { $connectionType = "network"; $ip = $port.HostAddress }
    elseif ($port.PortType -eq "Wsd" -or $port.PortType -eq "Tcp") { $connectionType = "usb"; $usbPortName = $portName }
    elseif ($portName -match "LPT" -or $portName -match "COM") { $connectionType = "local" }
    else { $connectionType = "virtual" }

    $statusText = "unknown"
    switch ($printer.PrinterStatus) {
        3 { $statusText = "online" }; 4 { $statusText = "printing" }
        5 { $statusText = "warming_up" }; 7 { $statusText = "offline" }
        6 { $statusText = "stopped" }; 1, 2 { $statusText = "unknown" }
    }

    if ($connectionType -eq "usb" -or $connectionType -eq "network") {
        $printerData = [PSCustomObject]@{
            asset_name = $name.Trim(); serial_number = $serial.Trim()
            model = $printer.DriverName; manufacturer = $printer.Manufacturer
            printer_status = $statusText; connection_type = $connectionType
            ip_address = $ip; usb_port = $usbPortName
            host_computer_name = $hostName; host_computer_ip = $hostIp
            driver_version = $printer.DriverVersion
            total_page_count = $null; firmware_version = $null
        }
        $printersList += $printerData
    }
}
$printersList | ConvertTo-Json -Depth 4
''';

    final tempDir = Directory.systemTemp;
    final scriptFile = File('${tempDir.path}\\monitor_printers.ps1');
    
    try {
      await scriptFile.writeAsString(scriptContent, flush: true, encoding: utf8);
      final result = await Process.run(
        'powershell',
        ['-ExecutionPolicy', 'Bypass', '-NoProfile', '-File', scriptFile.path],
        runInShell: true,
      );
      final stdoutString = _decodeOutput(result.stdout);
      final stderrString = _decodeOutput(result.stderr);

      if (result.exitCode == 0 && stdoutString.isNotEmpty && stdoutString.startsWith('[')) {
        final List<dynamic> decodedJson = json.decode(stdoutString);
        _logger.i('✅ ${decodedJson.length} impressoras físicas encontradas');
        return decodedJson.cast<Map<String, dynamic>>();
      } else {
        _logger.e('Erro ao executar script de impressoras: $stderrString \n $stdoutString');
        return [];
      }
    } catch (e) {
      _logger.e("❌ Exceção ao executar script de impressoras: $e");
      return [];
    } finally {
      try {
        if (await scriptFile.exists()) await scriptFile.delete();
      } catch (_) {}
    }
  }

  // ===================================================================
  // ✅ FUNÇÃO DE ENVIO DE PAYLOAD (Refatorada)
  // ===================================================================
  Future<void> _sendPayload(Map<String, dynamic> payload, String serverUrl, String moduleId) async {
    try {
      // 🔥 VALIDAÇÃO E SANITIZAÇÃO ROBUSTA
      String serial = (payload['serial_number'] ?? '').toString().trim();
      String assetName = (payload['asset_name'] ?? '').toString().trim();
      String hostname = (payload['hostname'] ?? '').toString().trim();

      // 1. Validar Serial Number
      if (serial.isEmpty || serial == 'N/A' || serial.toLowerCase() == 'null' || serial.contains('000000')) {
        _logger.w('⚠️ Serial inválido: "$serial". Tentando usar hostname...');
        serial = hostname.isNotEmpty && hostname != 'N/A' ? hostname : 'UNKNOWN-${DateTime.now().millisecondsSinceEpoch}';
      }

      // 2. Validar Asset Name (prioriza hostname, fallback para serial)
      if (assetName.isEmpty || assetName == 'N/A' || assetName.toLowerCase() == 'null') {
        _logger.w('⚠️ Asset Name inválido: "$assetName". Usando hostname ou serial...');
        assetName = hostname.isNotEmpty && hostname != 'N/A' ? hostname : serial;
      }

      // 3. Validação final (rejeita apenas se TUDO falhar)
      if (serial.isEmpty || assetName.isEmpty) {
        _logger.e('❌ PAYLOAD CRÍTICO: Impossível enviar sem identificação válida');
        _logger.e('   Serial: "$serial" | AssetName: "$assetName" | Hostname: "$hostname"');
        return;
      }

      // Atualiza o payload com valores sanitizados
      payload['serial_number'] = serial;
      payload['asset_name'] = assetName;
      if (hostname.isNotEmpty && hostname != 'N/A') {
        payload['hostname'] = hostname;
      }

      _logger.i('📤 Enviando ativo: Nome="$assetName" | S/N="$serial"');

      final headers = _authService.getHeaders();
      
      final response = await http.post(
        Uri.parse('$serverUrl/api/modules/$moduleId/assets'),
        headers: headers,
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final wasUpdated = responseData['updated'] ?? false;
        _logger.i(wasUpdated 
          ? '✅ Ativo "$assetName" atualizado com sucesso!' 
          : '✅ Novo ativo "$assetName" criado com sucesso!');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.w('❌ Token inválido ou expirado para "$assetName"');
        throw Exception('Autenticação falhou');
      } else {
        _logger.e('❌ Erro ao enviar "$assetName": ${response.statusCode}');
        _logger.e('   Resposta: ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.e('❌ ERRO no envio do payload: $e');
      _logger.d('Stack: $stackTrace');
    }
  }

  // ===================================================================
  // ✅ MÉTODO PRINCIPAL DE COLETA E ENVIO
  // ===================================================================
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
      await _authService.refreshTokenIfNeeded(serverUrl: serverUrl);
      final structure = await _moduleStructureService.fetchModuleStructure(
        serverUrl: serverUrl, token: token, moduleId: moduleId,
      );
      if (structure == null) { throw Exception('Não foi possível obter a estrutura do módulo'); }
      _logger.i('📦 Tipo do módulo: ${structure.type}');
      final String moduleType = structure.type.toLowerCase();

      // ==========================================================
      // CASO ESPECIAL: MÓDULO DE IMPRESSORA
      // ==========================================================
      if (moduleType == 'printer') {
        _logger.i('🖨️  Módulo de Impressora selecionado. Coletando impressoras...');
        final printers = await _getPrintersInfo();

        if (printers.isEmpty) {
          _logger.i('Nenhuma impressora física encontrada para enviar.');
          _logger.i('✅ CICLO DE MONITORAMENTO (IMPRESSORAS) CONCLUÍDO\n');
          return;
        }

        for (final printerPayload in printers) {
          printerPayload['custom_data'] = { 'sector': manualSector, 'floor': manualFloor };
          if (!_moduleStructureService.validateData(printerPayload, 'printer')) {
             _logger.w('⚠️ Impressora [${printerPayload['serial_number']}] com campos obrigatórios ausentes. Pulando envio.');
             continue;
          }
          await _sendPayload(printerPayload, serverUrl, moduleId);
        }
        _logger.i('✅ CICLO DE MONITORAMENTO (IMPRESSORAS) CONCLUÍDO\n');
        return; 
      }
      
      // ==========================================================
      // LÓGICA PADRÃO (DESKTOP, NOTEBOOK, PANEL)
      // ==========================================================
      _logger.i('Coletando dados do host (PC)...');
      Map<String, dynamic> coreInfo = await _getCoreSystemInfo();

      if (coreInfo.isEmpty || (coreInfo['serial_number'] as String?).toString().isEmpty) {
        throw Exception('Não foi possível obter informações do sistema (serial number nulo)');
      }
      Map<String, dynamic> payload = {
          'custom_data': { 'sector': manualSector, 'floor': manualFloor }
      };
      
      // ✅ ATUALIZADO: O 'asset_name' vem do script validado
      payload.addAll(coreInfo);
      payload['assigned_to'] = await _runCommand('whoami', []); 
      
      // O 'asset_name' é definido pelo coreInfo['hostname']
      // O 'serial_number' é definido pelo coreInfo['serial_number']

      switch (moduleType) {
        case 'desktop':
          _logger.i('💻 Coletando dados específicos de Desktop...');
          payload['installed_software'] = await _getInstalledPrograms();
          final peripherals = await _getPeripherals();
          payload['biometric_reader'] = peripherals['biometric'];
          payload['connected_printer'] = '${peripherals['zebra']} / ${peripherals['bematech']}';
          break;

        case 'notebook':
          _logger.i('💼 Coletando dados específicos de Notebook...');
          payload['installed_software'] = await _getInstalledPrograms();
          final batteryInfo = await _getBatteryInfo();
          
          // ✅ CORREÇÃO NOTEBOOK
          if (batteryInfo['battery_level'] != null) {
            payload['battery_level'] = batteryInfo['battery_level'];
          }
          payload['battery_health'] = batteryInfo['battery_health'];
          break;

        case 'panel':
          _logger.i('📺 Coletando dados de Panel...');
          payload.addAll({
            'is_online': true, 'screen_size': 'N/A',
            'resolution': 'N/A', 'firmware_version': 'N/A',
          });
          break;
        default:
          _logger.i('📦 Módulo customizado ou não mapeado: enviando apenas dados base');
      }

      if (!_moduleStructureService.validateData(payload, structure.type)) {
        _logger.w('⚠️  Alguns campos obrigatórios estão ausentes');
      }
      await _sendPayload(payload, serverUrl, moduleId);

    } catch (e) {
      _logger.e('❌ ERRO no ciclo de monitoramento: $e');
      rethrow;
    }
    _logger.i('✅ CICLO DE MONITORAMENTO (HOST) CONCLUÍDO\n');
  }
}