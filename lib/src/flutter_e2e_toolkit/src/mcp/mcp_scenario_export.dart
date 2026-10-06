import 'dart:convert';

import '../scenario/e2e_scenario.dart';

/// Which stack to prefer when a scenario action exists on both Marionette and
/// flutter-skill.
enum McpTransportPreference {
  /// Marionette VM-service tools (`mcp_*`). Default for native debug apps.
  marionetteFirst,

  /// Flutter-skill tools (`skill_*`). Typical for web/CDP sessions.
  flutterSkillFirst,
}

/// One JSON-RPC 2.0 message the MCP client sends over stdio to
/// `flutter-e2e-mcp`.
class McpJsonRpcMessage {
  const McpJsonRpcMessage({
    required this.id,
    required this.method,
    this.params = const {},
  });

  /// Monotonic request id (MCP clients assign these).
  final int id;

  /// Usually `tools/call`; `initialize` may appear in hand-written scripts.
  final String method;

  /// JSON-RPC params object.
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params.isNotEmpty) 'params': params,
      };

  /// Builds a `tools/call` for [toolName] with [arguments].
  factory McpJsonRpcMessage.toolsCall(
    int id,
    String toolName, {
    Map<String, Object?> arguments = const {},
  }) =>
      McpJsonRpcMessage(
        id: id,
        method: 'tools/call',
        params: {
          'name': toolName,
          'arguments': arguments,
        },
      );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// JSON document: attach to a live app, then replay scenario steps as MCP calls.
///
/// Agents and CI can save this file and pipe each [instructions] entry (or the
/// whole array) to a running `flutter-e2e-mcp serve` session after replacing
/// [attachTargetPlaceholder] with the VM service URI from `flutter run`.
class McpInstructionScript {
  const McpInstructionScript({
    required this.scenarioName,
    this.description,
    required this.attach,
    required this.instructions,
    this.transportPreference = McpTransportPreference.marionetteFirst,
    this.server = 'flutter-e2e-mcp',
  });

  /// Scenario this script was generated from.
  final String scenarioName;

  final String? description;

  /// `connect_app` call. Replace [attachTargetPlaceholder] before running.
  final McpJsonRpcMessage attach;

  /// Ordered `tools/call` messages (tap, enter_text, assertions, …).
  final List<McpJsonRpcMessage> instructions;

  final McpTransportPreference transportPreference;

  /// MCP server that consumes these messages.
  final String server;

  /// Placeholder in [attach] arguments for the Dart VM service URI.
  static const String attachTargetPlaceholder = '{{VM_SERVICE_URI}}';

  Map<String, Object?> toJson() => {
        'format': 'flutter-e2e-mcp-instructions',
        'formatVersion': 1,
        'server': server,
        'scenario': scenarioName,
        if (description != null) 'description': description,
        'transportPreference': transportPreference.name,
        'attachTargetPlaceholder': attachTargetPlaceholder,
        'attach': attach.toJson(),
        'instructions': instructions.map((m) => m.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Converts validated [E2eScenario] JSON into MCP JSON-RPC instructions.
class McpScenarioExporter {
  const McpScenarioExporter({
    this.preference = McpTransportPreference.marionetteFirst,
    this.includeAttach = true,
    this.startId = 1,
  });

  final McpTransportPreference preference;
  final bool includeAttach;
  final int startId;

  /// Marionette bare tool names (wire prefix `mcp_`).
  static const Set<String> _marionetteTools = {
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
    'assert_text_contains',
    'assert_visible',
    'assert_gone',
    'wait_for_element',
  };

  /// Flutter-skill bare tool names (wire prefix `skill_`).
  static const Set<String> _flutterSkillTools = {
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
  };

  /// Scenario action name → Marionette tool name when they differ.
  static const Map<String, String> _marionetteAliases = {
    'scroll': 'scroll_to',
    'go_back': 'press_back_button',
    'screenshot': 'take_screenshots',
    'wait': 'wait_for_element',
  };

  /// Scenario action name → flutter-skill tool name when they differ.
  static const Map<String, String> _skillAliases = {};

  /// Built-in flutter-e2e MCP tools (no stack prefix).
  static const Set<String> _e2eTools = {
    'connect_app',
    'disconnect_app',
    'execute_batch',
    'replay_scenario',
    'capability',
  };

  /// Resolves a scenario [action] to the MCP wire name (`mcp_tap`, `skill_tap`, …).
  String wireNameForAction(String action) {
    if (_e2eTools.contains(action)) return action;

    final marionetteTool = _marionetteAliases[action] ?? action;
    final skillTool = _skillAliases[action] ?? action;

    final onMarionette = _marionetteTools.contains(marionetteTool);
    final onSkill = _flutterSkillTools.contains(skillTool);

    if (preference == McpTransportPreference.marionetteFirst) {
      if (onMarionette) return 'mcp_$marionetteTool';
      if (onSkill) return 'skill_$skillTool';
    } else {
      if (onSkill) return 'skill_$skillTool';
      if (onMarionette) return 'mcp_$marionetteTool';
    }
    return action;
  }

  /// Full script: optional attach + one MCP call per scenario step.
  McpInstructionScript exportScript(E2eScenario scenario) {
    var id = startId;
    final attach = McpJsonRpcMessage.toolsCall(
      id++,
      'connect_app',
      arguments: {
        'target': McpInstructionScript.attachTargetPlaceholder,
        'kind': preference == McpTransportPreference.marionetteFirst
            ? 'vmService'
            : 'webPage',
      },
    );

    final calls = <McpJsonRpcMessage>[];
    for (final step in scenario.interpolate().commands) {
      calls.add(
        McpJsonRpcMessage.toolsCall(
          id++,
          wireNameForAction(step.action),
          arguments: Map<String, Object?>.from(step.args),
        ),
      );
    }

    return McpInstructionScript(
      scenarioName: scenario.name,
      description: scenario.description,
      attach: attach,
      instructions: calls,
      transportPreference: preference,
    );
  }

  /// Single MCP `execute_batch` call wrapping the whole scenario (compact attach).
  McpJsonRpcMessage exportBatchCall(
    E2eScenario scenario, {
    int id = 1,
    bool stopOnFailure = true,
  }) {
    return McpJsonRpcMessage.toolsCall(
      id,
      'execute_batch',
      arguments: {
        'commands': scenario.interpolate().commands.map((c) => c.toJson()).toList(),
        'stop_on_failure': stopOnFailure,
      },
    );
  }
}
