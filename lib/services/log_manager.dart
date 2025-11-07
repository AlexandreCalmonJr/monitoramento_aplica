import 'dart:io';

class LogManager {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final List<LogEntry> _logs = [];
  final int _maxLogs = 1000;

  void addLog(LogEntry entry) {
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  /// Exporta logs para arquivo
  Future<String> exportLogs() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('logs/agent_logs_$timestamp.txt');
    await file.create(recursive: true);

    final buffer = StringBuffer();
    buffer.writeln('=== AGENT WINDOWS LOGS ===');
    buffer.writeln('Gerado em: ${DateTime.now()}');
    buffer.writeln('Total de registros: ${_logs.length}\n');

    for (final log in _logs) {
      buffer.writeln('[${log.timestamp}] [${log.level}] ${log.message}');
      if (log.details != null) {
        buffer.writeln('   Detalhes: ${log.details}');
      }
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Limpa logs antigos (mantém últimas 24h)
  void clearOldLogs() {
    final cutoff = DateTime.now().subtract(Duration(hours: 24));
    _logs.removeWhere((log) => log.timestamp.isBefore(cutoff));
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });
}