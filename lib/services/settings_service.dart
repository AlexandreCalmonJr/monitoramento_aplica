// File: lib/services/settings_service.dart
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  final Logger _logger;

  late String ip;
  late String port;
  late int interval;
  late String moduleId;
  late String sector;
  late String floor;
  late String token;
  late String assetName; // <-- NOVO

  SettingsService(this._logger) {
    _logger.i('SettingsService inicializado');
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ip = prefs.getString('server_ip') ?? '';
    port = prefs.getString('server_port') ?? '';
    interval = prefs.getInt('sync_interval') ?? 300; // Padrão de 5 minutos
    moduleId = prefs.getString('module_id') ?? '';
    sector = prefs.getString('manual_sector') ?? '';
    floor = prefs.getString('manual_floor') ?? '';
    token = prefs.getString('auth_token') ?? '';
    assetName = prefs.getString('asset_name') ?? ''; // <-- NOVO
    _logger.d('Configurações carregadas');
  }

  Future<void> saveSettings({
    required String newIp,
    required String newPort,
    required int newInterval,
    required String newModuleId,
    required String newSector,
    required String newFloor,
    required String newToken,
    required String newAssetName, // <-- NOVO
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp);
    await prefs.setString('server_port', newPort);
    await prefs.setInt('sync_interval', newInterval);
    await prefs.setString('module_id', newModuleId);
    await prefs.setString('manual_sector', newSector);
    await prefs.setString('manual_floor', newFloor);
    await prefs.setString('auth_token', newToken); 
    await prefs.setString('asset_name', newAssetName); // <-- NOVO
    
    // Atualiza as variáveis locais
    ip = newIp;
    port = newPort;
    interval = newInterval;
    moduleId = newModuleId;
    sector = newSector;
    floor = newFloor;
    token = newToken;
    assetName = newAssetName; // <-- NOVO
    
    _logger.i('Configurações salvas: Módulo $newModuleId, Servidor $newIp:$newPort');
  }
}