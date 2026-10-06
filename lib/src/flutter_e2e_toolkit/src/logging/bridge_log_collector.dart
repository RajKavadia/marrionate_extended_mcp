import 'package:marrionate_extended_mcp/src/marionette_flutter/e2e_marionette_flutter.dart';
import 'package:logging/logging.dart';

import 'e2e_log_store.dart';

/// Forwards application logs into marionette and the toolkit's own store.
///
/// Implements marionette's [LogCollector], whose contract is a sink factory:
/// marionette calls [start] with a callback and expects this object to invoke it
/// for every captured line. flutter-skill's internal log buffers are private
/// with no public write path, so they are deliberately not bridged; the toolkit
/// store is the single read surface instead.
class BridgeLogCollector implements LogCollector {
  BridgeLogCollector({E2eLogStore? store, this.mirrorToStdout = false})
      : store = store ?? E2eLogStore();

  /// Shared store read by the `get_logs` MCP tool.
  final E2eLogStore store;

  /// Also prints each line, for local debugging.
  final bool mirrorToStdout;

  void Function(String log)? _onLog;
  bool _started = false;

  @override
  void start(void Function(String log) onLog) {
    _onLog = onLog;
    _started = true;
  }

  @override
  void dispose() {
    _onLog = null;
    _started = false;
  }

  /// Records an informational line.
  void emit(String message) => _record(message, E2eLogLevel.info);

  /// Records a debug line.
  void debug(String message) => _record(message, E2eLogLevel.debug);

  /// Records a warning line.
  void warn(String message) => _record(message, E2eLogLevel.warning);

  /// Records an error line and its stack trace.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(': $error');
    store.add(E2eLogRecord(
      message: buffer.toString(),
      level: E2eLogLevel.error,
      timestamp: DateTime.now(),
      stackTrace: stackTrace?.toString(),
    ));
    _forward(buffer.toString());
  }

  /// Ingests a log record from `package:logging`.
  ///
  /// Level 900 and above is `Level.SEVERE`, which is what FlutterError and
  /// zone-uncaught errors arrive as; everything below is informational so a
  /// chatty app does not flood the buffer.
  void ingestLogRecord(LogRecord record) {
    final level = record.level >= Level.SEVERE
        ? E2eLogLevel.error
        : record.level >= Level.WARNING
            ? E2eLogLevel.warning
            : E2eLogLevel.info;
    _record('${record.loggerName}: ${record.message}', level,
        error: record.error, stackTrace: record.stackTrace);
  }

  void _record(String message, E2eLogLevel level,
      {Object? error, StackTrace? stackTrace}) {
    store.add(E2eLogRecord(
      message: message,
      level: level,
      timestamp: DateTime.now(),
      stackTrace: stackTrace?.toString(),
    ));
    _forward(message);
  }

  void _forward(String message) {
    if (mirrorToStdout) {
      // ignore: avoid_print
      print('[e2e] $message');
    }
    // Marionette's collector is only wired up after the binding starts it;
    // emitting before that must not throw.
    _onLog?.call(message);
  }

  /// Whether marionette has begun collecting.
  bool get isStarted => _started;
}
