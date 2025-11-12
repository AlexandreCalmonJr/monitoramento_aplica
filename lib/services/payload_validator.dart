class PayloadValidator {
  static ValidationResult validate(
      Map<String, dynamic> payload, String moduleType) {
    final errors = <String>[];
    final warnings = <String>[];

    // Validações Obrigatórias
    // CORREÇÃO (Item 5): Validação de serial movida para cá
    if (!_hasValidValue(payload['serial_number'])) {
      errors.add('Serial number inválido ou ausente');
    }

    if (!_hasValidValue(payload['asset_name'])) {
      errors.add('Asset name inválido ou ausente');
    }

    if (!_hasValidValue(payload['hostname'])) {
      warnings.add('Hostname ausente - usando fallback');
      payload['hostname'] = payload['asset_name'] ?? 'UNKNOWN';
    }

    // Validações Específicas por Tipo
    switch (moduleType.toLowerCase()) {
      case 'notebook':
        if (!_hasValidValue(payload['battery_level'])) {
          warnings
              .add('Nível de bateria não detectado (esperado para notebooks)');
        }
        if (!_hasValidValue(payload['mac_address_radio'])) {
          warnings.add('BSSID não detectado - localização WiFi indisponível');
        }
        break;

      case 'desktop':
        if (!_hasValidValue(payload['biometric_reader'])) {
          warnings.add('Status do leitor biométrico não detectado');
        }
        break;

      case 'printer':
        if (!_hasValidValue(payload['printer_status'])) {
          errors.add('Status da impressora obrigatório');
        }
        break;
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  static bool _hasValidValue(dynamic value) {
    if (value == null) return false;
    final str = value.toString().trim();

    if (str.isEmpty || str == 'N/A' || str.toLowerCase() == 'null') {
      return false;
    }

    // CORREÇÃO (Item 17): Ser mais específico
    // Só considera inválido se for EXATAMENTE "000000..." ou "00:00:00:..."
    if (RegExp(r'^(0+|0+:0+:0+.*)$').hasMatch(str)) {
      return false;
    }

    return true;
  }
}

class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });
}