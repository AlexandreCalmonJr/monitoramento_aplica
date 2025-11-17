# get_core_system_info.ps1
# VERSÃO: NOMES REAIS DE IMPRESSORAS (FIM DO "N" E "A")
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# --- Funções Auxiliares ---
function Get-RegValue { param($path, $name) try { (Get-ItemProperty -Path $path -Name $name).$name } catch { $null } }

# --- 1. UPTIME ---
$uptime = "0d 0h 0m"
try {
    $osObj = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($osObj.LastBootUpTime) {
        $timeSpan = (Get-Date) - $osObj.LastBootUpTime
        $uptime = "$($timeSpan.Days)d $($timeSpan.Hours)h $($timeSpan.Minutes)m"
    }
} catch { $uptime = "N/A" }

# --- 2. Hardware ---
$model = "N/A"; $manufacturer = "N/A"; $processor = "N/A"; $ram = "N/A"
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object Model, Manufacturer, TotalPhysicalMemory
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object Name
    if ($cs.Model) { $model = $cs.Model.Trim() }
    if ($cs.Manufacturer) { $manufacturer = $cs.Manufacturer.Trim() }
    if ($cs.TotalPhysicalMemory) { $ram = "$([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB" }
    if ($cpu.Name) { $processor = $cpu.Name.Trim() }
} catch {
    $regSystem = "HKLM:\HARDWARE\DESCRIPTION\System\BIOS"
    $regCpu = "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0"
    if ($model -eq "N/A") { $model = Get-RegValue $regSystem "SystemProductName" }
    if ($manufacturer -eq "N/A") { $manufacturer = Get-RegValue $regSystem "SystemManufacturer" }
    if ($processor -eq "N/A") { $processor = Get-RegValue $regCpu "ProcessorNameString" }
}
if ($processor -eq "N/A") { $processor = $env:PROCESSOR_IDENTIFIER }

# --- 3. Armazenamento ---
$storage = "N/A"; $storageType = "N/A"
try {
    $volC = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($volC) { $storage = "$([math]::Round($volC.Size / 1GB, 2)) GB" }
    $disk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq 0 }
    if ($disk) { $storageType = $disk.MediaType }
} catch {}

# --- 4. Sistema Operacional ---
$osName = "Windows"; $osVersion = "N/A"
try {
    if ($osObj) { $osName = $osObj.Caption; $osVersion = $osObj.Version }
    else { 
        $osName = (Get-CimInstance Win32_OperatingSystem).Caption
        $osVersion = (Get-CimInstance Win32_OperatingSystem).Version 
    }
} catch {}

# --- 5. Rede ---
$ipAddress = "N/A"; $macAddress = "N/A"; $bssid = "N/A"; $ssid = "N/A"; $signal = 0 
try {
    $activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object LinkSpeed -Descending | Select-Object -First 1
    if ($activeAdapter) {
        $macAddress = $activeAdapter.MacAddress
        $ipInfo = Get-NetIPAddress -InterfaceIndex $activeAdapter.InterfaceIndex -AddressFamily IPv4
        if ($ipInfo) { $ipAddress = $ipInfo.IPAddress }
        if ($activeAdapter.MediaType -match "802.11|Wireless") {
             $wifiStatus = netsh wlan show interfaces
             if ($wifiStatus -match "BSSID\s*:\s*([a-fA-F0-9:]+)") { $bssid = $Matches[1].Trim() }
             if ($wifiStatus -match "SSID\s*:\s*(.+)") { $ssid = $Matches[1].Trim() }
             if ($wifiStatus -match "Sinal\s*:\s*(\d+)%") { $signal = [int]$Matches[1] }
        }
    }
} catch {}

# --- 6. Bateria ---
$batteryLevel = $null; $isNotebook = $false
try {
    $battery = Get-WmiObject Win32_Battery -ErrorAction Stop
    if ($battery) { $batteryLevel = $battery.EstimatedChargeRemaining; $isNotebook = $true }
} catch {}
if (-not $isNotebook) {
    try {
        $chassis = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
        if ($chassis -contains 9 -or $chassis -contains 10) { $isNotebook = $true }
    } catch {}
}

# --- 7. IMPRESSORAS: LOGICA AVANÇADA ---
$zebraInfo = "Não Instalada"
$bematechInfo = "Não Instalada"
$defaultPrinterName = "Nenhuma Padrão"
$totemType = "Administrativo/Outro"

try {
    $allPrinters = Get-Printer -ErrorAction SilentlyContinue
    
    # 1. Impressora Padrão (Tenta WMI primeiro, depois Get-Printer)
    $wmiDefault = Get-CimInstance -ClassName Win32_Printer | Where-Object Default -eq $true | Select-Object -First 1
    if ($wmiDefault) { 
        $defaultPrinterName = $wmiDefault.Name 
    } else {
        # Fallback
        $psDefault = $allPrinters | Where-Object Type -eq "Local" | Select-Object -First 1
        if ($psDefault) { $defaultPrinterName = $psDefault.Name }
    }

    # 2. ZEBRA (Procura por Zebra ou ZDesigner)
    $zebraObj = $allPrinters | Where-Object { $_.Name -match "Zebra|ZDesigner|ZD" } | Select-Object -First 1
    $hasZebra = $false
    if ($zebraObj) {
        $hasZebra = $true
        # Traduz Status Code
        $st = "Desconhecido"
        if ($zebraObj.PrinterStatus -eq "Normal" -or $zebraObj.PrinterStatus -eq "Idle") { $st = "Pronta" }
        elseif ($zebraObj.PrinterStatus -eq "Offline") { $st = "Offline" }
        elseif ($zebraObj.PrinterStatus -eq "Error") { $st = "Erro" }
        else { $st = $zebraObj.PrinterStatus }
        
        $zebraInfo = "$($zebraObj.Name) ($st)"
    }

    # 3. BEMATECH (Procura por Bematech ou MP-4200)
    $bemaObj = $allPrinters | Where-Object { $_.Name -match "Bematech|MP-4200|MP4200" } | Select-Object -First 1
    $hasBematech = $false
    if ($bemaObj) {
        $hasBematech = $true
        $st = "Desconhecido"
        if ($bemaObj.PrinterStatus -eq "Normal" -or $bemaObj.PrinterStatus -eq "Idle") { $st = "Pronta" }
        elseif ($bemaObj.PrinterStatus -eq "Offline") { $st = "Offline" }
        elseif ($bemaObj.PrinterStatus -eq "Error") { $st = "Erro" }
        else { $st = $bemaObj.PrinterStatus }
        
        $bematechInfo = "$($bemaObj.Name) ($st)"
    }

    # 4. DEFINIÇÃO DE TIPO (REGRA DE NEGÓCIO)
    if ($hasZebra) {
        # Se tem Zebra (mesmo com Bematech junto) -> Emergência
        $totemType = "Emergência"
    } elseif ($hasBematech) {
        # Se tem SÓ Bematech (sem Zebra) -> Fiscal
        $totemType = "Fiscal"
    }

} catch {
    $defaultPrinterName = "Erro na detecção"
    $zebraInfo = "Erro"
    $bematechInfo = "Erro"
}

# --- 8. Leitor Biométrico ---
$biometricStatus = "Não detectado"
try {
    $bio = Get-PnpDevice -Class "Biometric" -Status OK -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bio) { $biometricStatus = "Conectado" }
} catch {}

# --- 9. AUDITORIA DE APPS ---
$programsList = @()
$hasNdd = $false
$hasCortex = $false
$hasCapturaBio = $false
$hasAutomatos = $false

try {
    $keys = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $rawPrograms = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ne $null }

    # Verifica com regex (match case insensitive)
    $hasNdd = ($rawPrograms.DisplayName -match "NDD|PrintClient").Count -gt 0
    $hasCortex = ($rawPrograms.DisplayName -match "Cortex|Palo Alto").Count -gt 0
    $hasCapturaBio = ($rawPrograms.DisplayName -match "CapturaBio").Count -gt 0
    $hasAutomatos = ($rawPrograms.DisplayName -match "Automatos").Count -gt 0

    $programsList = $rawPrograms | 
        Select-Object @{N="Name";E={$_.DisplayName}}, @{N="Version";E={$_.DisplayVersion}} | 
        Sort-Object -Unique Name | 
        ForEach-Object { "$($_.Name) v$($_.Version)" }
} catch {}

# --- 10. Saída JSON ---
$hostname = $env:COMPUTERNAME
$currentUser = $env:USERNAME
$serial = (Get-CimInstance Win32_BIOS).SerialNumber
if (-not $serial -or $serial -match "000000|To be filled") { $serial = $hostname }

$data = [PSCustomObject]@{
    hostname = $hostname
    serial_number = $serial
    asset_name = $hostname
    uptime = $uptime
    
    model = $model
    processor = $processor
    ram = $ram
    storage = $storage
    
    ip_address = $ipAddress
    mac_address = $macAddress
    wifi_ssid = $ssid
    wifi_signal = $signal
    battery_level = $batteryLevel 
    
    # --- Campos Solicitados ---
    totem_type = $totemType            # "Emergência" / "Fiscal"
    printerStatus = $defaultPrinterName # Nome da Impressora Padrão
    zebraStatus = $zebraInfo           # Ex: "ZDesigner TLP (Pronta)" (NÃO MAIS "N" ou "A")
    bematechStatus = $bematechInfo     # Ex: "Bematech MP-4200 (Offline)"
    biometricReaderStatus = $biometricStatus
    
    # --- Auditoria de Apps ---
    app_ndd_installed = $hasNdd
    app_cortex_installed = $hasCortex
    app_capturabio_installed = $hasCapturaBio
    app_automatos_installed = $hasAutomatos
    
    installed_software = $programsList
    last_seen = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    current_user = $currentUser
}

$data | ConvertTo-Json -Depth 3 -Compress