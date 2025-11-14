// File: lib/services/legacy_totem_service.dart (CORRIGIDO)
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class LegacyTotemService {
  final Logger _logger;

  static const String _notDetected = 'Não detectado';

  LegacyTotemService(this._logger);

  Future<bool> sendTotemData({
    required String serverUrl,
    required Map<String, dynamic> systemInfo, // Agora recebe o coreInfo
    required String token,
    String? sector,
    String? floor,
  }) async {
    try {
      // Monta o payload no formato esperado pelo backend legado
      final payload = _buildLegacyPayload(systemInfo, sector, floor);

      _logger.i('📤 Enviando dados para sistema legado de Totem...');
      _logger
          .d('   Payload: ${payload['serialNumber']} - ${payload['hostname']}');

      final response = await http
          .post(
            Uri.parse('$serverUrl/api/monitor'), // Rota /api/monitor
            headers: {
              'Content-Type': 'application/json',
              'AUTH_TOKEN': token, // Header de autenticação legado
            },
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final location = responseData['location'] ?? 'Desconhecida';

        _logger.i('✅ Dados enviados ao sistema legado com sucesso!');
        _logger.i('   Localização: $location');
        return true;
      } else {
        _logger
            .e('❌ Erro ao enviar para sistema legado: ${response.statusCode}');
        _logger.e('   Resposta: ${response.body}');
        return false;
      }
    } catch (e) {
      _logger.e('❌ Exceção ao enviar para sistema legado: $e');
      return false;
    }
  }

  /// Constrói o payload no formato do sistema legado de Totem
  Map<String, dynamic> _buildLegacyPayload(
    Map<String, dynamic> systemInfo, // Este é o coreInfo
    String? sector,
    String? floor,
  ) {
    // Extrai os status dos periféricos (que vêm como "Zebra / Bematech")
    final peripherals =
        (systemInfo['connected_printer'] ?? 'N/A / N/A').split('/');
    final zebraStatus =
        (peripherals.length > 0 ? peripherals[0].trim() : 'N/A');
    final bematechStatus =
        (peripherals.length > 1 ? peripherals[1].trim() : 'N/A');

    return {
      // Campos do modelo Totem
      'hostname': systemInfo['hostname'] ?? 'Unknown',
      'serialNumber': systemInfo['serial_number'] ?? 'Unknown',
      'model': systemInfo['model'] ?? 'N/A',
      'serviceTag':
          systemInfo['serial_number'] ?? 'N/A', // Usa serial como fallback
      'ip': systemInfo['ip_address'] ?? 'N/A',
      'macAddress': systemInfo['mac_address'] ?? 'N/A', // ✅ CORRIGIDO

      'installedPrograms': systemInfo['installed_software'] ?? [],

      'biometricReaderStatus': systemInfo['biometric_reader'] ?? _notDetected,
      'zebraStatus': zebraStatus, // ✅ CORRIGIDO
      'bematechStatus': bematechStatus, // ✅ CORRIGIDO

      // Infere o tipo (lógica movida para cá)
      'totemType': _inferTotemType(
          systemInfo['biometric_reader'], zebraStatus, bematechStatus),

      'ram': systemInfo['ram'] ?? 'N/A',
      'hdType': systemInfo['storage_type'] ?? 'N/A',
      'hdStorage': systemInfo['storage'] ?? 'N/A',

      'sector': sector ?? 'N/A',
      'floor': floor ?? 'N/A',

      // Campos que o modelo totem.dart não usa, mas o legacy_totem_service esperava
      'printerStatus': systemInfo['connected_printer'] ?? 'N/A',
    };
  }

  String _inferTotemType(String? biometric, String? zebra, String? bematech) {
    final hasBiometric = biometric != null && biometric != _notDetected;
    final hasPrinter = (zebra != null && zebra != _notDetected) ||
        (bematech != null && bematech != _notDetected);

    if (hasBiometric && hasPrinter) {
      return 'Totem Completo';
    } else if (hasBiometric) {
      return 'Totem com Biometria';
    } else if (hasPrinter) {
      return 'Totem com Impressora';
    } else {
      return 'Desktop/Workstation';
    }
  }
}
