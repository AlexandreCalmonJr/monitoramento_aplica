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
  
  /// CORREÇÃO (Item 7): Nome manual do ativo. Se vazio, usa hostname automaticamente.
  late String assetName; 
  late bool forceLegacyMode; // <-- ADIÇÃO 1

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
    assetName = prefs.getString('asset_name') ?? ''; //
    forceLegacyMode = prefs.getBool('forceLegacyMode') ?? false; // <-- ADIÇÃO 2
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
    required String newAssetName, //
    required bool newForceLegacyMode, // <-- ADIÇÃO 3
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', newIp);
    await prefs.setString('server_port', newPort);
    await prefs.setInt('sync_interval', newInterval);
    await prefs.setString('module_id', newModuleId);
    await prefs.setString('manual_sector', newSector);
    await prefs.setString('manual_floor', newFloor);
    await prefs.setString('auth_token', newToken); 
    await prefs.setString('asset_name', newAssetName); //
    await prefs.setBool('forceLegacyMode', newForceLegacyMode); // <-- ADIÇÃO 4
    
    // Atualiza as variáveis locais
    ip = newIp;
    port = newPort;
    interval = newInterval;
    moduleId = newModuleId;
    sector = newSector;
    floor = newFloor;
    token = newToken;
    assetName = newAssetName; //
    forceLegacyMode = newForceLegacyMode; // <-- ADIÇÃO 5
    
    _logger.i('Configurações salvas: Módulo $newModuleId, Servidor $newIp:$newPort');
  }

  // --- CORREÇÃO (Item 9): MÉTODO PARA SALVAR APENAS O MODO LEGADO ---
  // Este método é usado pela settings_screen.dart
  Future<void> saveForceLegacyMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('forceLegacyMode', value);
    forceLegacyMode = value; // Atualiza a variável local
    _logger.i('Modo legado forçado salvo: $value');
  }
  // --- FIM DA CORREÇÃO ---
}