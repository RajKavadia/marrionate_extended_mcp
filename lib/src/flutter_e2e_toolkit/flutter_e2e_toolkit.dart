/// App-side bindings and scenario model for Flutter e2e automation.
///
/// One entry point wires both vendored automation stacks together:
///
/// ```dart
/// void main() {
///   if (!kReleaseMode) {
///     E2eBinding.ensureInitialized(const E2eConfig(verbose: true));
///   }
///   runApp(const MyApp());
/// }
/// ```
///
/// On native targets that installs marionette and flutter-skill's VM-service
/// extensions; on web it installs the flutter-skill JS bridge, because no Dart
/// VM service exists in a browser. [E2eCapability] reports which tools work so
/// callers fail fast instead of timing out.
///
/// Requires Flutter. Code running on a plain Dart VM (such as the MCP server)
/// must import `package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart`
/// instead, which omits the widget bindings.
library;

export 'flutter_e2e_toolkit_core.dart';
export 'src/binding/e2e_binding.dart';
export 'src/capability/e2e_capability.dart';
export 'src/config/e2e_config.dart';
export 'src/logging/bridge_log_collector.dart';
export 'src/logging/e2e_log_store.dart';
export 'src/recording/e2e_recorder_fab.dart';
export 'src/recording/e2e_recorder_scope.dart';
export 'src/recording/interaction_recorder.dart';
export 'src/recording/live_session_publisher.dart';
