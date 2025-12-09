// File: lib/services/command_executor_service.dart (CLIENTE WINDOWS)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class CommandExecutorService {
  final Logger _logger;
  final AuthService _authService;
  Timer? _pollingTimer;
  bool _isExecuting = false;

  CommandExecutorService(this._logger, this._authService, SettingsService settingsService);

  /// Inicia o polling de comandos (chamado periodicamente)
  void startCommandPolling({
    required String serverUrl,
    required String moduleId,
    required String serialNumber,
    Duration interval = const Duration(seconds: 30),
  }) {
    _logger
        .i('🔄 Iniciando polling de comandos (a cada ${interval.inSeconds}s)');

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (timer) async {
      if (!_isExecuting) {
        await _checkAndExecuteCommands(serverUrl, moduleId, serialNumber);
      }
    });
  }

  void stopCommandPolling() {
    _pollingTimer?.cancel();
    _logger.i('⏸️ Polling de comandos interrompido');
  }

  /// Verifica e executa comandos pendentes
  Future<void> _checkAndExecuteCommands(
    String serverUrl,
    String moduleId,
    String serialNumber,
  ) async {
    if (_isExecuting) return;
    _isExecuting = true;

    try {
      final commands = await _fetchPendingCommands(
        serverUrl,
        moduleId,
        serialNumber,
      );

      if (commands.isEmpty) {
        _logger.d('✅ Nenhum comando pendente');
        return;
      }

      _logger.i('📥 ${commands.length} comando(s) recebido(s)');

      for (final command in commands) {
        await _executeCommand(serverUrl, moduleId, command);
      }
    } catch (e) {
      _logger.e('❌ Erro ao verificar comandos: $e');
    } finally {
      _isExecuting = false;
    }
  }

  /// Busca comandos pendentes no servidor
  Future<List<Map<String, dynamic>>> _fetchPendingCommands(
    String serverUrl,
    String moduleId,
    String serialNumber,
  ) async {
    try {
      final uri = Uri.parse(
        '$serverUrl/api/modules/$moduleId/assets/commands/pending?serialNumber=$serialNumber',
      );

      final response = await http
          .get(
            uri,
            headers: _authService.getHeaders(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['commands'] ?? []);
      } else {
        _logger.w('⚠️ Erro ao buscar comandos: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _logger.e('❌ Erro na requisição de comandos: $e');
      return [];
    }
  }

  /// Executa um comando e reporta o resultado
  Future<void> _executeCommand(
    String serverUrl,
    String moduleId,
    Map<String, dynamic> command,
  ) async {
    final commandId = command['id'];
    final commandType = command['commandType'];
    final commandText = command['command'];
    final requiresElevation = command['requiresElevation'] ?? false;
    final timeout = command['timeout'] ?? 60000;

    _logger.i('⚙️ Executando comando: $commandType');
    _logger.d('   Comando: $commandText');
    _logger.d('   Admin: $requiresElevation | Timeout: ${timeout}ms');

    final stopwatch = Stopwatch()..start();
    String stdout = '';
    String stderr = '';
    int exitCode = -1;
    bool success = false;

    try {
      // Executa o comando
      final result = await _runCommand(
        commandText,
        requiresElevation: requiresElevation,
        timeout: Duration(milliseconds: timeout),
      );

      stdout = result['stdout'] ?? '';
      stderr = result['stderr'] ?? '';
      exitCode = result['exitCode'] ?? -1;
      success = exitCode == 0;

      stopwatch.stop();

      _logger.i(
        success ? '✅ Comando executado com sucesso' : '❌ Comando falhou',
      );
      if (stdout.isNotEmpty) {
        _logger.d(
            '   STDOUT: ${stdout.substring(0, stdout.length > 200 ? 200 : stdout.length)}...');
      }
      if (stderr.isNotEmpty) _logger.w('   STDERR: $stderr');
    } catch (e) {
      stopwatch.stop();
      stderr = 'Erro de execução: ${e.toString()}';
      _logger.e('❌ Exceção ao executar comando: $e');
    }

    // Reporta o resultado ao servidor
    await _reportCommandResult(
      serverUrl,
      moduleId,
      commandId,
      success: success,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      executionTime: stopwatch.elapsedMilliseconds,
    );
  }

  /// Executa comando no sistema operacional
  Future<Map<String, dynamic>> _runCommand(
    String command, {
    bool requiresElevation = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      ProcessResult result;

      if (requiresElevation) {
        // Tenta executar como administrador (usando RunAs)
        _logger.d('🔐 Executando com privilégios elevados...');

        // Cria um script temporário
        final tempDir = Directory.systemTemp;
        final scriptFile = File(
            '${tempDir.path}\\temp_command_${DateTime.now().millisecondsSinceEpoch}.bat');

        await scriptFile.writeAsString('@echo off\n$command\n', flush: true);

        result = await Process.run(
          'powershell',
          [
            '-Command',
            'Start-Process',
            '-FilePath',
            '"${scriptFile.path}"',
            '-Verb',
            'RunAs',
            '-Wait'
          ],
          runInShell: true,
        ).timeout(timeout);

        // Limpa o script temporário
        try {
          await scriptFile.delete();
        } catch (_) {}
      } else {
        // Executa normalmente
        result = await Process.run(
          'cmd',
          ['/c', command],
          runInShell: true,
        ).timeout(timeout);
      }

      return {
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
        'exitCode': result.exitCode,
      };
    } on TimeoutException {
      return {
        'stdout': '',
        'stderr': 'Comando excedeu o tempo limite',
        'exitCode': -2,
      };
    } catch (e) {
      return {
        'stdout': '',
        'stderr': 'Erro: ${e.toString()}',
        'exitCode': -1,
      };
    }
  }

  /// Reporta o resultado do comando ao servidor
  Future<void> _reportCommandResult(
    String serverUrl,
    String moduleId,
    String commandId, {
    required bool success,
    required String stdout,
    required String stderr,
    required int exitCode,
    required int executionTime,
  }) async {
    try {
      final uri = Uri.parse(
        '$serverUrl/api/modules/$moduleId/assets/commands/$commandId/result',
      );

      final body = {
        'success': success,
        'stdout': stdout.length > 5000 ? stdout.substring(0, 5000) : stdout,
        'stderr': stderr.length > 2000 ? stderr.substring(0, 2000) : stderr,
        'exitCode': exitCode,
        'executionTime': executionTime,
      };

      final response = await http
          .post(
            uri,
            headers: {
              ..._authService.getHeaders(),
              'Content-Type': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _logger.i('✅ Resultado reportado ao servidor');
      } else {
        _logger.w('⚠️ Falha ao reportar resultado: ${response.statusCode}');
      }
    } catch (e) {
      _logger.e('❌ Erro ao reportar resultado: $e');
    }
  }
}
