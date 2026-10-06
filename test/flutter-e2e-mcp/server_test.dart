import 'dart:convert';
import 'dart:io';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

import 'package:marrionate_extended_mcp/src/flutter_e2e_mcp/flutter_e2e_mcp.dart';
import 'package:test/test.dart';

/// Builds a registry with stub tools that record their invocations.
ToolRegistry buildStubRegistry({
  Set<String> failingActions = const {},
  Set<String> throwingActions = const {},
  List<String>? callLog,
}) {
  final registry = ToolRegistry();

  for (final action in ['tap', 'enter_text', 'scroll']) {
    registry.register(ToolDescriptor(
      name: action,
      description: 'stub $action',
      source: action == 'tap' ? ToolSource.flutterSkill : ToolSource.e2e,
      handler: (args, context) async {
        // Log before branching, so the call log proves which steps actually
        // reached the handler even when the step then fails.
        callLog?.add('$action:${args['key'] ?? ''}');
        if (throwingActions.contains(action)) {
          throw StateError('$action exploded');
        }
        if (failingActions.contains(action)) {
          return {'ok': false, 'error': '$action deliberately failed'};
        }
        return {'ok': true, 'actual': 'stub'};
      },
    ));
  }

  registry.register(ToolDescriptor(
    name: 'assert_visible',
    description: 'stub assertion',
    source: ToolSource.flutterSkill,
    handler: (args, context) async {
      callLog?.add('assert_visible:${args['key']}');
      final present = args['present'] != false;
      return {
        'ok': present,
        if (!present) 'error': 'element ${args['key']} not found',
        'expected': 'present',
        'actual': present ? 'present' : 'absent',
      };
    },
  ));

  registry.register(ToolDescriptor(
    name: 'assert_text_contains',
    description: 'stub plain-text assertion',
    source: ToolSource.e2e,
    handler: (args, context) async {
      final haystack = args['actualText']?.toString() ?? '';
      final needle = args['text']?.toString() ?? '';
      final found = haystack.contains(needle);
      return {
        'ok': found,
        if (!found) 'error': '"$needle" not found in "$haystack"',
        'expected': needle,
        'actual': haystack,
      };
    },
  ));

  registry.register(ToolDescriptor(
    name: 'get_interactive_elements',
    description: 'stub marionette tool',
    source: ToolSource.marionette,
    handler: (args, context) async => {'elements': <String>[]},
    // Mirrors the real server: a namespaced canonical name with the flat
    // upstream name kept as an alias.
    aliases: {'inspect_elements'},
  ));

  return registry;
}

void main() {
  group('ToolRegistry', () {
    test('resolves canonical names before aliases', () {
      final registry = buildStubRegistry();

      expect(registry.resolve('tap')?.name, 'tap');
      expect(registry.resolve('inspect_elements')?.name, 'get_interactive_elements',
          reason: 'alias must resolve to the owning tool');
    });

    test('rejects duplicate names within the same source', () {
      final registry = buildStubRegistry();
      final source = registry.resolve('tap')!.source;

      expect(
        () => registry.register(ToolDescriptor(
          name: 'tap',
          description: 'dup',
          source: source,
          handler: (args, context) async => const {},
        )),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('allows the same bare name from two different sources', () {
      // Both vendored stacks define `tap`. Namespacing, not the bare name, is
      // what keeps them apart.
      final registry = ToolRegistry();
      Future<Map<String, Object?>> handler(
        Map<String, Object?> args,
        ToolContext context,
      ) async =>
          const {};

      registry.register(ToolDescriptor(
        name: 'tap',
        description: 'marionette tap',
        source: ToolSource.marionette,
        handler: handler,
      ));
      registry.register(ToolDescriptor(
        name: 'tap',
        description: 'flutter-skill tap',
        source: ToolSource.flutterSkill,
        handler: handler,
      ));

      expect(registry.resolve('mcp_tap')!.source, ToolSource.marionette);
      expect(registry.resolve('skill_tap')!.source, ToolSource.flutterSkill);
      // A bare name resolves to the first source that owns it.
      expect(registry.resolve('tap')!.source, ToolSource.marionette);
      expect(registry.length, 2);
    });

    test('rejects an alias already claimed by another tool', () {
      final registry = buildStubRegistry();

      expect(
        () => registry.register(ToolDescriptor(
          name: 'other',
          description: 'squatter',
          source: ToolSource.e2e,
          handler: (args, context) async => const {},
          aliases: {'inspect_elements'},
        )),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('filters by source', () {
      final registry = buildStubRegistry();

      expect(registry.list(source: ToolSource.marionette), hasLength(1));
      expect(
        registry.list(source: ToolSource.marionette).single.name,
        'get_interactive_elements',
      );
    });
  });

  group('BatchExecutor argument shapes', () {
    late BatchExecutor executor;

    setUp(() {
      executor = BatchExecutor(registry: buildStubRegistry());
    });

    test('reads the step list from "actions"', () async {
      final result = await executor.execute({
        'actions': [
          {'action': 'tap', 'key': 'submit_button'},
        ],
      });

      expect(result['success'], isTrue);
    });

    test('reads the step list from "commands"', () async {
      final result = await executor.execute({
        'commands': [
          {'tool': 'tap', 'params': {'key': 'submit_button'}},
        ],
      });

      expect(result['success'], isTrue);
    });

    test('honours stop_on_failure', () async {
      final log = <String>[];
      final executor = BatchExecutor(
        registry: buildStubRegistry(
          failingActions: {'tap'},
          callLog: log,
        ),
      );

      final result = await executor.execute({
        'actions': [
          {'action': 'tap', 'key': 'home_screen'},
          {'action': 'tap', 'key': 'items_screen'},
        ],
        'stop_on_failure': true,
      });

      expect(result['success'], isFalse);
      expect(result['stoppedEarly'], isTrue);
      expect(result['failedStep'], 1);
      // Second step is reported as skipped, not silently dropped.
      final reports = result['stepReports'] as List;
      expect(reports, hasLength(2));
      expect((reports[1] as Map)['error'], contains('skipped'));
      expect(log, ['tap:home_screen'], reason: 'the second tap must not have run');
    });

    test('continues past failures without stop_on_failure', () async {
      final log = <String>[];
      final executor = BatchExecutor(
        registry: buildStubRegistry(
          failingActions: {'tap'},
          callLog: log,
        ),
      );

      final result = await executor.execute({
        'actions': [
          {'action': 'tap', 'key': 'home_screen'},
          {'action': 'tap', 'key': 'items_screen'},
        ],
      });

      expect(result['stoppedEarly'], isFalse);
      expect(result['failedCount'], 2);
      expect(log, ['tap:home_screen', 'tap:items_screen']);
    });

    test('reports an unknown action without throwing', () async {
      // Validation is disabled so this exercises the executor's own
      // unknown-action path; with validation on the batch is refused up front.
      final lenient = BatchExecutor(
        registry: buildStubRegistry(),
        validateFirst: false,
      );

      final result = await lenient.execute({
        'actions': [
          {'action': 'teleport', 'key': 'home_screen'},
        ],
      });

      expect(result['success'], isFalse);
      final reports = result['stepReports'] as List;
      expect(((reports.first as Map)['error'] as String),
          contains('unknown action'));
    });

    test('validation refuses an unknown action before anything runs', () async {
      final result = await executor.execute({
        'actions': [
          {'action': 'teleport', 'key': 'home_screen'},
        ],
      });

      expect(result['success'], isFalse);
      expect(result['stepReports'], isEmpty);
      expect((result['validationIssues'] as List).join(),
          contains('unsupported action'));
    });

    test('rejects a malformed request shape', () async {
      expect((await executor.execute({'nope': []}))['success'], isFalse);
      expect((await executor.execute({'actions': ['oops']}))['success'], isFalse);
    });

    test('validation failure runs nothing', () async {
      final log = <String>[];
      final executor = BatchExecutor(
        registry: buildStubRegistry(callLog: log),
      );

      final result = await executor.execute({
        'actions': [
          {'action': 'tap', 'key': 'home_screen'},
          // Not in KeyRegistry, so the batch must be refused up front.
          {'action': 'tap', 'key': 'not_a_registered_key'},
        ],
      });

      expect(result['success'], isFalse);
      expect(result['stepReports'], isEmpty);
      expect(log, isEmpty, reason: 'no step may run when validation fails');
      expect((result['validationIssues'] as List), isNotEmpty);
    });

    test('surfaces a handler exception as a failed step', () async {
      final executor = BatchExecutor(
        registry: buildStubRegistry(throwingActions: {'tap'}),
      );

      final result = await executor.execute({
        'actions': [
          {'action': 'tap', 'key': 'home_screen'},
        ],
      });

      expect(result['success'], isFalse);
      final reports = result['stepReports'] as List;
      expect(((reports.first as Map)['error'] as String), contains('exploded'));
    });
  });

  group('assert_text_contains', () {
    test('passes when the plain text contains the needle', () async {
      final executor = BatchExecutor(registry: buildStubRegistry());

      final result = await executor.execute({
        'actions': [
          {
            'action': 'assert_text_contains',
            'key': 'items_counter',
            'text': '5',
            'actualText': 'Count: 5',
          },
        ],
      });

      expect(result['success'], isTrue);
    });

    test('fails with expected and actual when absent', () async {
      final executor = BatchExecutor(registry: buildStubRegistry());

      final result = await executor.execute({
        'actions': [
          {
            'action': 'assert_text_contains',
            'key': 'items_counter',
            'text': '9',
            'actualText': 'Count: 5',
          },
        ],
      });

      expect(result['success'], isFalse);
      final report = (result['stepReports'] as List).first as Map;
      expect(report['expected'], '9');
      expect(report['actual'], 'Count: 5');
    });
  });

  group('UnifiedMcpServer', () {
    late UnifiedMcpServer server;
    late ToolRegistry registry;

    setUp(() {
      registry = buildStubRegistry();
      server = UnifiedMcpServer(
        registry: registry,
        executor: BatchExecutor(registry: registry),
      )..registerBuiltinTools();
    });

    test('initialize reports server identity', () async {
      final response = await server.handleRequest(
        McpRequest(method: 'initialize', id: 1),
      );

      final result = response.result!;
      final info = result['serverInfo'] as Map;
      expect(info['name'], 'flutter-e2e-mcp');
      expect(info['version'], '0.1.0');
      expect(result['protocolVersion'], isNotNull);
    });

    test('tools/list namespaces names and publishes aliases', () async {
      final response = await server.handleRequest(
        McpRequest(method: 'tools/list', id: 2),
      );

      final tools = (response.result!['tools'] as List).cast<Map>();
      final names = tools.map((t) => t['name']).toSet();

      expect(names, contains('skill_tap'));
      expect(names, contains('mcp_get_interactive_elements'));
      expect(names, contains('execute_batch'));

      final marionette =
          tools.firstWhere((t) => t['name'] == 'mcp_get_interactive_elements');
      expect((marionette['aliases'] as List), contains('inspect_elements'));
    });

    test('tools/call resolves a prefixed name', () async {
      final response = await server.handleRequest(McpRequest(
        method: 'tools/call',
        id: 3,
        params: {
          'name': 'skill_assert_visible',
          'arguments': {'key': 'submit_button'},
        },
      ));

      expect(response.isError, isFalse);
      expect(response.result!['ok'], isTrue);
    });

    test('tools/call resolves a flat alias', () async {
      final response = await server.handleRequest(McpRequest(
        method: 'tools/call',
        id: 4,
        params: {
          'name': 'assert_visible',
          'arguments': {'key': 'submit_button'},
        },
      ));

      expect(response.isError, isFalse);
    });

    test('unknown tool is methodNotFound and lists alternatives', () async {
      final response = await server.handleRequest(McpRequest(
        method: 'tools/call',
        id: 5,
        params: {'name': 'no_such_tool'},
      ));

      expect(response.errorCode, McpErrorCode.methodNotFound);
      expect(response.errorMessage, contains('Available'));
    });

    test('unknown method is rejected', () async {
      final response = await server.handleRequest(
        McpRequest(method: 'does/not/exist', id: 6),
      );

      expect(response.errorCode, McpErrorCode.methodNotFound);
    });

    test('malformed JSON is a parse error, not a crash', () async {
      final response = await server.handleLine('{not json');

      expect(response!.errorCode, McpErrorCode.parseError);
    });

    test('notifications get no response', () async {
      // initialize-style notification carries no id.
      final response = await server.handleLine(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );

      expect(response, isNull);
    });

    group('capability gating follows the connection, not a platform guess', () {
      late UnifiedMcpServer live;

      /// A VM-service session, which is what native *and* debug-web targets are.
      LiveSession vmServiceSession() => LiveSession(
            driver: MarionetteDriver(),
            kind: DriverKind.vmService,
            target: 'ws://127.0.0.1:1/token=/ws',
          );

      /// A CDP session, which never touches the Dart VM service.
      LiveSession webSession() => LiveSession(
            driver: FlutterSkillDriver.web(url: 'http://localhost:1/'),
            kind: DriverKind.webPage,
            target: 'http://localhost:1/',
          );

      Set<String> listedNames(McpResponse response) =>
          ((response.result!['tools'] as List).cast<Map>())
              .map((t) => t['name'].toString())
              .toSet();

      setUp(() {
        final registry = ToolRegistry();
        registerAllLiveTools(registry);
        live = UnifiedMcpServer(
          registry: registry,
          executor: BatchExecutor(registry: registry),
        )..registerBuiltinTools();
      });

      test('every tool is advertised before connecting', () async {
        final names = listedNames(
          await live.handleRequest(McpRequest(method: 'tools/list', id: 1)),
        );

        expect(names, contains('mcp_get_interactive_elements'));
        expect(names, contains('skill_tap'));
      });

      test('a CDP session withholds marionette and names the alternative',
          () async {
        await live.adoptSession(webSession());

        final names = listedNames(
          await live.handleRequest(McpRequest(method: 'tools/list', id: 2)),
        );
        expect(names, isNot(contains('mcp_get_interactive_elements')));
        expect(names, contains('skill_tap'));

        final call = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 3,
          params: {'name': 'mcp_get_interactive_elements', 'arguments': {}},
        ));
        expect(call.errorCode, McpErrorCode.toolUnavailable);
        expect(call.errorMessage, contains('skill_get_interactive_elements'));
        expect(call.errorMessage, contains('DevTools'));
      });

      test('a CDP session withholds VM-service-only skill tools', () async {
        await live.adoptSession(webSession());

        final names = listedNames(
          await live.handleRequest(McpRequest(method: 'tools/list', id: 4)),
        );

        expect(names, isNot(contains('skill_press_key')));
        expect(names, contains('skill_tap'));
      });

      test('a marionette session serves mcp_ tools and withholds skill_ ones',
          () async {
        await live.adoptSession(vmServiceSession());

        final names = listedNames(
          await live.handleRequest(McpRequest(method: 'tools/list', id: 5)),
        );

        expect(names, contains('mcp_get_interactive_elements'));
        expect(names, isNot(contains('skill_tap')));
      });

      test('a disconnected marionette call says connect, not unavailable',
          () async {
        final call = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 6,
          params: {'name': 'mcp_tap', 'arguments': {'key': 'submit_button'}},
        ));

        expect(call.errorCode, McpErrorCode.toolUnavailable);
        expect(call.errorMessage, contains('connect_app'));
      });

      test('capability reports the attached transport', () async {
        await live.adoptSession(vmServiceSession());

        final response = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 7,
          params: {'name': 'capability', 'arguments': {}},
        ));

        expect(response.result!['connected'], isTrue);
        expect((response.result!['session'] as Map)['isWeb'], isFalse);
        expect(response.result!['marionetteTools'], isNotEmpty);
        expect(response.result!['flutterSkillTools'], isEmpty);
      });

      test('capability explains that nothing is connected yet', () async {
        final response = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 8,
          params: {'name': 'capability', 'arguments': {}},
        ));

        expect(response.result!['connected'], isFalse);
        expect(response.result!['note'], contains('connect_app'));
      });

      test('connect_app rejects an unknown kind without touching the network',
          () async {
        final response = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 9,
          params: {
            'name': 'connect_app',
            'arguments': {'target': 'ws://x/y=/ws', 'kind': 'carrier-pigeon'},
          },
        ));

        expect(response.result!['success'], isFalse);
        expect(response.result!['error'], contains('unknown kind'));
        expect(live.session, isNull);
      });

      test('connect_app requires a target', () async {
        final response = await live.handleRequest(McpRequest(
          method: 'tools/call',
          id: 10,
          params: {'name': 'connect_app', 'arguments': {}},
        ));

        expect(response.result!['success'], isFalse);
        expect(response.result!['error'], contains('target'));
      });
    });
  });

  group('ReportFormatter', () {
    late ReplayReport report;

    setUp(() async {
      final registry = buildStubRegistry(failingActions: {'tap'});
      final replayer = ScenarioReplayer(
        executor: BatchExecutor(registry: registry),
      );
      report = await replayer.replayScenarios([
        // Passing: assert_visible succeeds on the stub.
        E2eScenario.fromJson({'name': 'passing_case', 'commands': [
          {'action': 'assert_visible', 'key': 'submit_button'},
        ]}),
        // Failing: tap is configured to fail, and the run stops at step 1.
        E2eScenario.fromJson({'name': 'failing_case', 'commands': [
          {'action': 'tap', 'key': 'items_counter'},
          {'action': 'tap', 'key': 'about_settings_button'},
        ]}),
      ]);
    });

    test('text names the failing step', () {
      final text = ReportFormatter.toText(report);

      expect(text, contains('failing_case'));
      expect(text, contains('step 1'));
      expect(text, contains('1/2 scenarios passed'));
    });

    test('json reports counts', () {
      final decoded = jsonDecode(ReportFormatter.toJson(report)) as Map;

      expect(decoded['total'], 2);
      expect(decoded['passed'], 1);
      expect(decoded['failed'], 1);
      expect(decoded['allPassed'], isFalse);
    });

    test('junit is well-formed and carries the failure', () {
      final xml = ReportFormatter.toJunit(report);

      expect(xml, startsWith('<?xml version="1.0"'));
      expect(xml, contains('failures="1"'));
      expect(xml, contains('name="failing_case"'));
      expect(xml, contains('<failure'));
      expect(xml.trim(), endsWith('</testsuites>'));
    });

    test('junit escapes XML metacharacters', () {
      final xml = ReportFormatter.toJunit(ReplayReport([
        ScenarioOutcome(
          name: 'a & b <c>',
          passed: false,
          error: 'x < y && z > w',
        ),
      ]));

      expect(xml, contains('a &amp; b &lt;c&gt;'));
      expect(xml, isNot(contains('a & b <c>')));
    });
  });

  group('ScenarioReplayer', () {
    test('stopOnFailure halts at the first failing scenario', () async {
      final replayer = ScenarioReplayer(
        executor: BatchExecutor(
          registry: buildStubRegistry(failingActions: {'tap'}),
        ),
      );

      final result = await replayer.replayScenarios(
        [
          E2eScenario.fromJson({'name': 'one', 'commands': [{'action': 'tap', 'key': 'home_screen'}]}),
          E2eScenario.fromJson({'name': 'two', 'commands': [{'action': 'tap', 'key': 'items_screen'}]}),
        ],
        stopOnFailure: true,
      );

      expect(result.scenarios, hasLength(1));
      expect(result.failed, 1);
    });

    test('a directory with only unparseable json fails loudly', () async {
      final dir = Directory.systemTemp.createTempSync('e2e_bad_json');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}${Platform.pathSeparator}not_a_scenario.json')
          .writeAsStringSync('{"just":"config"}');

      final replayer = ScenarioReplayer(
        executor: BatchExecutor(registry: buildStubRegistry()),
      );
      final result = await replayer.replayDirectory(dir);

      expect(result.allPassed, isFalse);
      expect(result.failures.first.error, contains('missing "name"'));
    });

    test('a missing directory fails loudly', () async {
      final replayer = ScenarioReplayer(
        executor: BatchExecutor(registry: buildStubRegistry()),
      );

      final result = await replayer.replayDirectory(
        Directory('definitely/not/here'),
      );

      expect(result.allPassed, isFalse);
      expect(result.failures.single.error, contains('does not exist'));
    });
  });
}

