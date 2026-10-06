/// Which automation transport a running app is using.
///
/// Deliberately free of any Flutter import. The MCP server depends on this enum
/// to gate tools per platform, and that server runs on the plain Dart VM where
/// `dart:ui` does not exist, so anything in its import graph must avoid Flutter.
enum E2ePlatform {
  /// Dart VM service is available (Windows, macOS, Linux, Android, iOS).
  ///
  /// Both marionette (`ext.flutter.marionette.*`) and flutter-skill
  /// (`ext.flutter.flutter_skill.*`) service extensions are registered and
  /// reachable through the VM service protocol.
  nativeVmService,

  /// Running in a browser, where no Dart VM service exists.
  ///
  /// Only the flutter-skill JS/CDP bridge works. Marionette is architecturally
  /// VM-service-only, so its tools are unavailable here.
  webCdpBridge,
}

/// Whether the platform has a usable Dart VM service.
///
/// Used by the MCP server to decide whether marionette tools can be advertised.
bool get hasVmService => E2ePlatform.nativeVmService.hasVmService;

/// VM-service availability for a platform.
extension E2ePlatformVmService on E2ePlatform {
  /// True when the Dart VM service is reachable for this platform.
  bool get hasVmService => this == E2ePlatform.nativeVmService;
}

/// Whether marionette tools can run on this platform.
bool get marionetteSupported => E2ePlatform.nativeVmService.marionetteSupported;

/// Marionette support for a platform.
extension E2ePlatformMarionette on E2ePlatform {
  /// True when marionette's VM-service extensions can be registered.
  bool get marionetteSupported => this == E2ePlatform.nativeVmService;
}
