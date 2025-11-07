import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class LocalCacheService {
  final Logger _logger;
  final String _cacheDir = 'cache';

  LocalCacheService(this._logger);

  /// Salva dados localmente quando o envio falha
  Future<void> cacheFailedPayload(Map<String, dynamic> payload) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('$_cacheDir/payload_$timestamp.json');
      await file.create(recursive: true);
      await file.writeAsString(json.encode(payload));
      _logger.i('💾 Payload salvo no cache: ${file.path}');
    } catch (e) {
      _logger.e('Erro ao salvar cache: $e');
    }
  }

  /// Envia dados em cache quando a conexão é restabelecida
  Future<void> syncCachedData(String serverUrl, String token) async {
    try {
      final dir = Directory(_cacheDir);
      if (!await dir.exists()) return;

      final files = dir.listSync().whereType<File>().toList();
      if (files.isNotEmpty) {
        _logger.i('🔄 Sincronizando ${files.length} payloads em cache...');
      }

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final payload = json.decode(content);

          // Tenta enviar
          final response = await http
              .post(
                Uri.parse('$serverUrl/api/modules/${payload['moduleId']}/assets'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json'
                },
                body: json.encode(payload),
              )
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 200 || response.statusCode == 201) {
            await file.delete();
            _logger.i('✅ Payload em cache enviado com sucesso');
          }
        } catch (e) {
          _logger.w('⚠️ Falha ao enviar payload em cache: $e');
        }
      }
    } catch (e) {
      _logger.e('Erro ao sincronizar cache: $e');
    }
  }
}