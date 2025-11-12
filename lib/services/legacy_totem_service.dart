// File: lib/services/legacy_totem_service.dart
// Descrição: Serviço para enviar dados ao sistema legado de Totem
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class LegacyTotemService {
  final Logger _logger;

  // CORREÇÃO (Item 19): Criar constante
  static const String _notDetected = 'Não detectado';

  LegacyTotemService(this._logger);

  /// Envia dados para o endpoint legado de Totem
  /// Rota: POST /api/monitor
  Future<bool> sendTotemData({
    required String serverUrl,
    required Map<String, dynamic> systemInfo,
    required String token, // ⬅️ ADICIONADO (Correto)
    String? sector,
    String? floor,
  }) async {
    try {
      // Monta o payload no formato esperado pelo backend legado
      final payload = _buildLegacyPayload(systemInfo, sector, floor);

      _logger.i('📤 Enviando dados para sistema legado de Totem...');
      _logger.d('   Payload: ${payload['serialNumber']} - ${payload['hostname']}');

      // ⬇️ MODIFICADO: Corrigido o endpoint e adicionado o token
      final response = await http.post(
        Uri.parse('$serverUrl/api/monitor'), // CORREÇÃO: Rota é /api/monitor
        headers: {
          'Content-Type': 'application/json',
          'AUTH_TOKEN': token, // ⬅️ Header de autenticação legado (Correto)
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final location = responseData['location'] ?? 'Desconhecida';
        
        _logger.i('✅ Dados enviados ao sistema legado com sucesso!');
        _logger.i('   Localização: $location');
        return true;
      } else {
        _logger.e('❌ Erro ao enviar para sistema legado: ${response.statusCode}');
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
    Map<String, dynamic> systemInfo,
    String? sector,
    String? floor,
  ) {
    return {
      // Campos obrigatórios do modelo Totem.js
      'hostname': systemInfo['hostname'] ?? 'Unknown',
      'serialNumber': systemInfo['serial_number'] ?? 'Unknown',
      
      // Campos opcionais (com valores padrão)
      'model': systemInfo['model'] ?? 'N/A',
      'serviceTag': systemInfo['service_tag'] ?? 'N/A',
      'ip': systemInfo['ip_address'] ?? 'N/A',
      
      // Programas instalados
      'installedPrograms': systemInfo['installed_software'] ?? [],
      
      // Status de periféricos (se disponíveis)
      'printerStatus': _extractPrinterStatus(systemInfo),
      'biometricReaderStatus': _extractBiometricStatus(systemInfo),
      'zebraStatus': _extractPeripheralStatus(systemInfo, 'zebra'),
      'bematechStatus': _extractPeripheralStatus(systemInfo, 'bematech'),
      
      // Tipo de totem (inferido do tipo de dispositivo)
      'totemType': _inferTotemType(systemInfo),
      
      // Especificações de hardware
      'ram': systemInfo['ram'] ?? 'N/A',
      'hdType': systemInfo['storage_type'] ?? 'N/A',
      'hdStorage': systemInfo['storage'] ?? 'N/A',
      
      // Dados customizados (setor e andar)
      'sector': sector ?? 'N/A',
      'floor': floor ?? 'N/A',
    };
  }

  /// Extrai status da impressora dos dados do sistema
  String _extractPrinterStatus(Map<String, dynamic> systemInfo) {
    final connectedPrinter = systemInfo['connected_printer'];
    // CORREÇÃO (Item 19): Usar constante
    if (connectedPrinter != null && connectedPrinter != _notDetected) {
      return connectedPrinter.toString();
    }
    return 'N/A';
  }

  /// Extrai status do leitor biométrico
  String _extractBiometricStatus(Map<String, dynamic> systemInfo) {
    final biometric = systemInfo['biometric_reader'];
    // CORREÇÃO (Item 19): Usar constante
    if (biometric != null && biometric != _notDetected) {
      return biometric.toString();
    }
    return 'N/A';
  }

  /// Extrai status de periférico específico
  String _extractPeripheralStatus(Map<String, dynamic> systemInfo, String peripheral) {
    // Tenta extrair do campo connected_printer que pode conter "zebra / bematech"
    final connectedPrinter = systemInfo['connected_printer']?.toString() ?? '';
    
    if (connectedPrinter.toLowerCase().contains(peripheral.toLowerCase())) {
      final parts = connectedPrinter.split('/');
      for (var part in parts) {
        if (part.toLowerCase().contains(peripheral.toLowerCase())) {
          return part.trim();
        }
      }
    }
    return 'N/A';
  }

  /// Infere o tipo de totem baseado nas características do dispositivo
  String _inferTotemType(Map<String, dynamic> systemInfo) {
    // Verifica se tem biométrico
    // CORREÇÃO (Item 19): Usar constante
    final hasBiometric = systemInfo['biometric_reader'] != null &&
        systemInfo['biometric_reader'] != _notDetected;
    
    // Verifica se tem impressora zebra/bematech
    // CORREÇÃO (Item 19): Usar constante
    final hasPrinter = systemInfo['connected_printer'] != null &&
        systemInfo['connected_printer'] != _notDetected;
    
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