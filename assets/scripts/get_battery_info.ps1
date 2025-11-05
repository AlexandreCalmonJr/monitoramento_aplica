$battery = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue
if ($battery) {
  $level = $battery.EstimatedChargeRemaining
  $health = if ($battery.BatteryStatus -eq 2) { "Carregando" } else { "OK" }
  Write-Output "$level;$health"
}