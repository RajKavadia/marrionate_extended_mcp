import '../drivers/flutter_skill_driver.dart';
import '../drivers/live_driver.dart';
import '../drivers/marionette_driver.dart';
import '../replay/batch_executor.dart' show ToolCapabilityException;
import 'tool_registry.dart';

/// Selector properties shared by every element-targeted tool.
///
/// `key` is the important one: it is the only selector that survives a text or
/// layout change, which is why the whole scenario format is built around
/// `ValueKey<String>`.
Map<String, Object?> _selectorSchema({List<String> required = const []}) => {
      'type': 'object',
      'properties': {
        'key': {
          'type': 'string',
          'description': 'ValueKey<String> of the target widget.',
        },
        'identifier': {
          'type': 'string',
          'description': 'Semantics identifier, when the app sets one.',
        },
        'text': {'type': 'string', 'description': 'Visible text to match.'},
        'type': {'type': 'string', 'description': 'Widget type name.'},
        'coordinates': {
          'type': 'object',
          'properties': {
            'x': {'type': 'number'},
            'y': {'type': 'number'},
          },
        },
        'ancestor_keys': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Scope the search to this subtree. Keys nest, '
              'outermost first.',
        },
        'focused_element': {
          'type': 'boolean',
          'description': 'Target whatever currently has focus.',
        },
      },
      if (required.isNotEmpty) 'required': required,
    };

Map<String, Object?> _schemaFor(String tool) => switch (tool) {
      'tap' ||
      'secondary_tap' ||
      'double_tap' ||
      'long_press' ||
      'scroll_to' ||
      'pinch_zoom' ||
      'press_back_button' ||
      'assert_visible' ||
      'assert_gone' =>
        _selectorSchema(),
      'get_interactive_elements' => {
          'type': 'object',
          'properties': {
            'compaction': {'type': 'string', 'enum': ['none', 'compact']},
            'ancestor_keys': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      'enter_text' => {
          ..._selectorSchema(),
          'properties': {
            ...(_selectorSchema()['properties']! as Map<String, Object?>),
            'text': {'type': 'string', 'description': 'Text to type.'},
          },
          'required': ['text'],
        },
      'assert_text_contains' => {
          ..._selectorSchema(),
          'properties': {
            ...(_selectorSchema()['properties']! as Map<String, Object?>),
            'contains': {'type': 'string'},
          },
          'required': ['contains'],
        },
      'wait_for_element' => {
          ..._selectorSchema(),
          'properties': {
            ...(_selectorSchema()['properties']! as Map<String, Object?>),
            'timeout_ms': {'type': 'integer'},
          },
        },
      'press_key' => {
          'type': 'object',
          'properties': {
            'key': {'type': 'string'},
            'modifiers': {'type': 'string'},
          },
          'required': ['key'],
        },
      'swipe' => {
          ..._selectorSchema(),
          'properties': {
            'direction': {
              'type': 'string',
              'enum': ['left', 'right', 'up', 'down'],
            },
            'distance': {'type': 'number'},
            'startX': {'type': 'number'},
            'startY': {'type': 'number'},
            'endX': {'type': 'number'},
            'endY': {'type': 'number'},
          },
        },
      'set_device_config' => {
          'type': 'object',
          'properties': {
            'text_scale': {'type': 'number'},
            'bold_text': {'type': 'boolean'},
            'platform_brightness': {'type': 'string', 'enum': ['light', 'dark']},
            'reset': {'type': 'boolean'},
          },
        },
      'call_custom_extension' => {
          'type': 'object',
          'properties': {
            'extension': {'type': 'string'},
            'args': {'type': 'object'},
          },
          'required': ['extension'],
        },
      _ => const {'type': 'object'},
    };

const Map<String, String> _marionetteDocs = {
  'get_interactive_elements':
      'Lists interactive widgets with their keys, text and bounds. Optionally '
      'scoped to a subtree via ancestor_keys.',
  'get_logs': 'Returns logs the app collected through the toolkit log store.',
  'take_screenshots': 'Captures every view and returns base64 PNGs.',
  'tap': 'Taps the element matching the selector.',
  'secondary_tap': 'Right-clicks the matching element. Desktop only.',
  'double_tap': 'Double taps the matching element.',
  'long_press': 'Presses and holds the matching element.',
  'swipe': 'Swipes by direction from an element, or between coordinates.',
  'pinch_zoom': 'Pinches on an element. scale > 1 zooms in.',
  'press_back_button': 'Sends a system back press.',
  'scroll_to': 'Scrolls until the matching element is visible.',
  'enter_text': 'Types into the field matching the selector.',
  'press_key': 'Sends a key event to the focused element.',
  'set_device_config':
      'Overrides text scale, bold text, or brightness. Needs a '
      'MarionetteDeviceConfig in the widget tree.',
  'list_custom_extensions':
      'Lists app-registered extensions, promoting each to a callable tool.',
  'call_custom_extension':
      'Calls an app-registered extension by name, without the ext.flutter. '
      'prefix.',
  'hot_reload': 'Hot reloads the app. Requires flutter run to be attached.',
  'hot_restart': 'Hot restarts the app. Requires flutter run to be attached.',
  'assert_text_contains':
      'Asserts that an element\'s text contains a substring.',
  'assert_visible': 'Asserts that an element is present on screen.',
  'assert_gone': 'Asserts that an element is no longer on screen.',
  'wait_for_element': 'Polls until an element appears, or the timeout expires.',
};

const Map<String, String> _flutterSkillDocs = {
  'get_interactive_elements':
      'Lists interactive elements. On the VM service these are Flutter '
      'widgets; over CDP they are DOM nodes.',
  'tap': 'Taps the element matching key or text.',
  'enter_text': 'Types into the field matching key.',
  'swipe': 'Swipes in a direction, optionally anchored to an element.',
  'take_screenshots': 'Captures the app and returns a base64 image.',
  'get_logs': 'Returns recent app log lines.',
  'clear_logs': 'Clears collected log lines.',
  'hot_reload': 'Reloads the app.',
  'hot_restart': 'Restarts the app. Requires flutter run to be attached.',
  'press_key': 'Sends a key event. VM service only.',
  'scroll_to': 'Scrolls an element into view. VM service only.',
  'wait_for_element': 'Waits for an element. VM service only.',
  'long_press': 'Long presses an element. VM service only.',
  'double_tap': 'Double taps an element. VM service only.',
  'tap_at': 'Taps absolute coordinates. VM service only.',
  'get_text': 'Reads a field\'s text. VM service only.',
  'get_route': 'Reports the current route. VM service only.',
  'go_back': 'Pops the current route. VM service only.',
  'assert_text_contains': "Asserts that an element's text contains a substring.",
};

/// Resolves the driver a tool should run against, or explains why it cannot.
///
/// Both stacks define a `tap` with different transports, so a tool registered
/// under [ToolSource.marionette] must never silently execute on the flutter-skill
/// driver: the selectors are not interchangeable.
LiveDriver Function(ToolContext) _resolverFor(ToolSource source) {
  return switch (source) {
    ToolSource.marionette => _requireMarionette,
    ToolSource.flutterSkill => _requireFlutterSkill,
    ToolSource.e2e => throw DriverException('built-in tools have no driver'),
  };
}

Never _notConnected(ToolSource source) {
  throw ToolCapabilityException(
    'Not connected to an app. Call connect_app first with a VM service URI '
    '(${source == ToolSource.marionette ? "mcp_" : "skill_"}tools need one).',
  );
}

LiveDriver _requireMarionette(ToolContext context) {
  final session = context.session;
  if (session == null) _notConnected(ToolSource.marionette);
  if (!session.supportsMarionette) {
    throw ToolCapabilityException(
      'The connected target is a web page driven over the Chrome DevTools '
      'Protocol, which never touches the Dart VM service, so marionette cannot '
      'reach it. Use the skill_ equivalents, which speak CDP.',
    );
  }
  final driver = session.driver;
  if (driver is! MarionetteDriver) {
    throw ToolCapabilityException(
      'The connected target is a flutter-skill VM-service session, not a '
      'marionette one. Use the skill_ equivalents.',
    );
  }
  return driver;
}

LiveDriver _requireFlutterSkill(ToolContext context) {
  final session = context.session;
  if (session == null) _notConnected(ToolSource.flutterSkill);
  final driver = session.driver;
  if (driver is! FlutterSkillDriver) {
    throw ToolCapabilityException(
      'The connected target is a marionette session, not a flutter-skill one. '
      'Use the mcp_ equivalents.',
    );
  }
  return driver;
}

/// Whether [driver] can serve [name] from [source].
///
/// Both stacks expose a `tap`, so name membership alone is not enough: the tool
/// has to belong to the stack that is actually attached, or `skill_tap` would
/// quietly run on a marionette session.
bool toolAvailableFor(ToolSource source, String name, LiveDriver driver) {
  // Built-ins are served by this server, not by a driver, so they are always
  // available regardless of what is attached.
  if (source == ToolSource.e2e) return true;
  final ownerMatches = switch (source) {
    ToolSource.marionette => driver is MarionetteDriver,
    ToolSource.flutterSkill => driver is FlutterSkillDriver,
    ToolSource.e2e => true,
  };
  return ownerMatches && driver.supportedTools.contains(name);
}

/// Registers the live tools for [source] into [registry].
///
/// [aliasNames] controls which tools also answer to their flat name. Both stacks
/// define `tap`, so the flat name is claimed once, by marionette, and
/// flutter-skill is reached through its `skill_` prefix. A caller on a web-only
/// CDP session therefore gets a capability error naming the alternative rather
/// than a silent dispatch to the wrong transport.
void registerLiveTools(
  ToolRegistry registry,
  ToolSource source, {
  required Set<String> toolNames,
  required Set<String> aliasNames,
}) {
  final docs = source == ToolSource.marionette
      ? _marionetteDocs
      : _flutterSkillDocs;

  registry.registerAll(toolNames.map((name) {
    final description = docs[name] ??
        'Runs the flutter-skill "$name" tool against the connected app.';
    return ToolDescriptor(
      name: name,
      description: description,
      source: source,
      inputSchema: _schemaFor(name),
      aliases: aliasNames.contains(name) ? {name} : const {},
      handler: (args, context) async {
        final driver = _resolverFor(source)(context);
        return driver.execute(name, args);
      },
    );
  }));
}

/// Registers every live tool both stacks can serve, before any connection.
///
/// Marionette is registered first so it claims the flat aliases. Tools are
/// advertised up front and gated at call time instead, because an agent needs to
/// see what it can call before it knows where the app is running.
void registerAllLiveTools(ToolRegistry registry) {
  registerLiveTools(
    registry,
    ToolSource.marionette,
    toolNames: MarionetteDriver.toolNames,
    aliasNames: MarionetteDriver.toolNames,
  );

  final marionetteNames = MarionetteDriver.toolNames.toSet();
  final skillTools = FlutterSkillDriver.catalogFor(FlutterSkillMode.native);
  registerLiveTools(
    registry,
    ToolSource.flutterSkill,
    toolNames: skillTools,
    aliasNames: skillTools.where((n) => !marionetteNames.contains(n)).toSet(),
  );
}
