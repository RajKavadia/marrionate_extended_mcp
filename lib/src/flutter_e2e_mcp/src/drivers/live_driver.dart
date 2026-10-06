/// A live connection to a Flutter app under test.
///
/// Both vendored automation stacks reduce to the same shape: connect to a
/// target, execute a named tool with arguments, return a JSON-ish result,
/// disconnect. This interface is the seam that lets [ToolRegistry] stay
/// agnostic about which stack actually drives the app.
///
/// Implementations must translate a tool failure into a thrown exception or an
/// `ok: false` result rather than returning a malformed payload, because
/// `BatchExecutor` treats a missing `ok` as success.
abstract class LiveDriver {
  /// Identifies the backing stack, e.g. `marionette` or `flutterSkill`.
  String get kind;

  /// Whether a target is currently attached.
  bool get isConnected;

  /// The target this driver is attached to, or null.
  String? get target;

  /// Tool names this driver can execute.
  Set<String> get supportedTools;

  /// Attaches to [target].
  ///
  /// Throws [DriverException] if the target cannot be reached.
  Future<Map<String, Object?>> connect(String target);

  /// Runs [tool] with [args].
  ///
  /// The returned map always contains `ok`; on failure it also carries `error`.
  Future<Map<String, Object?>> execute(
    String tool,
    Map<String, Object?> args,
  );

  /// Detaches from the app. Safe to call when not connected.
  Future<void> disconnect();
}

/// Raised when a driver cannot connect to, or talk to, its target.
class DriverException implements Exception {
  DriverException(this.message, {this.hint});

  final String message;

  /// Actionable next step, when there is an obvious one.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}
