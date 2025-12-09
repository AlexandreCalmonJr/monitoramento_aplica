import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_windows/utils/app_logger.dart';
import 'package:logger/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  final Logger _logger;
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  String? _serverUrl;
  bool _isDisposed = false;

  WebSocketService(this._logger);

  bool get isConnected => _isConnected;

  Future<void> connect(String serverUrl) async {
    _serverUrl = serverUrl;
    if (_isConnected && _channel != null) return;

    try {
      // Garante que a URL use o protocolo ws://
      final wsUrl = serverUrl.replaceFirst('http', 'ws');
      _logger.i('🔌 Tentando conectar WebSocket em $wsUrl/ws...');

      final uri = Uri.parse('$wsUrl/ws');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          if (!_isConnected) {
            _isConnected = true;
            _logger.i('✅ WebSocket conectado com sucesso!');
            _sendRegister();
            _startHeartbeat();
          }
          // Processar mensagens recebidas se necessário
        },
        onError: (error) {
          _logger.e('❌ WebSocket error: $error');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          _logger.w('🔌 WebSocket desconectado.');
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _logger.e('❌ Falha ao iniciar conexão WebSocket: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _sendRegister() {
    if (_isConnected) {
      final hostname = Platform.localHostname;
      final os = Platform.operatingSystem;

      try {
        _channel?.sink.add(
          json.encode({
            'type': 'register',
            'hostname': hostname,
            'platform': os,
          }),
        );
      } catch (e) {
        _logger.e('Erro ao enviar registro: $e');
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        try {
          _channel?.sink.add(json.encode({'type': 'heartbeat'}));
        } catch (e) {
          _logger.e('Erro ao enviar heartbeat: $e');
        }
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;

    _heartbeatTimer?.cancel();
    if (_reconnectTimer?.isActive ?? false) return;

    _logger.i('🔄 Tentando reconectar WebSocket em 10 segundos...');
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_serverUrl != null) {
        connect(_serverUrl!);
      }
    });
  }

  Future<void> sendShutdownSignal() async {
    if (_isConnected) {
      _logger.w('🛑 Enviando sinal de SHUTDOWN...');
      final hostname = Platform.localHostname;
      try {
        _channel?.sink.add(
          json.encode({'type': 'shutdown', 'hostname': hostname}),
        );
        // Aguarda um pouco para garantir o envio
        await Future.delayed(const Duration(milliseconds: 500));
        await _channel?.sink.close();
      } catch (e) {
        _logger.e('Erro ao enviar shutdown: $e');
      }
      _isConnected = false;
    }
  }

  void dispose() {
    _isDisposed = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }
}
