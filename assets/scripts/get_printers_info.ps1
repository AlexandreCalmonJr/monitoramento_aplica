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