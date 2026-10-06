import 'package:marrionate_extended_mcp/src/flutter_skill/e2e_flutter_skill.dart';
import 'package:marrionate_extended_mcp/src/marionette_flutter/e2e_marionette_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

import '../config/e2e_config.dart';
import '../capability/e2e_capability.dart';
import '../logging/bridge_log_collector.dart';
import '../logging/e2e_log_store.dart';
import '../platform/e2e_platform.dart';

/// Initialises both automation bindings in the only order that works.
///
/// Two independent bindings are involved and they collide in two ways:
///
///  1. `MarionetteBinding extends WidgetsFlutterBinding`, so it *is* the
///     app's widget binding. It must be constructed before anything else
///     touches `WidgetsBinding.instance`, and it throws a [FlutterError] if a
///     binding already exists.
///  2. `FlutterSkillBinding.ensureInitialized` overwrites
///     `FlutterError.onError`, silently discarding whatever handler was there.
///
/// So the native sequence is: capture the current handler, install marionette,
/// install flutter-skill, then re-install a handler that records the error and
/// forwards to flutter-skill's handler. Nothing is swallowed.
///
/// On web there is no Dart VM service, so neither VM-service-based binding can
/// work. Only flutter-skill's JS bridge is installed there.
///
/// Call this from `main()` before `runApp()`.
class E2eBinding {
  E2eBinding._(
    this.config,
    this.platform,
    this.logs,
    this.collector, {
    bool marionetteInstalled = true,
  }) : _marionetteInstalled = marionetteInstalled;

  static E2eBinding? _instance;

  /// Retained handle for the web semantics tree.
  ///
  /// Held for the process lifetime on purpose: dropping the last handle turns
  /// semantics back off, which would silently blind a CDP driver mid-run.
  static SemanticsHandle? _webSemanticsHandle;

  /// Whether the web semantics tree is currently materialized.
  ///
  /// False on native, where marionette reads the widget tree directly, and on
  /// web whenever [E2eConfig.enableWebSemantics] was left off.
  static bool get webSemanticsEnabled => _webSemanticsHandle != null;

  /// The active binding.
  ///
  /// Throws if [ensureInitialized] has not run, which is always a bug: tooling
  /// reaching this point outside a debug build means the app forgot to opt in.
  static E2eBinding get instance {
    final binding = _instance;
    if (binding == null) {
      throw StateError(
        'E2eBinding.ensureInitialized() was never called. Call it from main() '
        'before runApp(), guarded by `if (!kReleaseMode)`.',
      );
    }
    return binding;
  }

  /// Whether [ensureInitialized] has run.
  static bool get isInitialized => _instance != null;

  /// Installs the appropriate bindings for the current platform.
  ///
  /// Idempotent: subsequent calls return the existing binding.
  static E2eBinding ensureInitialized([E2eConfig config = const E2eConfig()]) {
    final existing = _instance;
    if (existing != null) return existing;

    return _instance = kIsWeb ? _initWeb(config) : _initNative(config);
  }

  static E2eBinding _initNative(E2eConfig config) {
    final logs = E2eLogStore();
    final collector = BridgeLogCollector(store: logs, mirrorToStdout: config.verbose);

    // (1) Remember the pre-existing handler so the chain can call it later.
    _previousOnError = FlutterError.onError;

    // (2) Marionette must own WidgetsBinding.instance. Throws if a binding was
    //     already installed by the app or by a plugin.
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(
        isInteractiveElement: config.isInteractiveElement,
        extractText: config.extractText,
        maxScreenshotSize: config.maxScreenshotSize,
        compaction: _toCompactionMode(config.compaction),
        logCollector: collector,
        enableSessionReports: config.enableSessionReports,
      ),
    );

    // (3) Registers ext.flutter.flutter_skill.* and overwrites onError.
    FlutterSkillBinding.ensureInitialized(
      autoEnableIndicators: config.autoEnableIndicators,
    );

    // (4) Restore a handler that records then forwards, so flutter-skill's
    //     error ring buffer still receives everything it used to.
    _chainErrorHandlers(logs);

    if (config.verbose) {
      // ignore: avoid_print
      print('[e2e] E2eBinding native init: marionette + flutter-skill '
          '(VM service)');
    }

    return E2eBinding._(config, E2ePlatform.nativeVmService, logs, collector);
  }

  static E2eBinding _initWeb(E2eConfig config) {
    final logs = E2eLogStore();
    final collector = BridgeLogCollector(store: logs, mirrorToStdout: config.verbose);

    // Flutter web has no Dart VM service in release builds, so marionette's
    // extensions could never be invoked there and installing them would only
    // cost startup time. FlutterSkillBinding handles the web transport itself:
    // on web it registers the JS bridge instead of relying on service
    // extensions.
    //
    // In debug builds Flutter web *does* expose a VM service, so marionette can
    // be opted into for evaluation. See E2eConfig.marionetteOnWeb.
    if (config.marionetteOnWeb) {
      try {
        _previousOnError = FlutterError.onError;
        MarionetteBinding.ensureInitialized(
          MarionetteConfiguration(
            isInteractiveElement: config.isInteractiveElement,
            extractText: config.extractText,
            maxScreenshotSize: config.maxScreenshotSize,
            compaction: _toCompactionMode(config.compaction),
            logCollector: collector,
            enableSessionReports: config.enableSessionReports,
          ),
        );
      } catch (e) {
        if (config.verbose) {
          // ignore: avoid_print
          print('[e2e] MarionetteBinding on web skipped: $e');
        }
      }
    }

    FlutterSkillBinding.ensureInitialized(
      autoEnableIndicators: config.autoEnableIndicators,
    );

    // Without marionette, the only web transport is CDP, and CDP cannot see
    // inside a canvas. Materializing the semantics tree gives it real DOM nodes
    // to select. Skipped when marionette drives, since that reads the widget
    // tree directly and would gain nothing.
    //
    // Deferred to after the first frame: enabling semantics reconfigures the
    // pipeline's semantics owner, which is not ready before a frame is
    // scheduled, and asking for it too early trips an assertion.
    if (!config.marionetteOnWeb && config.enableWebSemantics) {
      Future.delayed(const Duration(milliseconds: 250), () {
        try {
          _webSemanticsHandle = SemanticsBinding.instance.ensureSemantics();
          if (config.verbose) {
            // ignore: avoid_print
            print('[e2e] semantics tree enabled for CDP automation');
          }
        } catch (e) {
          if (config.verbose) {
            // ignore: avoid_print
            print('[e2e] could not enable semantics: $e');
          }
        }
      });
    }

    // FlutterSkillBinding installs FlutterError.onError on every platform, so
    // the chain is needed here too, not only on native.
    _chainErrorHandlers(logs);

    if (config.verbose) {
      // ignore: avoid_print
      print('[e2e] E2eBinding web init: flutter-skill JS bridge'
          '${config.marionetteOnWeb ? " + marionette (opt-in, debug only)" : " only"}'
          ' (no release VM service; marionette'
          '${config.marionetteOnWeb ? " experimental" : " unavailable"})');
    }

    // The platform stays webCdpBridge: marionette's presence does not change the
    // transport flutter-skill uses, and callers still need the capability report
    // to know marionette is experimental here.
    return E2eBinding._(
      config,
      E2ePlatform.webCdpBridge,
      logs,
      collector,
      marionetteInstalled: config.marionetteOnWeb,
    );
  }

  static void _chainErrorHandlers(E2eLogStore logs) {
    final flutterSkillHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logs.add(E2eLogRecord(
        message: details.exceptionAsString(),
        level: E2eLogLevel.error,
        timestamp: DateTime.now(),
        stackTrace: details.stack?.toString(),
      ));
      // Never swallow: flutter-skill owns its error ring buffer and relies on
      // this call to populate it.
      flutterSkillHandler?.call(details);
      _previousOnError?.call(details);
    };
  }

  static FlutterExceptionHandler? _previousOnError;

  /// Configuration this binding was initialised with.
  final E2eConfig config;

  /// Transport this binding selected.
  final E2ePlatform platform;

  /// Toolkit-owned log store.
  final E2eLogStore logs;

  /// Collector wired into marionette.
  final BridgeLogCollector collector;

  final bool _marionetteInstalled;

  /// Capability report for the selected platform.
  late final E2eCapability capability = E2eCapability.forPlatform(
    platform,
    marionetteInstalled: _marionetteInstalled,
  );

  /// Whether marionette's tools can work here.
  ///
  /// True on native. On web only when [E2eConfig.marionetteOnWeb] was set, since
  /// marionette needs a Dart VM service and web release builds have none.
  bool get marionetteAvailable =>
      platform == E2ePlatform.nativeVmService || _marionetteInstalled;

  /// Whether marionette is supported on this platform without caveats.
  ///
  /// Distinguishes "installed and expected to work" from "installed but
  /// experimental", so a scenario can assert strictly and tooling can warn.
  bool get marionetteFullySupported =>
      platform == E2ePlatform.nativeVmService;

  /// Whether flutter-skill's tools can work here.
  bool get flutterSkillAvailable => capability.flutterSkillAvailable;

  /// Releases the log collector. Safe to call more than once.
  void dispose() {
    collector.dispose();
  }

  static CompactionMode _toCompactionMode(E2eCompaction compaction) {
    switch (compaction) {
      case E2eCompaction.compact:
        return CompactionMode.compact;
      case E2eCompaction.none:
        return CompactionMode.none;
    }
  }
}
