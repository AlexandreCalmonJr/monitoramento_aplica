# get_core_system_info.ps1 (UNIFICADO E CORRIGIDO)
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# --- 1. Informações Base ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, LastBootUpTime
$cs = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object Model, Manufacturer, TotalPhysicalMemory
$bios = Get-CimInstance -ClassName Win32_BIOS | Select-Object SerialNumber
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1 | Select-Object Name
$volC = Get-Volume -DriveLetter C
$disk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 } | Select-Object -First 1

# ✅ ADICIONADO: Uptime e Usuário
$uptimeTicks = (Get-Date) - [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
# Formata como "Xd Yh Zm"
$uptime = "$($uptimeTicks.Days)d $($uptimeTicks.Hours)h $($uptimeTicks.Minutes)m"
$currentUser = $env:USERNAME

# --- 2. Rede ---
$wifiAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and ($_.InterfaceDescription -match "Wi-Fi|Wireless|802.11") } | Select-Object -First 1
$ethernetAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Wi-Fi|Wireless|802.11|Virtual|Hyper-V" } | Select-Object -First 1
$activeAdapter = if ($wifiAdapter) { $wifiAdapter } else { $ethernetAdapter }
$net = if ($activeAdapter) { Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $activeAdapter.InterfaceIndex | Select-Object -First 1 } else { $null }
$mac = if ($activeAdapter) { $activeAdapter.MacAddress } else { $null }
$bssid = $null; $ssid = $null; $signalQuality = $null
try {
    $wlanInfo = netsh wlan show interfaces | Select-String "BSSID", "SSID", "Signal"
    foreach ($line in $wlanInfo) {
        $lineStr = $line.ToString().Trim()
        if ($lineStr -match "BSSID\s+:\s+(.+)") { $bssid = $Matches[1].Trim() }
        if ($lineStr -match "SSID\s+:\s+(.+)" -and $lineStr -notmatch "BSSID") { $ssid = $Matches[1].Trim() }
        if ($lineStr -match "Signal\s+:\s+(\d+)%") { $signalQuality = $Matches[1].Trim() + "%" }
    }
} catch {}
$connectionType = if ($wifiAdapter -and $wifiAdapter.Status -eq "Up") { "WiFi" } 
                elseif ($ethernetAdapter) { "Ethernet" } 
                else { "Desconhecido" }

# --- 3. Segurança ---
$av = Get-MpComputerStatus | Select-Object AntivirusEnabled, AMProductVersion
$bitlocker = Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty ProtectionStatus

# --- 4. Detecção de Notebook ---
$isNotebook = $false
$chassisTypes = @(8, 9, 10, 11, 14, 18, 21, 31, 32)
$chassis = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
foreach ($type in $chassis) {
    if ($chassisTypes -contains $type) {
        $isNotebook = $true
        break
    }
}

# --- 5. Software ---
function Get-RegValue { param($path, $name) (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
$javaVersion = Get-RegValue -path "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment" -name "CurrentVersion"
if ($javaVersion) { $javaVersionPath = "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\$javaVersion"; $javaVersion = Get-RegValue -path $javaVersionPath -name "JavaVersion" }
$chromeVersion = (Get-RegValue -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -name "(default)" | Get-Item -ErrorAction SilentlyContinue).VersionInfo.ProductVersion

# --- 6. Programas Instalados ---
$installedPrograms = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -ne $null } | Select-Object DisplayName, DisplayVersion | ForEach-Object { "$($_.DisplayName) version $($_.DisplayVersion)" } | Sort-Object -Unique

# --- 7. Bateria ---
$battery = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue
$level = 0
$health = "N/A"
if ($battery) {
  $level = $battery.EstimatedChargeRemaining
  $health = if ($battery.BatteryStatus -eq 2) { "Carregando" } else { "OK" }
}

# --- 8. Periféricos ---
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

# --- 9. Validação de Hostname e Serial ---
$hostname = $env:COMPUTERNAME
$serial = $bios.SerialNumber
if (-not $hostname -or $hostname.Trim() -eq "") { $hostname = $serial }
if (-not $serial -or $serial.Trim() -eq "" -or $serial -match "000000" -or $serial -match "N/A") { $serial = $hostname }
if (-not $hostname -or $hostname.Trim() -eq "") { $hostname = "HostDesconhecido" }
if (-not $serial -or $serial.Trim() -eq "") { $serial = $hostname }

# --- 10. Objeto JSON Final (Unificado) ---
$data = [PSCustomObject]@{
    # Core
    hostname           = $hostname.Trim()
    serial_number      = $serial.Trim()
    model              = $cs.Model
    manufacturer       = $cs.Manufacturer
    processor          = $cpu.Name
    ram                = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB"
    storage            = "$([math]::Round($volC.Size / 1GB, 2)) GB"
    storage_type       = $disk.MediaType
    operating_system   = $os.Caption
    os_version         = $os.Version
    is_notebook        = $isNotebook
    uptime             = $uptime       # ✅ CAMPO ADICIONADO
    current_user       = $currentUser # ✅ CAMPO ADICIONADO
    
    # Rede
    ip_address         = $net.IPAddress
    mac_address        = $mac
    mac_address_radio  = $bssid
    wifi_ssid          = $ssid
    wifi_signal        = $signalQuality
    connection_type    = $connectionType
    
    # Segurança
    antivirus_status   = $av.AntivirusEnabled
    antivirus_version  = $av.AMProductVersion
    is_encrypted       = if ($bitlocker -eq "On") { $true } else { $false }
    
    # Software
    java_version       = $javaVersion
    browser_version    = "Chrome $chromeVersion"
    installed_software = $installedPrograms
    
    # Bateria
    battery_level      = $level
    battery_health     = $health
    
    # Periféricos
    biometric_reader   = $biometricStatus
    connected_printer  = "$zebraStatus / $bematechStatus"
}
$data | ConvertTo-Json -Depth 4