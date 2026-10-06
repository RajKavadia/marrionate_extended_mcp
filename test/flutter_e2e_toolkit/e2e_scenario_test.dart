import 'dart:convert';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart';
import 'package:test/test.dart';

void main() {
  group('E2eStep.fromJson tolerates all three vendor shapes', () {
    test('inline arguments', () {
      final step = E2eStep.fromJson({
        'step': 1,
        'action': 'tap',
        'key': 'submit_button',
      });

      expect(step.action, 'tap');
      expect(step.args['key'], 'submit_button');
      // Metadata keys must not leak into tool arguments.
      expect(step.args.containsKey('step'), isFalse);
      expect(step.args.containsKey('action'), isFalse);
    });

    test('nested args block', () {
      final step = E2eStep.fromJson({
        'step': 2,
        'action': 'enter_text',
        'args': {'key': 'name_field', 'text': 'Ada'},
      });

      expect(step.action, 'enter_text');
      expect(step.args['key'], 'name_field');
      expect(step.args['text'], 'Ada');
    });

    test('recorded tool/params shape', () {
      final step = E2eStep.fromJson({
        'step': 3,
        'tool': 'tap',
        'params': {'key': 'items_counter'},
      });

      expect(step.action, 'tap');
      expect(step.args['key'], 'items_counter');
      expect(step.args.containsKey('params'), isFalse);
    });

    test('method is accepted as a verb alias', () {
      final step = E2eStep.fromJson({
        'step': 1,
        'method': 'assert_visible',
        'params': {'key': 'submit_button'},
      });

      expect(step.action, 'assert_visible');
    });

    test('nested block wins over inline duplicate', () {
      final step = E2eStep.fromJson({
        'action': 'tap',
        'args': {'key': 'from_nested'},
        'key': 'from_inline',
      });

      expect(step.args['key'], 'from_nested');
    });

    test('missing verb is a FormatException naming the keys seen', () {
      expect(
        () => E2eStep.fromJson({'step': 1, 'key': 'x'}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('missing an action'))),
      );
    });
  });

  group('E2eScenario.fromJson', () {
    test('reads commands and renumbers densely from 1', () {
      final scenario = E2eScenario.fromJson({
        'name': 'profile_submit_flow',
        'commands': [
          {'action': 'tap', 'key': 'submit_button'},
          {'action': 'assert_visible', 'key': 'submit_button', 'step': 99},
        ],
      });

      expect(scenario.name, 'profile_submit_flow');
      expect(scenario.commands.map((c) => c.step), [1, 2]);
    });

    test('accepts steps/actions/tools as the command list key', () {
      for (final key in ['steps', 'actions', 'tools']) {
        final scenario = E2eScenario.fromJson({
          'name': 'n_$key',
          key: [
            {'action': 'tap', 'key': 'items_counter'},
          ],
        });
        expect(scenario.commands, hasLength(1), reason: 'key "$key"');
      }
    });

    test('missing name is rejected', () {
      expect(
        () => E2eScenario.fromJson({
          'commands': [
            {'action': 'tap', 'key': 'x'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-object command is rejected with its index', () {
      expect(
        () => E2eScenario.fromJson({
          'name': 'bad',
          'commands': ['not-an-object'],
        }),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('command 1'))),
      );
    });

    test('round-trips through toJson and back', () {
      final original = E2eScenario.fromJson({
        'name': 'round_trip',
        'commands': [
          {'action': 'tap', 'key': 'submit_button'},
          {
            'action': 'assert_text_contains',
            'key': 'items_counter',
            'text': '5'
          },
        ],
      });

      final decoded =
          E2eScenario.decode(jsonEncode(original.toJson()));

      expect(decoded.name, original.name);
      expect(decoded.commands.length, original.commands.length);
      expect(decoded.commands[1].args['text'], '5');
    });
  });

  group('variable interpolation', () {
    test('substitutes whole-value matches', () {
      final scenario = E2eScenario.fromJson({
        'name': 'templated',
        'variables': {'profile_name': 'Ada Lovelace'},
        'commands': [
          {
            'action': 'enter_text',
            'args': {'key': 'name_field', 'text': 'profile_name'}
          },
        ],
      }).interpolate();

      expect(scenario.commands.first.args['text'], 'Ada Lovelace');
    });

    test('leaves partially-matching strings untouched', () {
      final scenario = E2eScenario.fromJson({
        'name': 'partial',
        'variables': {'who': 'Ada'},
        'commands': [
          {
            'action': 'assert_text_contains',
            'args': {'key': 'items_counter', 'text': 'hello who'}
          },
        ],
      }).interpolate();

      expect(scenario.commands.first.args['text'], 'hello who');
    });

    test('non-string values are stringified', () {
      final scenario = E2eScenario.fromJson({
        'name': 'numeric_var',
        'variables': {'target_count': 5},
        'commands': [
          {
            'action': 'assert_element_count',
            'args': {'key': 'items_list', 'count': 'target_count'}
          },
        ],
      }).interpolate();

      expect(scenario.commands.first.args['count'], '5');
    });
  });
}
