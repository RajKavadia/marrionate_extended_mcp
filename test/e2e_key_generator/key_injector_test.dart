import 'package:marrionate_extended_mcp/src/e2e_key_generator/e2e_key_generator.dart';
import 'package:test/test.dart';

void main() {
  const injector = KeyInjector();

  test('injects keys on catalog widgets when e2e:auto_keys is set', () {
    const input = '''
// e2e:auto_keys
import 'package:flutter/material.dart';

class Sample extends StatelessWidget {
  const Sample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Hello recorder'),
        ElevatedButton(
          onPressed: () {},
          child: const Text('Go'),
        ),
      ],
    );
  }
}
''';

    final output = injector.inject(source: input, path: 'sample.dart');
    expect(output, contains('key: const ValueKey<String>'));
    expect(output, contains('elevated_button'));
    expect(
      RegExp(r"Text\('Hello recorder', key: const ValueKey<String>").hasMatch(output),
      isTrue,
    );
    expect(
      RegExp(r'ElevatedButton\(\s*key: const ValueKey<String>').hasMatch(output),
      isTrue,
    );
  });

  test('skips files without opt-in marker', () {
    const input = '''
import 'package:flutter/material.dart';

Widget w() => Text('plain');
''';
    expect(injector.inject(source: input, path: 'plain.dart'), input);
  });

  test('does not duplicate when key already present', () {
    const input = '''
// e2e:auto_keys
import 'package:flutter/material.dart';

Widget w() => Text('x', key: const ValueKey<String>('existing'));
''';
    expect(injector.inject(source: input, path: 'x.dart'), input);
  });
}
