// Ficheiro: lib/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  late String ip;
  late String port;
  late String totemType; // NOVO: Variável para o tipo de totem
  late int interval;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ip = prefs.getString('ip') ?? '';
    port = prefs.getString('port') ?? '';
    totemType = prefs.getString('totemType') ?? 'N/A'; // NOVO: Carrega o tipo de totem
    interval = prefs.getInt('interval') ?? 60; // Padrão de 1 minuto
  }

  Future<void> saveSettings(String newIp, String newPort, String newTotemType, int newInterval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', newIp);
    await prefs.setString('port', newPort);
    await prefs.setString('totemType', newTotemType); // NOVO: Guarda o tipo de totem
    await prefs.setInt('interval', newInterval);
    ip = newIp;
    port = newPort;
    totemType = newTotemType;
    interval = newInterval;
  }
}