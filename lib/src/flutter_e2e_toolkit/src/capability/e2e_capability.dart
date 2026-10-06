import '../platform/e2e_platform.dart';

/// Reports which automation tools actually work on this platform.
///
/// The MCP server consults this before dispatching a call. Without it, a
/// marionette tool invoked against a web target would wait for a VM service
/// reply that can never arrive and surface as an opaque timeout; with it the
/// caller gets an immediate, explanatory error.
class E2eCapability {
  const E2eCapability({
    required this.platform,
    required this.marionetteTools,
    required this.flutterSkillTools,
    this.marionetteExperimental = false,
  });

  /// Builds the capability set implied by [platform].
  ///
  /// Set [marionetteInstalled] when marionette was explicitly opted into on web
  /// via `E2eConfig.marionetteOnWeb`; it then reports as available but
  /// experimental.
  factory E2eCapability.forPlatform(
    E2ePlatform platform, {
    bool marionetteInstalled = false,
  }) {
    final marionetteUsable =
        platform == E2ePlatform.nativeVmService || marionetteInstalled;
    return E2eCapability(
      platform: platform,
      marionetteTools:
          marionetteUsable ? marionetteToolNames : const <String>{},
      flutterSkillTools: flutterSkillToolNames,
      marionetteExperimental:
          platform != E2ePlatform.nativeVmService && marionetteInstalled,
    );
  }

  /// Marionette tool names, all VM-service-backed.
  static const Set<String> marionetteToolNames = {
    'tap',
    'secondary_tap',
    'double_tap',
    'long_press',
    'swipe',
    'pinch_zoom',
    'press_back_button',
    'scroll_to',
    'enter_text',
    'press_key',
    'get_interactive_elements',
    'get_logs',
    'take_screenshots',
    'set_device_config',
    'list_custom_extensions',
    'call_custom_extension',
    'hot_reload',
    'hot_restart',
  };

  /// Flutter-skill tool names, split into interaction and assertion groups.
  static const Set<String> flutterSkillToolNames = {
    'inspect',
    'tap',
    'enter_text',
    'scroll',
    'swipe',
    'long_press',
    'double_tap',
    'go_back',
    'press_key',
    'screenshot',
    'wait',
    'hot_reload',
    'hot_restart',
    'assert_visible',
    'assert_not_visible',
    'assert_text',
    'assert_text_contains',
    'assert_element_count',
    'assert_enabled',
    'execute_batch',
    'connect_app',
  };

  final E2ePlatform platform;

  /// Marionette tools reachable here; empty on web.
  final Set<String> marionetteTools;

  /// Flutter-skill tools reachable here.
  final Set<String> flutterSkillTools;

  /// Whether marionette is present but not guaranteed.
  ///
  /// True only on web with `E2eConfig.marionetteOnWeb` set: Flutter web exposes
  /// a Dart VM service in debug builds but not in release builds, so marionette
  /// works there under conditions that do not hold for a shipped web app.
  final bool marionetteExperimental;

  /// Whether marionette can work here, i.e. a VM service exists.
  bool get marionetteAvailable => marionetteTools.isNotEmpty;

  /// Whether flutter-skill can work here.
  ///
  /// True on every supported platform: the VM service on native, the JS/CDP
  /// bridge on web.
  bool get flutterSkillAvailable => flutterSkillTools.isNotEmpty;

  /// Whether [toolName] can run on this platform.
  bool supports(String toolName) {
    if (marionetteTools.contains(toolName)) return true;
    if (flutterSkillTools.contains(toolName)) return true;
    // Unknown tools are reported as unsupported by the registry, not here.
    return false;
  }

  /// Whether [toolName] is served by marionette specifically.
  bool isMarionetteTool(String toolName) =>
      marionetteToolNames.contains(toolName);

  /// Why [toolName] cannot run, or null when it can.
  String? unsupportedReason(String toolName) {
    if (supports(toolName)) return null;

    if (marionetteToolNames.contains(toolName)) {
      if (platform == E2ePlatform.webCdpBridge) {
        return 'Tool "$toolName" is served by marionette, which requires the '
            'Dart VM service. Flutter web only exposes one in debug builds, and '
            'the app did not opt in via E2eConfig.marionetteOnWeb. Use the '
            'flutter-skill equivalent instead (for example "assert_visible" or '
            '"tap").';
      }
    }
    return 'Tool "$toolName" is not registered.';
  }

  Map<String, Object?> toJson() => {
        'platform': platform.name,
        'marionetteAvailable': marionetteAvailable,
        'marionetteExperimental': marionetteExperimental,
        'marionetteTools': marionetteTools.toList()..sort(),
        'flutterSkillTools': flutterSkillTools.toList()..sort(),
      };

  @override
  String toString() => 'E2eCapability(${platform.name}, '
      'marionette: ${marionetteTools.length}, '
      'skill: ${flutterSkillTools.length})';
}
