import 'dart:collection';

/// Severity of a captured log line.
enum E2eLogLevel {
  debug,
  info,
  warning,
  error,
}

/// One captured log line.
class E2eLogRecord {
  E2eLogRecord({
    required this.message,
    required this.level,
    required this.timestamp,
    this.stackTrace,
  });

  final String message;
  final E2eLogLevel level;
  final DateTime timestamp;
  final String? stackTrace;

  Map<String, Object?> toJson() => {
        'message': message,
        'level': level.name,
        'timestamp': timestamp.toIso8601String(),
        if (stackTrace != null) 'stackTrace': stackTrace,
      };

  @override
  String toString() => '[${level.name}] $message';
}

/// In-memory ring buffer of log lines.
///
/// Bounded so a long-running app cannot exhaust memory through logging alone.
class E2eLogStore {
  E2eLogStore({this.capacity = 500});

  /// Maximum retained records.
  final int capacity;

  final Queue<E2eLogRecord> _records = Queue<E2eLogRecord>();

  /// Appends a record, evicting the oldest once [capacity] is exceeded.
  void add(E2eLogRecord record) {
    _records.addLast(record);
    while (_records.length > capacity) {
      _records.removeFirst();
    }
  }

  /// Returns records matching [level], or all records when [level] is null.
  ///
  /// [since] filters out records older than the given instant, which lets the
  /// MCP server return only what happened after a scenario started.
  List<E2eLogRecord> records({E2eLogLevel? level, DateTime? since}) {
    return _records
        .where((r) => level == null || r.level == level)
        .where((r) => since == null || !r.timestamp.isBefore(since))
        .toList(growable: false);
  }

  /// Removes and returns every retained record.
  List<E2eLogRecord> drain() {
    final out = _records.toList(growable: false);
    _records.clear();
    return out;
  }

  int get length => _records.length;

  void clear() => _records.clear();
}
