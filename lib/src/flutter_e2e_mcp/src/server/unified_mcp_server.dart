import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../drivers/driver_factory.dart';
import '../drivers/flutter_skill_driver.dart';
import '../drivers/live_driver.dart';
import '../drivers/marionette_driver.dart';
import '../replay/batch_executor.dart';
import '../replay/scenario_replayer.dart';
import '../report/report_formatter.dart';
import 'live_tools.dart';
import 'tool_registry.dart';

/// An inbound JSON-RPC request.
class McpRequest {
  McpRequest({
    required this.method,
    this.params = const {},
    this.id,
  });

  factory McpRequest.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    return McpRequest(
      method: json['method']?.toString() ?? '',
      params: json['params'] is Map
          ? Map<String, Object?>.from(json['params'] as Map)
          : const {},
      id: id is num ? id.toInt() : null,
    );
  }

  final String method;
  final Map<String, Object?> params;

  /// Absent for notifications, which must not be answered.
  final int? id;

  bool get isNotification => id == null;
}

/// A JSON-RPC response.
class McpResponse {
  McpResponse({
    required this.id,
    this.result,
    this.errorCode,
    this.errorMessage,
  });

  /// Builds a success response.
  factory McpResponse.ok(int id, Map<String, Object?> result) =>
      McpResponse(id: id, result: result);

  /// Builds an error response.
  factory McpResponse.error(int id, int code, String message) =>
      McpResponse(id: id, errorCode: code, errorMessage: message);

  final int id;
  final Map<String, Object?>? result;
  final int? errorCode;
  final String? errorMessage;

  bool get isError => errorCode != null;

  Map<String, Object?> toJson() {
    if (isError) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': errorCode, 'message': errorMessage},
      };
    }
    return {'jsonrpc': '2.0', 'id': id, 'result': result ?? const {}};
  }
}

/// How tool names are presented to clients.
enum ToolPrefixPolicy {
  /// Expose `mcp_tap` and `skill_tap` plus flat aliases.
  ///
  /// Both vendored stacks define a `tap` with different argument shapes, so the
  /// canonical names are namespaced while `tap` still resolves for existing
  /// agent configurations.
  namespaced,

  /// Expose only canonical names, no aliases.
  namespacedOnly,

  /// Expose flat names only; last registration wins on collision.
  flat,
}

/// MCP protocol error codes.
class McpErrorCode {
  const McpErrorCode._();

  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;

  /// A tool cannot run against the connected app or platform.
  ///
  /// Chosen so clients can distinguish "you asked for something impossible
  /// here" from a genuine internal failure, and to avoid a client timeout.
  static const int toolUnavailable = -32001;

  /// A tool ran and reported an assertion failure.
  static const int assertionFailed = -32002;
}

/// One MCP server over stdio exposing both automation tool sets.
///
/// Responsibilities kept deliberately narrow: framing, JSON-RPC dispatch,
/// tool exposure, and capability gating. Actual driving of the app lives in the
/// registered handlers.
class UnifiedMcpServer {
  UnifiedMcpServer({
    required this.registry,
    required this.executor,
    this.prefixPolicy = ToolPrefixPolicy.namespaced,
    this.serverName = 'flutter-e2e-mcp',
    this.serverVersion = '0.1.0',
    DriverFactory? driverFactory,
  })  : replayer = ScenarioReplayer(executor: executor),
        driverFactory = driverFactory ?? const DriverFactory();

  final ToolRegistry registry;
  final BatchExecutor executor;
  final ToolPrefixPolicy prefixPolicy;
  final String serverName;
  final String serverVersion;
  final DriverFactory driverFactory;

  /// Replays scenario files through [executor].
  final ScenarioReplayer replayer;

  LiveSession? _session;

  /// The app currently attached, if any.
  LiveSession? get session => _session;

  /// Replaces the attached app, disconnecting the previous one.
  ///
  /// Called by `connect_app`. The old session is torn down first so a failed
  /// reconnect cannot leave two drivers holding the same app.
  Future<void> adoptSession(LiveSession session) async {
    await _session?.driver.disconnect();
    _session = session;
  }

  /// Detaches the current app, if any.
  Future<void> dropSession() async {
    await _session?.driver.disconnect();
    _session = null;
  }

  StreamSubscription<String>? _stdinSubscription;
  bool _running = false;

  bool get isRunning => _running;

  /// Serves MCP over stdin/stdout until stdin closes.
  ///
  /// One JSON-RPC message per line, which is the framing both vendored servers
  /// use. Writes go to stdout; all diagnostics go to stderr so they cannot
  /// corrupt the protocol stream.
  Future<void> serveStdio() async {
    _running = true;
    stderr.writeln('[$serverName] ready on stdio '
        '(${registry.length} tools, policy ${prefixPolicy.name})');

    final lines = stdin
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    // Requests are handled strictly in order.
    //
    // `listen` does not await an async callback, so without this queue a client
    // that pipelines `tools/call` followed by `shutdown` has both dispatched at
    // once: shutdown disposes the VM service while the tool call is still
    // awaiting its response, and the app reports "Service connection disposed".
    // Serializing also makes step ordering in a batch meaningful.
    var queue = Future<void>.value();

    _stdinSubscription = lines.listen(
      (line) {
        if (line.trim().isEmpty) return;
        queue = queue.then((_) async {
          try {
            final response = await handleLine(line);
            if (response != null) {
              stdout.writeln(jsonEncode(response.toJson()));
            }
          } catch (e) {
            // A failure here must not poison the queue for later requests.
            stderr.writeln('[$serverName] request failed: $e');
          }
        });
      },
      onError: (Object error) {
        stderr.writeln('[$serverName] stdin error: $error');
      },
      onDone: () async {
        _running = false;
        stderr.writeln('[$serverName] stdin closed, shutting down');
        // Let queued work finish before tearing the session down.
        await queue;
        await stop();
      },
      cancelOnError: false,
    );
  }

  /// Stops serving.
  ///
  /// Also releases the attached app. Without this the VM-service or CDP socket
  /// stays open, the Dart event loop never drains, and the process hangs on exit
  /// rather than terminating when its host closes stdin.
  Future<void> stop() async {
    await _stdinSubscription?.cancel();
    _stdinSubscription = null;
    _running = false;
    await dropSession();
  }

  /// Parses and dispatches one line, returning null for notifications.
  Future<McpResponse?> handleLine(String line) async {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return McpResponse.error(0, McpErrorCode.parseError, 'invalid JSON');
    }
    if (decoded is! Map) {
      return McpResponse.error(
          0, McpErrorCode.invalidRequest, 'request must be an object');
    }

    final request = McpRequest.fromJson(Map<String, Object?>.from(decoded));
    final response = await handleRequest(request);
    return request.isNotification ? null : response;
  }

  /// Dispatches a request to its handler.
  Future<McpResponse> handleRequest(McpRequest request) async {
    final id = request.id ?? 0;
    try {
      switch (request.method) {
        case 'initialize':
          return McpResponse.ok(id, _initializeResult());
        case 'notifications/initialized':
          return McpResponse.ok(id, const {});
        case 'ping':
          return McpResponse.ok(id, const {});
        case 'tools/list':
          return McpResponse.ok(id, {
            'tools': _visibleTools(),
          });
        case 'tools/call':
          return await _handleToolsCall(id, request);
        case 'shutdown':
          await stop();
          return McpResponse.ok(id, const {});
        default:
          return McpResponse.error(id, McpErrorCode.methodNotFound,
              'unknown method "${request.method}"');
      }
    } catch (e) {
      return McpResponse.error(id, McpErrorCode.invalidRequest, e.toString());
    }
  }

  Map<String, Object?> _initializeResult() => {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {'name': serverName, 'version': serverVersion},
      };

  /// Tools visible to clients, honouring the prefix policy.
  ///
  /// Before a connection every tool is advertised, because an agent needs to
  /// know what it can call before it knows where the app is running. Once a
  /// session exists, tools the attached driver cannot serve are withheld so the
  /// client never plans around a call that can only fail.
  List<Map<String, Object?>> _visibleTools() {
    final tools = registry.list().where(_isAvailable).toList();
    return tools.map((t) {
      final json = t.toJson();
      json['name'] = prefixPolicy == ToolPrefixPolicy.flat ? t.name : t.wireName;
      if (prefixPolicy == ToolPrefixPolicy.namespaced) {
        json['aliases'] = t.aliases.toList()..sort();
      }
      return json;
    }).toList();
  }

  /// Whether the attached driver can serve [tool].
  bool _isAvailable(ToolDescriptor tool) {
    final session = _session;
    if (session == null) return true;
    return toolAvailableFor(tool.source, tool.name, session.driver);
  }

  /// Explains why [tool] cannot run, naming the alternative that can.
  ///
  /// The server cannot tell a web app from a native one over a VM service URI,
  /// so gating keys off the transport that is actually attached rather than a
  /// platform guess. That also means marionette is available on Flutter web in
  /// debug builds, which it is not in release builds where no VM service exists
  /// at all and therefore no connection can be made in the first place.
  String _unavailableMessage(ToolDescriptor tool, LiveSession session) {
    final other = tool.source == ToolSource.marionette
        ? 'skill_${tool.name}'
        : 'mcp_${tool.name}';
    if (!session.supportsMarionette && tool.source == ToolSource.marionette) {
      return 'Tool "${tool.name}" needs the Dart VM service, but this session is '
          'a web page driven over the Chrome DevTools Protocol. Use $other, '
          'which speaks CDP. Note that a Flutter web app paints to a canvas, so '
          'CDP can only resolve selectors once the app has materialized its '
          'semantics tree.';
    }
    if (tool.source == ToolSource.marionette) {
      return 'Tool "${tool.name}" belongs to marionette, but this session is '
          'attached through flutter-skill. Use $other.';
    }
    return 'Tool "${tool.name}" belongs to flutter-skill, but this session is '
        'attached through marionette. Use $other, or reconnect with connect_app '
        'and let the server pick the transport from the target.';
  }

  Future<McpResponse> _handleToolsCall(int id, McpRequest request) async {
    final rawName = request.params['name']?.toString();
    if (rawName == null || rawName.isEmpty) {
      return McpResponse.error(id, McpErrorCode.invalidParams,
          'tools/call requires a "name"');
    }

    // tools/list advertises namespaced names, so tools/call must accept them too.
    // The registry keys by source, so `mcp_tap` and `skill_tap` resolve to
    // different tools rather than colliding on the bare name.
    final tool = registry.resolve(rawName);
    if (tool == null) {
      return McpResponse.error(id, McpErrorCode.methodNotFound,
          'unknown tool "$rawName". Available: '
          '${registry.allCallableNames.join(", ")}');
    }

    final session = _session;
    if (session != null && !toolAvailableFor(tool.source, tool.name, session.driver)) {
      return McpResponse.error(
        id,
        McpErrorCode.toolUnavailable,
        _unavailableMessage(tool, session),
      );
    }

    final rawArgs = request.params['arguments'];
    final args = rawArgs is Map
        ? Map<String, Object?>.from(rawArgs)
        : <String, Object?>{};

    try {
      final result = await tool.handler(
        args,
        ToolContext(recorder: null, session: session),
      );
      return McpResponse.ok(id, result);
    } on ToolCapabilityException catch (e) {
      return McpResponse.error(id, McpErrorCode.toolUnavailable, e.message);
    } on DriverException catch (e) {
      return McpResponse.error(id, McpErrorCode.invalidParams, e.toString());
    } catch (e) {
      return McpResponse.error(id, McpErrorCode.invalidRequest, e.toString());
    }
  }

  /// Registers the tools this server adds on top of the vendored sets.
  ///
  /// Kept separate from [UnifiedMcpServer] construction so the tool set can be
  /// composed and tested without a live server.
  void registerBuiltinTools({String? scenariosPath}) {
    registry.registerAll([
      ToolDescriptor(
        name: 'capability',
        description: 'Reports what the connected target can actually run, and '
            'names the alternative for anything withheld. Before connecting, '
            'every tool is advertised.',
        source: ToolSource.e2e,
        handler: (args, context) async {
          final session = context.session ?? _session;
          final base = <String, Object?>{
            'registeredTools': registry.length,
            'advertisedTools': _visibleTools().length,
            'prefixPolicy': prefixPolicy.name,
          };
          if (session == null) {
            return {
              ...base,
              'connected': false,
              'note': 'Not connected, so the full tool set is advertised. Call '
                  'connect_app to narrow it to what the attached driver can '
                  'serve.',
            };
          }
          final mode =
              session.isWeb ? FlutterSkillMode.web : FlutterSkillMode.native;
          return {
            ...base,
            'connected': true,
            // Nested rather than spread: toJson reports the driver's own
            // connection state, which is a different fact from "a session
            // exists" and would otherwise overwrite it.
            'session': session.toJson(),
            'marionetteTools': MarionetteDriver.toolNames
                .where((n) =>
                    toolAvailableFor(ToolSource.marionette, n, session.driver))
                .toList()
              ..sort(),
            'flutterSkillTools': FlutterSkillDriver.catalogFor(mode)
                .where((n) => toolAvailableFor(
                    ToolSource.flutterSkill, n, session.driver))
                .toList()
              ..sort(),
          };
        },
      ),
      ToolDescriptor(
        name: 'connect_app',
        description: 'Attaches to a running Flutter app and picks the '
            'transport. A Dart VM service URI (ws://127.0.0.1:PORT/TOKEN=/ws) '
            'selects marionette, which reads the Flutter element tree by '
            'ValueKey. A page URL selects the Chrome DevTools Protocol, which '
            'sees only DOM. Override with "kind" when the target is ambiguous.',
        source: ToolSource.e2e,
        handler: (args, context) async {
          final target = args['target']?.toString() ?? args['uri']?.toString();
          if (target == null || target.isEmpty) {
            return {
              'success': false,
              'error': 'provide "target": a VM service URI or a page URL',
            };
          }

          DriverKind? kind;
          final kindName = args['kind']?.toString();
          if (kindName != null) {
            for (final candidate in DriverKind.values) {
              if (candidate.name == kindName) kind = candidate;
            }
            if (kind == null) {
              return {
                'success': false,
                'error': 'unknown kind "$kindName". Use one of: '
                    '${DriverKind.values.map((k) => k.name).join(", ")}',
              };
            }
          }

          try {
            final session = await driverFactory.connect(
              target,
              kind: kind,
              cdpPort: (args['cdp_port'] as num?)?.toInt() ?? 9222,
              launchChrome: args['launch_chrome'] as bool? ?? true,
              headless: args['headless'] as bool? ?? false,
              chromePath: args['chrome_path']?.toString(),
              url: args['url']?.toString(),
            );
            await adoptSession(session);
            return {'success': true, ...session.toJson()};
          } on DriverException catch (e) {
            return {'success': false, 'error': e.toString()};
          }
        },
        inputSchema: {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'description': 'VM service URI, page URL, or cdp://host:port.',
            },
            'kind': {
              'type': 'string',
              'enum': ['vmService', 'webPage', 'cdp'],
            },
            'url': {
              'type': 'string',
              'description': 'Page URL, required when target is cdp://.',
            },
            'cdp_port': {'type': 'integer'},
            'launch_chrome': {'type': 'boolean'},
            'headless': {'type': 'boolean'},
            'chrome_path': {'type': 'string'},
          },
          'required': ['target'],
        },
        aliases: {'connect'},
      ),
      ToolDescriptor(
        name: 'disconnect_app',
        description: 'Detaches from the app. Safe to call when not connected.',
        source: ToolSource.e2e,
        handler: (args, context) async {
          final current = _session;
          if (current == null) {
            return {'success': true, 'note': 'nothing was connected'};
          }
          await dropSession();
          return {'success': true, 'target': current.target};
        },
        aliases: {'disconnect'},
      ),
      ToolDescriptor(
        name: 'execute_batch',
        description: 'Runs a list of interaction and assertion steps in order. '
            'Accepts "actions" or "commands"; each step may carry inline '
            'arguments or a nested "args" object. Honours stop_on_failure and '
            'step_delay_ms.',
        source: ToolSource.e2e,
        handler: (args, context) => executor.execute(args),
        inputSchema: {
          'type': 'object',
          'properties': {
            'actions': {'type': 'array', 'items': {'type': 'object'}},
            'commands': {'type': 'array', 'items': {'type': 'object'}},
            'stop_on_failure': {'type': 'boolean'},
            'step_delay_ms': {'type': 'integer'},
          },
        },
        aliases: {'batch'},
      ),
      ToolDescriptor(
        name: 'replay_scenario',
        description: 'Loads a JSON scenario file and replays every step. '
            'Scenarios are JSON only; no Dart test code is generated.',
        source: ToolSource.e2e,
        handler: (args, context) async {
          final path = args['path']?.toString() ?? scenariosPath;
          if (path == null) {
            return {
              'success': false,
              'error': 'provide "path", or start the server with a scenarios '
                  'directory',
            };
          }
          final report = await replayer.replayDirectory(Directory(path));
          return report.toJson();
        },
        inputSchema: {
          'type': 'object',
          'properties': {'path': {'type': 'string'}},
        },
      ),
      ToolDescriptor(
        name: 'report',
        description: 'Renders the last replay report as text, json, or junit.',
        source: ToolSource.e2e,
        handler: (args, context) async {
          final format = ReportFormat.values.firstWhere(
            (f) => f.name == (args['format']?.toString() ?? 'text'),
            orElse: () => ReportFormat.text,
          );
          final path = args['path']?.toString() ?? scenariosPath;
          if (path == null) {
            return {
              'success': false,
              'error': 'provide "path" to a scenario directory',
            };
          }
          final report = await replayer.replayDirectory(Directory(path));
          return {'success': true, 'format': format.name, 'report': ReportFormatter.render(report, format)};
        },
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'format': {'type': 'string', 'enum': ['text', 'json', 'junit']},
          },
        },
      ),
    ]);
  }
}
