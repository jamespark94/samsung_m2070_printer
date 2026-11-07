import 'package:flutter/foundation.dart';
import '../models/print_job_state.dart';

class PrintLogger extends ChangeNotifier {
  static final PrintLogger instance = PrintLogger._internal();
  PrintLogger._internal();

  final List<LogEntry> _logs = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String message, {String level = 'INFO'}) {
    final entry = LogEntry(message, level: level);
    _logs.add(entry);
    notifyListeners();
  }

  void info(String message) => log(message, level: 'INFO');
  void warn(String message) => log(message, level: 'WARN');
  void error(String message) => log(message, level: 'ERROR');

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
