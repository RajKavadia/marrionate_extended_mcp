import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';
import 'package:test/test.dart';

void main() {
  const exporter = McpScenarioExporter();

  group('McpScenarioExporter', () {
    test('maps tap to mcp_tap under marionetteFirst', () {
      expect(exporter.wireNameForAction('tap'), 'mcp_tap');
      expect(exporter.wireNameForAction('enter_text'), 'mcp_enter_text');
    });

    test('maps scroll to mcp_scroll_to', () {
      expect(exporter.wireNameForAction('scroll'), 'mcp_scroll_to');
    });

    test('exportScript produces JSON-RPC tools/call sequence', () {
      const scenario = E2eScenario(
        name: 'demo',
        commands: [
          E2eStep(step: 1, action: 'tap', args: {'key': 'home_profile'}),
          E2eStep(
            step: 2,
            action: 'assert_text_contains',
            args: {'key': 'profile_result', 'text': 'ok'},
          ),
        ],
      );

      final script = exporter.exportScript(scenario);
      expect(script.instructions, hasLength(2));
      expect(script.attach.params['name'], 'connect_app');
      expect(
        script.attach.params['arguments'],
        containsPair('target', McpInstructionScript.attachTargetPlaceholder),
      );

      final first = script.instructions.first.toJson();
      expect(first['method'], 'tools/call');
      expect(first['params'], {
        'name': 'mcp_tap',
        'arguments': {'key': 'home_profile'},
      });
    });

    test('exportBatchCall wraps commands in execute_batch', () {
      const scenario = E2eScenario(
        name: 'demo',
        commands: [
          E2eStep(step: 1, action: 'tap', args: {'key': 'a'}),
        ],
      );
      final batch = exporter.exportBatchCall(scenario);
      final args = batch.params['arguments']! as Map;
      expect(batch.params['name'], 'execute_batch');
      expect(args['commands'], isList);
    });
  });
}
