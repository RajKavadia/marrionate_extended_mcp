// flutter_skill keeps its app-side binding in `lib/e2e_flutter_skill.dart` and
// its driver code in `lib/src/**`. Only the latter is pure Dart, and only the
// latter is imported here, so this file never pulls `dart:ui` into the server.
// ignore_for_file: implementation_imports

import 'package:marrionate_extended_mcp/src/flutter_skill/src/bridge/cdp_driver.dart';
import 'package:marrionate_extended_mcp/src/flutter_skill/src/drivers/app_driver.dart';
import 'package:marrionate_extended_mcp/src/flutter_skill/src/drivers/flutter_driver.dart';

import 'live_driver.dart';

/// Which transport a [FlutterSkillDriver] is using.
enum FlutterSkillMode {
  /// Dart VM service. Native and debug-web targets.
  native,

  /// Chrome DevTools Protocol against a served page.
  web,
}

/// Drives a live app through flutter-skill's transports.
///
/// Two very different mechanisms sit behind one interface:
///
/// - [FlutterSkillMode.native] talks to `ext.flutter.flutter_skill.*` over the
///   Dart VM service, so it sees the real element tree and can use `ValueKey`.
/// - [FlutterSkillMode.web] drives Chrome over CDP. It has no knowledge of
///   Flutter at all: it finds elements by DOM role, aria-label, or text, and
///   dispatches real mouse events.
///
/// That difference is the main reason marionette is preferred where both work.
/// A Flutter web app paints to a canvas and only exposes a DOM tree once
/// semantics are materialized, so the CDP path additionally requires the app to
/// call `ensureSemantics()` (see the demo app's `E2E_SEMANTICS` switch).
class FlutterSkillDriver implements LiveDriver {
  FlutterSkillDriver._(this._driver, this._mode, this._target);

  /// Attaches to a native or debug-web target over the Dart VM service.
  factory FlutterSkillDriver.native(String wsUri) {
    final client = FlutterSkillClient(wsUri);
    return FlutterSkillDriver._(client, FlutterSkillMode.native, wsUri);
  }

  /// Attaches to a served page over the Chrome DevTools Protocol.
  factory FlutterSkillDriver.web({
    required String url,
    int cdpPort = 9222,
    bool launchChrome = true,
    bool headless = false,
    String? chromePath,
  }) {
    final driver = CdpDriver(
      url: url,
      port: cdpPort,
      launchChrome: launchChrome,
      headless: headless,
      chromePath: chromePath,
    );
    return FlutterSkillDriver._(driver, FlutterSkillMode.web, url);
  }

  final AppDriver _driver;
  final FlutterSkillMode _mode;
  String? _target;

  /// The underlying transport, for callers that need a capability it lacks.
  AppDriver get raw => _driver;

  /// The VM-service client, when in native mode.
  ///
  /// Exposed because several useful calls (`press_key`, `scroll_to`,
  /// `wait_for_element`) exist only on the VM-service client and have no CDP
  /// equivalent in this vendored copy.
  FlutterSkillClient? get nativeClient =>
      _mode == FlutterSkillMode.native ? _driver as FlutterSkillClient : null;

  @override
  String get kind => 'flutterSkill';

  @override
  bool get isConnected => _driver.isConnected;

  @override
  String? get target => _target;

  /// True when talking CDP, i.e. selectors are DOM-based rather than keys.
  bool get isWeb => _mode == FlutterSkillMode.web;

  /// Tools available on both transports.
  static const Set<String> sharedTools = {
    'get_interactive_elements',
    'tap',
    'enter_text',
    'swipe',
    'take_screenshots',
    'get_logs',
    'clear_logs',
    'hot_reload',
    'assert_text_contains',
  };

  /// Tools that need the Dart VM service, so they are withheld on web.
  static const Set<String> nativeOnlyTools = {
    'press_key',
    'scroll_to',
    'wait_for_element',
    'long_press',
    'double_tap',
    'tap_at',
    'get_text',
    'get_route',
    'go_back',
    'hot_restart',
  };

  /// Every tool this driver can serve in [mode].
  ///
  /// Registration uses the native superset; the server filters [tools/list] and
  /// [tools/call] against the live session so a web session never advertises a
  /// tool its transport cannot honour.
  static Set<String> catalogFor(FlutterSkillMode mode) => mode == FlutterSkillMode.web
      ? sharedTools
      : {...sharedTools, ...nativeOnlyTools};

  @override
  Set<String> get supportedTools => catalogFor(_mode);

  @override
  Future<Map<String, Object?>> connect(String target) async {
    if (isConnected) await _driver.disconnect();
    try {
      await _driver.connect();
    } on Object catch (e) {
      throw DriverException(
        'Could not attach flutter-skill to $target: $e',
        hint: isWeb
            ? 'The page must be served over http and Chrome must be reachable '
                'on the CDP port. Flutter web also needs its semantics tree '
                'materialized for selectors to resolve.'
            : 'Start the app with "flutter run" (debug mode), pass the VM '
                'service URI, and call FlutterSkillBinding.ensureInitialized().',
      );
    }
    _target = target;
    return {
      'ok': true,
      'target': target,
      'mode': _mode.name,
      'framework': _driver.frameworkName,
      'tools': supportedTools.length,
    };
  }

  @override
  Future<void> disconnect() async {
    if (_driver.isConnected) await _driver.disconnect();
    _target = null;
  }

  @override
  Future<Map<String, Object?>> execute(
    String tool,
    Map<String, Object?> args,
  ) async {
    if (!isConnected) {
      throw DriverException(
        'Not connected to any app. Call connect_app first.',
      );
    }
    if (!supportedTools.contains(tool)) {
      throw DriverException(
        isWeb && nativeOnlyTools.contains(tool)
            ? 'flutter-skill tool "$tool" needs the Dart VM service, which the '
                'CDP transport does not use. It is unavailable on web.'
            : 'flutter-skill has no tool "$tool". Available: '
                '${supportedTools.toList()..sort()}',
      );
    }

    final key = args['key']?.toString();
    final text = args['text']?.toString();
    final native = nativeClient;

    try {
      switch (tool) {
        case 'get_interactive_elements':
          return {
            'ok': true,
            'elements': await _driver.getInteractiveElements(),
          };
        case 'tap':
          if (key == null && text == null) {
            throw DriverException('"tap" needs a "key" or "text".');
          }
          return _wrap(await _driver.tap(key: key, text: text));
        case 'enter_text':
          final input = args['contains']?.toString() ??
              args['input']?.toString() ??
              text;
          if (input == null) {
            throw DriverException(
              '"enter_text" needs the text to type in "text".',
            );
          }
          return _wrap(await _driver.enterText(key, input));
        case 'swipe':
          final direction = args['direction']?.toString() ?? 'left';
          final distance = _double(args, 'distance') ?? 300;
          final ok = await _driver.swipe(
            direction: direction,
            distance: distance,
            key: key,
          );
          return {'ok': ok, if (!ok) 'error': 'swipe did not complete'};
        case 'take_screenshots':
          final image = await _driver.takeScreenshot();
          if (image == null) {
            return {'ok': false, 'error': 'screenshot returned no image'};
          }
          return {'ok': true, 'image': image, 'encoding': 'base64'};
        case 'get_logs':
          return {'ok': true, 'logs': await _driver.getLogs()};
        case 'clear_logs':
          await _driver.clearLogs();
          return {'ok': true};
        case 'hot_reload':
          await _driver.hotReload();
          return {'ok': true};
        case 'hot_restart':
          await native!.hotRestart();
          return {'ok': true};
        case 'press_key':
          final pressKey = args['key']?.toString();
          if (pressKey == null || pressKey.isEmpty) {
            throw DriverException('"press_key" needs a "key".');
          }
          final modifiers = (args['modifiers'] as List?)
              ?.map((e) => e.toString())
              .toList();
          return _wrap(await native!.pressKey(pressKey, modifiers: modifiers));
        case 'scroll_to':
          if (key == null && text == null) {
            throw DriverException('"scroll_to" needs a "key" or "text".');
          }
          return _wrap(await native!.scrollTo(key: key, text: text));
        case 'wait_for_element':
          final found = await native!.waitForElement(
            key: key,
            text: text,
            timeout: _int(args, 'timeout_ms') ?? 5000,
          );
          return {
            'ok': found,
            'found': found,
            if (!found) 'error': 'element not found before the timeout',
          };
        case 'long_press':
          final ok = await native!.longPress(
            key: key,
            text: text,
            duration: _int(args, 'duration_ms') ?? 500,
          );
          return {'ok': ok, if (!ok) 'error': 'long press did not complete'};
        case 'double_tap':
          final ok = await native!.doubleTap(key: key, text: text);
          return {'ok': ok, if (!ok) 'error': 'double tap did not complete'};
        case 'tap_at':
          await native!.tapAt(
            _double(args, 'x') ?? 0,
            _double(args, 'y') ?? 0,
          );
          return {'ok': true};
        case 'get_text':
          return _textResult(await _readText(key, text));
        case 'get_route':
          return {'ok': true, 'route': await native!.getCurrentRoute()};
        case 'go_back':
          return {'ok': await native!.goBack()};
        case 'assert_text_contains':
          final expected = args['contains']?.toString() ??
              args['expected']?.toString() ??
              text;
          if (expected == null || expected.isEmpty) {
            throw DriverException(
              '"assert_text_contains" needs the expected substring in '
              '"contains".',
            );
          }
          final actual = await _readText(key, text);
          final contains = actual.contains(expected);
          return {
            'ok': contains,
            if (!contains) 'error': 'text does not contain the expected substring',
            'actual': actual,
            'expected': expected,
          };
        default:
          throw DriverException('unhandled flutter-skill tool "$tool"');
      }
    } on DriverException {
      rethrow;
    } on Object catch (e) {
      throw DriverException('flutter-skill "$tool" failed: $e');
    }
  }

  /// Reads text from a keyed field (native) or the page (web).
  Future<String> _readText(String? key, String? text) async {
    final native = nativeClient;
    if (native != null) {
      final value = await native.getTextValue(key);
      if (value != null) return value;
    }
    if (_driver is CdpDriver) {
      return _driver.getVisibleText();
    }
    if (text != null) return text;
    return '';
  }

  /// Normalizes flutter-skill's `{success: bool}` envelopes to `ok`.
  static Map<String, Object?> _wrap(Map<String, dynamic> raw) {
    final result = <String, Object?>{...raw};
    final success = raw['success'];
    final ok = success is bool ? success : (raw['error'] == null);
    result['ok'] = ok;
    if (!ok && raw['error'] != null) {
      result['error'] = raw['error'].toString();
    } else if (!ok) {
      result['error'] = 'the app reported the action did not succeed';
    }
    return result;
  }

  static Map<String, Object?> _textResult(String value) =>
      value.isEmpty ? {'ok': false, 'error': 'no text found'} : {'ok': true, 'text': value};

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
}
