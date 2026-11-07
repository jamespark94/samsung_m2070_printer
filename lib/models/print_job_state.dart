enum PrintStep {
  idle,
  rendering,
  encoding,
  sending,
  completed,
  error,
}

class PrintJobProgress {
  final PrintStep step;
  final int currentPage;
  final int totalPages;
  final int sentBytes;
  final int totalBytes;
  final String statusMessage;

  const PrintJobProgress({
    this.step = PrintStep.idle,
    this.currentPage = 0,
    this.totalPages = 0,
    this.sentBytes = 0,
    this.totalBytes = 0,
    this.statusMessage = '',
  });

  PrintJobProgress copyWith({
    PrintStep? step,
    int? currentPage,
    int? totalPages,
    int? sentBytes,
    int? totalBytes,
    String? statusMessage,
  }) {
    return PrintJobProgress(
      step: step ?? this.step,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR
  final String message;

  LogEntry(this.message, {this.level = 'INFO'}) : timestamp = DateTime.now();

  @override
  String toString() {
    final timeStr = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
    return "[$timeStr] [$level] $message";
  }
}
