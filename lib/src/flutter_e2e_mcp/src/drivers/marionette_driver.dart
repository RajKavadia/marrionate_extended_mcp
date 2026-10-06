// The vendored marionette package ships no public library barrel, so its
// internals are imported directly. This mirrors what `e2e_marionette_cli`
// already does in this repo.
// ignore_for_file: implementation_imports

import 'package:marrionate_extended_mcp/src/marionette_mcp/src/formatting.dart';
import 'package:marrionate_extended_mcp/src/marionette_mcp/src/vm_service/vm_service_connector.dart';

import 'live_driver.dart';

/// Drives a live app through marionette's VM-service extensions.
///
/// Marionette is the richer of the two backends: it walks the real Flutter
/// element tree, so selectors are `ValueKey<String>` rather than CSS or
/// coordinates. That precision is why scenarios target it first and fall back
/// to flutter-skill only where CDP cannot see inside a canvas.
///
/// ## Web support
///
/// Flutter web in a **debug** build does expose a Dart VM service, so marionette
/// works there. It does not in a **release** build, which is why the app-side
/// `E2eBinding` gates installation behind `E2eConfig.marionetteOnWeb`. This
/// driver does not second-guess that: if no isolate exposes the extensions, the
/// connect fails with an actionable message rather than hanging.
class MarionetteDriver implements LiveDriver {
  MarionetteDriver({VmServiceConnector? connector, Duration? settle})
      : _connector = connector ?? VmServiceConnector(),
        settle = settle ?? const Duration(milliseconds: 250);

  final VmServiceConnector _connector;
  String? _target;
  String? _bindingVersion;

  /// How long to wait after an action before returning.
  ///
  /// Marionette acknowledges a tap once the pointer event is dispatched, not
  /// once the app has rebuilt, so a caller that asserts immediately can observe
  /// the screen from before the action. The driver lives in a different isolate
  /// and cannot await the app's frames, so this is a wall-clock allowance
  /// instead. Scenarios that must not race should use `wait_for_element`, which
  /// polls for the real condition rather than guessing a duration.
  final Duration settle;

  /// Actions after which the app needs a chance to rebuild.
  static const Set<String> _settlingTools = {
    'tap',
    'secondary_tap',
    'double_tap',
    'long_press',
    'enter_text',
    'press_key',
    'swipe',
    'pinch_zoom',
    'scroll_to',
    'set_device_config',
    'hot_reload',
    'hot_restart',
    'press_back_button',
  };

  @override
  String get kind => 'marionette';

  @override
  bool get isConnected => _connector.isConnected;

  @override
  String? get target => _target;

  /// Version reported by the app's binding, once connected.
  String? get bindingVersion => _bindingVersion;

  /// Every tool marionette can serve.
  ///
  /// `connect` and `disconnect` are intentionally absent: they are modelled by
  /// [connect] and [disconnect] rather than dispatched through [execute], so a
  /// scenario can never leave the session half-attached by calling them
  /// mid-batch.
  static const Set<String> toolNames = {
    'get_interactive_elements',
    'get_logs',
    'take_screenshots',
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
    'set_device_config',
    'list_custom_extensions',
    'call_custom_extension',
    'hot_reload',
    'hot_restart',
    // Added by this package, not upstream: marionette can read the element
    // tree, so assertions do not need a second transport.
    'assert_text_contains',
    'assert_visible',
    'assert_gone',
    'wait_for_element',
  };

  @override
  Set<String> get supportedTools => toolNames;

  @override
  Future<Map<String, Object?>> connect(String target) async {
    await disconnect();
    try {
      await _connector.connect(target);
    } on Object catch (e) {
      throw DriverException(
        'Could not attach marionette to $target: $e',
        hint: 'Start the app with "flutter run" (debug mode) and pass the VM '
            'service URI it prints, e.g. ws://127.0.0.1:PORT/TOKEN=/ws.\n'
            'The app must call MarionetteBinding.ensureInitialized(); on web '
            'also pass --dart-define=E2E_MARIONETTE_ON_WEB=true.',
      );
    }
    _target = target;

    // Upstream refuses the connection on a version mismatch. Reporting it
    // instead is deliberate: a unified server may legitimately be pointed at an
    // app built from a different fork, and the caller needs to see both values
    // to judge that, not just a refusal.
    String? version;
    String? versionNote;
    try {
      version = await _connector.getVersion();
      _bindingVersion = version;
    } on Object catch (e) {
      versionNote = 'binding did not report a version ($e)';
    }

    bool sessionReports = false;
    try {
      sessionReports = await _connector.getSessionReportsEnabled();
    } on Object {
      sessionReports = false;
    }

    return {
      'ok': true,
      'target': target,
      'bindingVersion': version,
      'sessionReportsEnabled': sessionReports,
      if (versionNote != null) 'note': versionNote,
      'tools': supportedTools.length,
    };
  }

  @override
  Future<void> disconnect() async {
    if (_connector.isConnected) {
      await _connector.disconnect();
    }
    _target = null;
    _bindingVersion = null;
  }

  @override
  Future<Map<String, Object?>> execute(
    String tool,
    Map<String, Object?> args,
  ) async {
    if (!isConnected) {
      throw DriverException(
        'Not connected to any app. Call connect_app first with the VM service '
        'URI.',
      );
    }
    final handler = _handlers[tool];
    if (handler == null) {
      throw DriverException(
        'marionette has no tool "$tool". Available: '
        '${supportedTools.toList()..sort()}',
      );
    }
    try {
      final result = await handler(args);
      if (_settlingTools.contains(tool) && settle > Duration.zero) {
        await Future<void>.delayed(settle);
      }
      return result;
    } on NotConnectedException catch (e) {
      throw DriverException(e.toString());
    } on VmServiceExtensionException catch (e) {
      // Carries the app-side detail, which is otherwise lost: the RPC error's
      // message is only "Extension X failed", and the exception and stack live
      // in the remaining fields.
      return {
        'ok': false,
        'error': e.message,
        'errorCode': e.errorCode,
        if (e.error != null) 'detail': e.error,
        if (e.stackTrace != null) 'appStack': e.stackTrace,
      };
    }
  }

  /// Translates marionette's wire responses into the `ok`-carrying shape the
  /// executor and report formatter expect.
  ///
  /// Marionette signals failure with an `error` field (and sometimes a `code`),
  /// never by throwing across the VM service boundary, so the presence of that
  /// field is the only reliable failure signal.
  static Map<String, Object?> _normalize(Map<String, dynamic> raw) {
    final result = <String, Object?>{...raw};
    final error = raw['error'];
    if (error != null) {
      result['ok'] = false;
      result['error'] = error.toString();
    } else {
      result['ok'] = true;
    }
    return result;
  }

  static Map<String, dynamic> _raw(Map<String, Object?> result) =>
      result.map((k, v) => MapEntry(k, v));

  static Map<String, dynamic> _matcher(Map<String, Object?> args) =>
      buildMatcher(_raw(args));

  static void _requireSelector(Map<String, dynamic> matcher, String tool) {
    if (!hasSelector(matcher)) {
      throw DriverException(
        'marionette "$tool" needs a selector. Pass one of "key", "identifier", '
        '"text", "type", or "coordinates". "ancestor_keys" only narrows the '
        'search and cannot select an element on its own.',
      );
    }
  }

  static double? _double(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _int(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _bool(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  static List<String> _ancestors(Map<String, Object?> args) =>
      (args['ancestor_keys'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      const <String>[];

  /// Pulls the element list out of an `interactiveElements` response.
  ///
  /// The exact envelope has changed across marionette versions, so this accepts
  /// the known shapes and degrades to an empty list rather than throwing: an
  /// assertion that cannot find its subject should report "not found", not
  /// crash the batch.
  static List<Map<String, dynamic>> _elementsOf(Map<String, dynamic> raw) {
    for (final field in const ['elements', 'nodes', 'interactiveElements']) {
      final value = raw[field];
      if (value is List) {
        return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    }
    if (raw['type'] != null || raw['key'] != null) return [raw];
    return const [];
  }

  static bool _matchesScope(Map<String, dynamic> element, List<String> scope) {
    if (scope.isEmpty) return true;
    // Best effort: marionette scopes server-side, so an element that came back
    // is already in scope. When the element reports its ancestry, verify it.
    final chain = element['ancestorKeys'] ?? element['ancestor_keys'];
    if (chain is! List) return true;
    final actual = chain.map((e) => e.toString()).toList();
    if (actual.length < scope.length) return false;
    return scope.asMap().entries.every((e) => actual[e.key] == e.value);
  }

  /// Whether [element] satisfies a selector and sits inside [scope].
  ///
  /// Every non-null criterion must match, so `key` plus `text` narrows rather
  /// than widens.
  static bool _elementMatches(
    Map<String, dynamic> element, {
    String? key,
    String? identifier,
    String? text,
    required List<String> scope,
  }) {
    if (!_matchesScope(element, scope)) return false;
    if (key != null && element['key']?.toString() != key) return false;
    if (identifier != null && element['identifier']?.toString() != identifier) {
      return false;
    }
    if (text != null && !(element['text']?.toString() ?? '').contains(text)) {
      return false;
    }
    return true;
  }

  /// Describes a selector for an error message.
  static String _describe(Map<String, Object?> args) {
    final parts = <String>[
      if (args['key'] != null) 'key "${args['key']}"',
      if (args['identifier'] != null) 'identifier "${args['identifier']}"',
      if (args['text'] != null) 'text "${args['text']}"',
    ];
    final scope = _ancestors(args);
    if (scope.isNotEmpty) parts.add('under ${scope.join(" > ")}');
    return parts.isEmpty ? 'the requested element' : parts.join(' ');
  }

  late final Map<String, Future<Map<String, Object?>> Function(Map<String, Object?>)>
      _handlers = {
    'get_interactive_elements': (args) async {
      final compaction = args['compaction']?.toString();
      final invalid = invalidCompactionError(compaction);
      if (invalid != null) throw DriverException(invalid);
      return _normalize(await _connector.getInteractiveElements(
        ancestorKeys: _ancestors(args),
        compaction: compaction,
      ));
    },
    'get_logs': (_) async => _normalize(await _connector.getLogs()),
    'take_screenshots': (_) async =>
        _normalize(await _connector.takeScreenshots()),
    'tap': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'tap');
      return _normalize(await _connector.tap(matcher));
    },
    'secondary_tap': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'secondary_tap');
      return _normalize(await _connector.secondaryTap(matcher));
    },
    'double_tap': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'double_tap');
      return _normalize(await _connector.doubleTap(
        matcher,
        delayMs: _int(args, 'delay_ms'),
      ));
    },
    'long_press': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'long_press');
      return _normalize(await _connector.longPress(
        matcher,
        durationMs: _int(args, 'duration_ms'),
      ));
    },
    'swipe': (args) async {
      final payload = _matcher(args);
      // Coordinate mode needs no selector; element mode does.
      final coordinateMode = args.containsKey('startX') && args.containsKey('endX');
      if (!coordinateMode) _requireSelector(payload, 'swipe');
      for (final field in const [
        'direction',
        'distance',
        'startX',
        'startY',
        'endX',
        'endY',
      ]) {
        if (args.containsKey(field)) payload[field] = args[field];
      }
      return _normalize(await _connector.swipe(payload));
    },
    'pinch_zoom': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'pinch_zoom');
      final scale = _double(args, 'scale');
      if (scale == null) {
        throw DriverException('marionette "pinch_zoom" requires a "scale".');
      }
      return _normalize(await _connector.pinchZoom(
        matcher,
        scale: scale,
        startDistance: _double(args, 'start_distance'),
      ));
    },
    'press_back_button': (_) async =>
        _normalize(await _connector.pressBackButton()),
    'scroll_to': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'scroll_to');
      return _normalize(await _connector.scrollToElement(matcher));
    },
    'enter_text': (args) async {
      final matcher = _matcher(args);
      _requireSelector(matcher, 'enter_text');
      final input = args['text']?.toString() ?? args['input']?.toString();
      if (input == null) {
        throw DriverException(
          'marionette "enter_text" requires the text to type in "text".',
        );
      }
      return _normalize(await _connector.enterText(matcher, input));
    },
    'press_key': (args) async {
      final key = args['key']?.toString();
      if (key == null || key.isEmpty) {
        throw DriverException('marionette "press_key" requires a "key".');
      }
      final modifiers = args['modifiers']?.toString();
      final invalid = invalidModifiersError(modifiers);
      if (invalid != null) throw DriverException(invalid);
      return _normalize(await _connector.pressKey(key, modifiers: modifiers));
    },
    'set_device_config': (args) async {
      final brightness = args['platform_brightness']?.toString();
      final invalid = invalidBrightnessError(brightness);
      if (invalid != null) throw DriverException(invalid);
      return _normalize(await _connector.setDeviceConfig(
        textScale: _double(args, 'text_scale'),
        boldText: args.containsKey('bold_text') ? _bool(args, 'bold_text') : null,
        platformBrightness: brightness,
        reset: _bool(args, 'reset'),
      ));
    },
    'list_custom_extensions': (_) async =>
        _normalize(await _connector.listExtensions()),
    'call_custom_extension': (args) async {
      final name = args['extension']?.toString() ?? args['name']?.toString();
      if (name == null || name.isEmpty) {
        throw DriverException(
          'marionette "call_custom_extension" requires an "extension" name '
          'without the "ext.flutter." prefix.',
        );
      }
      final rawArgs = args['args'];
      final payload = rawArgs is Map
          ? rawArgs.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{};
      return _normalize(await _connector.callCustomExtension(name, payload));
    },
    'hot_reload': (_) async => {'ok': await _connector.hotReload()},
    'hot_restart': (_) async => {'ok': await _connector.hotRestart()},
    'assert_visible': (args) async {
      final scope = _ancestors(args);
      final response = await _connector.getInteractiveElements(
        ancestorKeys: scope,
        compaction: 'compact',
      );
      final found = _elementsOf(response).any((e) => _elementMatches(
            e,
            key: args['key']?.toString(),
            identifier: args['identifier']?.toString(),
            text: args['text']?.toString(),
            scope: scope,
          ));
      return {
        'ok': found,
        'found': found,
        if (!found) 'error': '${_describe(args)} is not on screen',
        'actual': found ? 'present' : 'absent',
        'expected': 'present',
      };
    },
    'assert_gone': (args) async {
      final scope = _ancestors(args);
      final response = await _connector.getInteractiveElements(
        ancestorKeys: scope,
        compaction: 'compact',
      );
      final present = _elementsOf(response).any((e) => _elementMatches(
            e,
            key: args['key']?.toString(),
            identifier: args['identifier']?.toString(),
            text: args['text']?.toString(),
            scope: scope,
          ));
      return {
        // assert_gone passes when the element is absent, so invert.
        'ok': !present,
        'found': present,
        if (present) 'error': '${_describe(args)} is still on screen',
        'actual': present ? 'present' : 'absent',
        'expected': 'absent',
      };
    },
    'assert_text_contains': (args) async {
      final expected = args['contains']?.toString() ??
          args['expected']?.toString() ??
          args['text']?.toString();
      if (expected == null || expected.isEmpty) {
        throw DriverException(
          'assert_text_contains requires the expected substring in "contains".',
        );
      }
      final scope = _ancestors(args);
      final response = await _connector.getInteractiveElements(
        ancestorKeys: scope,
        compaction: args['compaction']?.toString(),
      );
      final elements = _elementsOf(response)
          .where((e) => _matchesScope(e, scope))
          .toList();

      final key = args['key']?.toString();
      final identifier = args['identifier']?.toString();
      final candidates = elements.where((e) => _elementMatches(
            e,
            key: key,
            identifier: identifier,
            scope: scope,
          )).toList();

      if (candidates.isEmpty) {
        return {
          'ok': false,
          'error': 'no interactive element matching ${_describe(args)}',
          'actual': '',
          'expected': expected,
        };
      }
      final actual = candidates.map((e) => e['text']?.toString() ?? '').join(' ');
      final contains = actual.contains(expected);
      return {
        'ok': contains,
        if (!contains) 'error': 'text does not contain the expected substring',
        'actual': actual,
        'expected': expected,
        'matchedElements': candidates.length,
      };
    },
    'wait_for_element': (args) async {
      final timeoutMs = _int(args, 'timeout_ms') ?? 5000;
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      final key = args['key']?.toString();
      final identifier = args['identifier']?.toString();
      final text = args['text']?.toString();
      final scope = _ancestors(args);

      Map<String, dynamic>? last;
      while (true) {
        final response = await _connector.getInteractiveElements(
          ancestorKeys: scope,
          compaction: 'compact',
        );
        final elements = _elementsOf(response);
        for (final element in elements) {
          if (_elementMatches(
            element,
            key: key,
            identifier: identifier,
            text: text,
            scope: scope,
          )) {
            return {'ok': true, 'found': true, 'element': element};
          }
        }
        if (DateTime.now().isAfter(deadline)) {
          last = elements.isEmpty ? null : elements.first;
          return {
            'ok': false,
            'found': false,
            'error': 'element not found within ${timeoutMs}ms',
            if (last != null) 'nearest': last,
          };
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    },
  };
}
