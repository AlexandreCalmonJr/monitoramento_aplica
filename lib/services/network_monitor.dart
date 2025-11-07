import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

class NetworkMonitor {
  final Logger _logger;
  final Function() onNetworkChange;

  String? _lastIpAddress;
  String? _lastBssid;
  Timer? _timer;

  NetworkMonitor(this._logger, this.onNetworkChange);

  void startMonitoring() {
    _timer = Timer.periodic(Duration(minutes: 5), (_) => _checkNetworkChanges());
    _checkNetworkChanges(); // Verifica imediatamente
  }

  void stopMonitoring() {
    _timer?.cancel();
  }

  Future<void> _checkNetworkChanges() async {
    try {
      final currentIp = await _getCurrentIp();
      final currentBssid = await _getCurrentBssid();

      if (_lastIpAddress != null && _lastBssid != null) {
        if (currentIp != _lastIpAddress || currentBssid != _lastBssid) {
          _logger.i('🔄 MUDANÇA DE REDE DETECTADA');
          _logger.i('   IP: $_lastIpAddress → $currentIp');
          _logger.i('   BSSID: $_lastBssid → $currentBssid');

          // Notifica para executar sincronização imediata
          onNetworkChange();
        }
      }

      _lastIpAddress = currentIp;
      _lastBssid = currentBssid;
    } catch (e) {
      _logger.e('Erro ao monitorar rede: $e');
    }
  }

  Future<String> _getCurrentIp() async {
    final result = await Process.run('powershell', [
      '-Command',
      r'(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1).IPAddress'
    ]);
    return result.stdout.toString().trim();
  }

  Future<String> _getCurrentBssid() async {
  final result = await Process.run('powershell', [
    '-Command',
    // ADICIONE O 'r' AQUI TAMBÉM:
    r'netsh wlan show interfaces | Select-String "BSSID" | ForEach-Object {$_ -replace ".*: ",""}'
  ]);
  return result.stdout.toString().trim();
}
  

  Future<Map<String, String>> getNetworkInfo() async {
    final currentIp = await _getCurrentIp();
    final currentBssid = await _getCurrentBssid();
    return {
      'ip': currentIp,
      'bssid': currentBssid,
    };
  }
}