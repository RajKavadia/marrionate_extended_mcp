import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';
import 'package:test/test.dart';

void main() {
  group('InteractionRecorder', () {
    test('notifies listeners with the full session', () {
      final seen = <Map<String, Object?>>[];
      final recorder = InteractionRecorder()..addListener(seen.add);
      recorder.start();
      recorder.recordTap('name_field');
      recorder.recordDoubleTap('name_field');
      recorder.stop();

      expect(seen, hasLength(4));
      expect(seen.first['recording'], isTrue);
      expect(seen[1]['steps'], hasLength(1));
      final replaced = (seen[2]['steps'] as List).single as Map;
      expect(replaced['action'], 'double_tap');
      expect(seen.last['recording'], isFalse);
    });

    test('records taps and enter_text', () {
      final recorder = InteractionRecorder()..start();
      recorder.recordTap('home_profile');
      recorder.recordEnterText('name_field', 'Ada');
      recorder.stop();

      final scenario = recorder.toScenario();
      expect(scenario.commands, hasLength(2));
      expect(scenario.commands[0].action, 'tap');
      expect(scenario.commands[1].args['text'], 'Ada');
    });

    test('dedupes rapid taps on the same key', () {
      final recorder = InteractionRecorder()..start();
      recorder.recordTap('a');
      recorder.recordTap('a');
      expect(recorder.steps, hasLength(1));
    });

    test('exports to Marionette MCP wire names', () {
      final recorder = InteractionRecorder()..start();
      recorder.recordTap('submit_button');
      recorder.stop();

      final script =
          const McpScenarioExporter().exportScript(recorder.toScenario());
      expect(script.instructions.single.params['name'], 'mcp_tap');
    });

    test('upgrades a tap into mcp_double_tap and exports swipe and pinch', () {
      final recorder = InteractionRecorder()..start();
      recorder.recordTap('mouse_tap_target');
      recorder.recordDoubleTap('mouse_tap_target');
      recorder.recordSecondaryTap('mouse_tap_target');
      recorder.recordSwipe('page_view', 'left', distance: 280);
      recorder.recordPinchZoom('zoomable', 1.5);
      recorder.recordPinchZoom('zoomable', 1.0);
      recorder.stop();

      expect(recorder.steps.map((s) => s.action).toList(), [
        'double_tap',
        'secondary_tap',
        'swipe',
        'pinch_zoom',
      ]);
      expect(recorder.steps[2].args['direction'], 'left');

      final names = const McpScenarioExporter()
          .exportScript(recorder.toScenario())
          .instructions
          .map((m) => m.params['name'])
          .toList();
      expect(names, [
        'mcp_double_tap',
        'mcp_secondary_tap',
        'mcp_swipe',
        'mcp_pinch_zoom',
      ]);
    });
  });
}
