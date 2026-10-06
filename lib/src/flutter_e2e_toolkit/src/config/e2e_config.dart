import 'package:flutter/widgets.dart';

/// How the toolkit reports elements during traversal.
enum E2eCompaction {
  /// Trim rendering details agents never read. Default.
  compact,

  /// Report every element with full properties.
  none,
}

/// Configuration for [E2eBinding.ensureInitialized].
class E2eConfig {
  const E2eConfig({
    this.autoEnableIndicators = false,
    this.enableSessionReports = true,
    this.compaction = E2eCompaction.compact,
    this.maxScreenshotSize,
    this.isInteractiveElement,
    this.extractText,
    this.verbose = false,
    this.marionetteOnWeb = false,
    this.enableWebSemantics = true,
  });

  /// Draws flutter-skill's tap/gesture indicator overlay.
  ///
  /// Off by default because the overlay pollutes screenshots, which would break
  /// visual assertions.
  final bool autoEnableIndicators;

  /// Writes marionette session reports (step log and screenshots) to disk.
  final bool enableSessionReports;

  /// Element-traversal verbosity for marionette's inspector.
  final E2eCompaction compaction;

  /// Caps screenshot dimensions; null captures at full size.
  final Size? maxScreenshotSize;

  /// Overrides which elements marionette treats as interactive.
  ///
  /// Returning false hides the element from the interactive-element list and
  /// from assertions that target it.
  final bool Function(Element element)? isInteractiveElement;

  /// Overrides how text is extracted from an element.
  final String? Function(Element element)? extractText;

  /// Prints binding lifecycle events to stdout.
  final bool verbose;

  /// Installs `MarionetteBinding` even on web, where it is normally skipped.
  ///
  /// Off by default because marionette's production transport assumes a VM
  /// service reachable over the wire, and Flutter web in **release** mode has no
  /// Dart VM service at all. In **debug** builds Flutter web does expose one,
  /// and marionette's extensions can register against it, so this flag exists to
  /// test that path rather than to depend on it.
  ///
  /// Leave this off unless you are deliberately evaluating web support: with it
  /// on, web targets advertise marionette tools whose behaviour is only
  /// guaranteed in debug builds.
  final bool marionetteOnWeb;

  /// Materializes Flutter web's semantics tree so DOM-based drivers can see it.
  ///
  /// A Flutter web app paints into a canvas and normally keeps no DOM for its
  /// widgets, which is why a Chrome DevTools Protocol driver finds nothing by
  /// default. Calling `ensureSemantics()` builds the accessibility tree Flutter
  /// already uses for screen readers, giving CDP real nodes to select.
  ///
  /// Only applied on web when marionette is *not* driving: marionette reads the
  /// widget tree directly and needs no semantics, and leaving the tree off keeps
  /// the DOM closer to a shipping build. Costs a little rendering performance.
  final bool enableWebSemantics;

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing an explicit null to a nullable callback clears it; the `?? this.x`
  /// pattern means clear-by-null is not expressible here, which is deliberate
  /// for the callbacks. Use [E2eConfig] directly for that case.
  E2eConfig copyWith({
    bool? autoEnableIndicators,
    bool? enableSessionReports,
    E2eCompaction? compaction,
    Size? maxScreenshotSize,
    bool Function(Element element)? isInteractiveElement,
    String? Function(Element element)? extractText,
    bool? verbose,
    bool? marionetteOnWeb,
    bool? enableWebSemantics,
  }) {
    return E2eConfig(
      autoEnableIndicators: autoEnableIndicators ?? this.autoEnableIndicators,
      enableSessionReports: enableSessionReports ?? this.enableSessionReports,
      compaction: compaction ?? this.compaction,
      maxScreenshotSize: maxScreenshotSize ?? this.maxScreenshotSize,
      isInteractiveElement: isInteractiveElement ?? this.isInteractiveElement,
      extractText: extractText ?? this.extractText,
      verbose: verbose ?? this.verbose,
      marionetteOnWeb: marionetteOnWeb ?? this.marionetteOnWeb,
      enableWebSemantics: enableWebSemantics ?? this.enableWebSemantics,
    );
  }

  @override
  String toString() => 'E2eConfig(indicators: $autoEnableIndicators, '
      'sessionReports: $enableSessionReports, compaction: $compaction)';
}
