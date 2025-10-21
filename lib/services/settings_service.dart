// File: lib/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  late String ip;
  late String port;
  late int interval;
  late String moduleId;
  late String sector;
  late String floor;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ip = prefs.getString('server_ip') ?? '';
    port = prefs.getString('server_port') ?? '';
    interval = prefs.getInt('sync_interval') ?? 300; // Padrão de 5 minutos
    moduleId = prefs.getString('module_id') ?? '';
    sector = prefs.getString('manual_sector') ?? '';
    floor = prefs.getString('manual_floor') ?? '';
  }

  Future<void> saveSettings({
    required String newIp,
    required String newPort,
    required int newInterval,
    required String newModuleId,
    required String newSector,
    required String newFloor,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp);
    await prefs.setString('server_port', newPort);
    await prefs.setInt('sync_interval', newInterval);
    await prefs.setString('module_id', newModuleId);
    await prefs.setString('manual_sector', newSector);
    await prefs.setString('manual_floor', newFloor);
    
    // Atualiza as variáveis locais
    ip = newIp;
    port = newPort;
    interval = newInterval;
    moduleId = newModuleId;
    sector = newSector;
    floor = newFloor;
  }
}