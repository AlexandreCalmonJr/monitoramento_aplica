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