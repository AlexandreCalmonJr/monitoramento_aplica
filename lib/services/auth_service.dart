// File: lib/services/auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Construtor público
  AuthService() {
    debugPrint('AuthService inicializado');
  }

  String? _jwtToken;
  String? _legacyToken;
  DateTime? _tokenExpiry;

  /// Verifica se o token JWT está válido
  bool get hasValidJWT {
    if (_jwtToken == null || _tokenExpiry == null) return false;
    return DateTime.now().isBefore(_tokenExpiry!);
  }

  /// Retorna o token apropriado para uso
  String? get token => _jwtToken ?? _legacyToken;

  Null get currentToken => null;

  /// Carrega tokens salvos
  Future<void> loadTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _jwtToken = prefs.getString('jwt_token');
      _legacyToken = prefs.getString('legacy_token');
      
      final expiryString = prefs.getString('token_expiry');
      if (expiryString != null) {
        _tokenExpiry = DateTime.tryParse(expiryString);
      }
      
      debugPrint('🔑 Tokens carregados:');
      debugPrint('   JWT: ${_jwtToken != null ? "Presente" : "Ausente"}');
      debugPrint('   Legacy: ${_legacyToken != null ? "Presente" : "Ausente"}');
      debugPrint('   Expira: $_tokenExpiry');
    } catch (e) {
      debugPrint('❌ Erro ao carregar tokens: $e');
    }
  }

  /// Salva o Legacy Token (AUTH_TOKEN do .env)
  Future<void> saveLegacyToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('legacy_token', token);
      _legacyToken = token;
      debugPrint('✅ Legacy token salvo');
    } catch (e) {
      debugPrint('❌ Erro ao salvar legacy token: $e');
    }
  }

  /// Salva o JWT Token
  Future<void> saveJWTToken(String token, Duration validity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiry = DateTime.now().add(validity);
      
      await prefs.setString('jwt_token', token);
      await prefs.setString('token_expiry', expiry.toIso8601String());
      
      _jwtToken = token;
      _tokenExpiry = expiry;
      
      debugPrint('✅ JWT token salvo (expira: $expiry)');
    } catch (e) {
      debugPrint('❌ Erro ao salvar JWT token: $e');
    }
  }

  /// Limpa todos os tokens
  Future<void> clearTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('legacy_token');
      await prefs.remove('token_expiry');
      
      _jwtToken = null;
      _legacyToken = null;
      _tokenExpiry = null;
      
      debugPrint('🗑️  Tokens limpos');
    } catch (e) {
      debugPrint('❌ Erro ao limpar tokens: $e');
    }
  }

  /// Tenta fazer login e obter um JWT
  /// (OPCIONAL: Caso o servidor forneça um endpoint de login para agentes)
  Future<bool> loginWithLegacyToken({
    required String serverUrl,
    required String legacyToken,
  }) async {
    try {
      debugPrint('🔐 Tentando fazer login com Legacy Token...');
      
      // Salva o legacy token primeiro
      await saveLegacyToken(legacyToken);
      
      // NOTA: Este endpoint não existe ainda no servidor
      // Se você implementá-lo, descomente e ajuste
      /*
      final response = await http.post(
        Uri.parse('$serverUrl/api/auth/agent-login'),
        headers: {
          'Content-Type': 'application/json',
          'AUTH_TOKEN': legacyToken,
        },
        body: json.encode({'agent': true}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final jwtToken = data['token'];
        
        if (jwtToken != null) {
          await saveJWTToken(jwtToken, const Duration(days: 7));
          debugPrint('✅ JWT obtido com sucesso');
          return true;
        }
      }
      */
      
      // Por enquanto, retorna true se o legacy token foi salvo
      debugPrint('✅ Legacy token configurado (JWT não disponível)');
      return true;
      
    } catch (e) {
      debugPrint('❌ Erro no login: $e');
      return false;
    }
  }

  /// Retorna os headers apropriados para requisições
  Map<String, String> getHeaders() {
    // Prioriza JWT se disponível e válido
    if (hasValidJWT && _jwtToken != null) {
      debugPrint('🔑 Usando JWT token');
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_jwtToken',
      };
    }
    
    // Fallback para Legacy Token
    if (_legacyToken != null) {
      debugPrint('🔑 Usando Legacy token (AUTH_TOKEN)');
      return {
        'Content-Type': 'application/json',
        'AUTH_TOKEN': _legacyToken!,
      };
    }
    
    debugPrint('⚠️  Nenhum token disponível!');
    return {
      'Content-Type': 'application/json',
    };
  }

  /// Tenta renovar o JWT se estiver próximo de expirar
  Future<void> refreshTokenIfNeeded({
    required String serverUrl,
  }) async {
    if (_tokenExpiry == null) return;
    
    // Renova se faltar menos de 1 dia para expirar
    final renewThreshold = DateTime.now().add(const Duration(days: 1));
    
    if (_tokenExpiry!.isBefore(renewThreshold)) {
      debugPrint('🔄 Token próximo de expirar, tentando renovar...');
      
      if (_legacyToken != null) {
        await loginWithLegacyToken(
          serverUrl: serverUrl,
          legacyToken: _legacyToken!,
        );
      }
    }
  }
}