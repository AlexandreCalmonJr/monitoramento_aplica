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

# MELHORADO: Detecção de rede (prioriza WiFi se disponível)
$wifiAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and ($_.InterfaceDescription -match "Wi-Fi|Wireless|802.11") } | Select-Object -First 1
$ethernetAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Wi-Fi|Wireless|802.11|Virtual|Hyper-V" } | Select-Object -First 1

# Prioriza WiFi, depois Ethernet
$activeAdapter = if ($wifiAdapter) { $wifiAdapter } else { $ethernetAdapter }
$net = if ($activeAdapter) { Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $activeAdapter.InterfaceIndex | Select-Object -First 1 } else { $null }
$mac = if ($activeAdapter) { $activeAdapter.MacAddress } else { $null }

$av = Get-MpComputerStatus | Select-Object AntivirusEnabled, AMProductVersion
$bitlocker = Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty ProtectionStatus

# MELHORADO: Coleta BSSID (múltiplos métodos)
$bssid = $null
$ssid = $null
$signalQuality = $null

# Método 1: netsh wlan (mais confiável)
try {
    $wlanInfo = netsh wlan show interfaces | Select-String "BSSID", "SSID", "Signal"
    foreach ($line in $wlanInfo) {
        $lineStr = $line.ToString().Trim()
        if ($lineStr -match "BSSID\s+:\s+(.+)") { $bssid = $Matches[1].Trim() }
        if ($lineStr -match "SSID\s+:\s+(.+)" -and $lineStr -notmatch "BSSID") { $ssid = $Matches[1].Trim() }
        if ($lineStr -match "Signal\s+:\s+(\d+)%") { $signalQuality = $Matches[1].Trim() + "%" }
    }
} catch {}

# Método 2: WMI (fallback)
if (-not $bssid -and $wifiAdapter) {
    try {
        $wifiConfig = netsh wlan show interfaces | Out-String
        if ($wifiConfig -match "BSSID\s+:\s+([0-9A-Fa-f:]{17})") {
            $bssid = $Matches[1]
        }
    } catch {}
}

# NOVO: Detecta se é Notebook
$isNotebook = $false
$chassisTypes = @(8, 9, 10, 11, 14, 18, 21, 31, 32) # Tipos de chassis que indicam notebook
$chassis = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes
foreach ($type in $chassis) {
    if ($chassisTypes -contains $type) {
        $isNotebook = $true
        break
    }
}

# Java e Browser
function Get-RegValue { param($path, $name) (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
$javaVersion = Get-RegValue -path "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment" -name "CurrentVersion"
if ($javaVersion) { $javaVersionPath = "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\$javaVersion"; $javaVersion = Get-RegValue -path $javaVersionPath -name "JavaVersion" }
$chromeVersion = (Get-RegValue -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -name "(default)" | Get-Item -ErrorAction SilentlyContinue).VersionInfo.ProductVersion

# Validação de Hostname e Serial
$hostname = $env:COMPUTERNAME
$serial = $bios.SerialNumber

if (-not $hostname -or $hostname.Trim() -eq "") {
    $hostname = $serial
}

if (-not $serial -or $serial.Trim() -eq "" -or $serial -match "000000" -or $serial -match "N/A") {
    $serial = $hostname
}

if (-not $hostname -or $hostname.Trim() -eq "") {
    $hostname = "HostDesconhecido"
}
if (-not $serial -or $serial.Trim() -eq "") {
    $serial = $hostname
}

# NOVO: Determina o tipo de conexão
$connectionType = if ($wifiAdapter -and $wifiAdapter.Status -eq "Up") { "WiFi" } 
                elseif ($ethernetAdapter) { "Ethernet" } 
                else { "Desconhecido" }

$data = [PSCustomObject]@{
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
    ip_address         = $net.IPAddress
    mac_address        = $mac
    mac_address_radio  = $bssid
    wifi_ssid          = $ssid
    wifi_signal        = $signalQuality
    connection_type    = $connectionType
    is_notebook        = $isNotebook
    antivirus_status   = $av.AntivirusEnabled
    antivirus_version  = $av.AMProductVersion
    is_encrypted       = if ($bitlocker -eq "On") { $true } else { $false }
    java_version       = $javaVersion
    browser_version    = "Chrome $chromeVersion"
}
$data | ConvertTo-Json -Depth 2

