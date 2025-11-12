// File: lib/utils/app_logger.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static late File _logFile;
  static late Logger logger;
  static final List<String> logHistory = [];
  static const int maxLogEntries = 1000;

  static Future<void> initialize() async {
    List<LogOutput> outputs = [];

    if (kDebugMode) {
      outputs.add(ConsoleOutput());
    } else {
      // Em modo Release, apenas loga no arquivo
    }

    // Adiciona o log em arquivo e na memória
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/agent_windows.log');
      
      // CORREÇÃO (Item 15): Testa a escrita
      await _logFile.writeAsString('--- Log inicializado em ${DateTime.now()} ---\n', mode: FileMode.append);
      
      outputs.add(FileOutput(file: _logFile));
      outputs.add(MemoryOutput(logHistory, maxLogEntries));
      
    } on FileSystemException catch (e) {
      debugPrint('Sem permissão para criar log: $e');
      // Continua só com memória
      outputs.add(MemoryOutput(logHistory, maxLogEntries));
    } catch (e) {
      debugPrint('Erro ao inicializar logger de arquivo: $e');
      outputs.add(MemoryOutput(logHistory, maxLogEntries));
    }

    logger = Logger(
      printer: PrettyPrinter(
        methodCount: 1,
        errorMethodCount: 5,
        lineLength: 100,
        colors: !kDebugMode, // Desativa cores no arquivo de log
        printEmojis: true,
        printTime: true,
      ),
      output: MultiOutput(outputs),
    );

    logger.i('Logger inicializado. Salvando em: ${_logFile.path}');
  }

  static Future<String> getLogContents() async {
    try {
      if (await _logFile.exists()) {
        return await _logFile.readAsString();
      }
      return "Arquivo de log não encontrado.";
    } catch (e) {
      return "Erro ao ler log: $e";
    }
  }

  static String getRecentLogs() {
    return logHistory.join('\n');
  }
}

// Outputs customizados para o Logger

class MemoryOutput extends LogOutput {
  final List<String> history;
  final int maxEntries;
  MemoryOutput(this.history, this.maxEntries);

  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      history.add(line);
      if (history.length > maxEntries) {
        history.removeAt(0);
      }
    }
  }
}