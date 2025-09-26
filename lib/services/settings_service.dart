// Ficheiro: lib/services/settings_service.dart
// DESCRIÇÃO: Adicionada a lógica para guardar e carregar o intervalo de sincronização.

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  late SharedPreferences _prefs;
  String _ip = '';
  String _port = '';
  // NOVA VARIÁVEL para o intervalo
  int _intervalInSeconds = 60; // Valor padrão de 1 minuto

  String get ip => _ip;
  String get port => _port;
  // NOVO GETTER para o intervalo
  int get intervalInSeconds => _intervalInSeconds;

  Future<void> loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    _ip = _prefs.getString('server_ip') ?? '';
    _port = _prefs.getString('server_port') ?? '';
    // Carrega o intervalo guardado, ou usa 60 como padrão
    _intervalInSeconds = _prefs.getInt('server_interval') ?? 60;
  }

  // A função agora aceita o novo intervalo
  Future<void> saveSettings(String newIp, String newPort, int newInterval) async {
    _ip = newIp;
    _port = newPort;
    _intervalInSeconds = newInterval;
    await _prefs.setString('server_ip', _ip);
    await _prefs.setString('server_port', _port);
    // Guarda o novo intervalo
    await _prefs.setInt('server_interval', _intervalInSeconds);
  }
}

