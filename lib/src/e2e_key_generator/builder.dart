import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import 'src/key_injector.dart';

/// build_runner builder: rewrites opted-in `.dart` files in place and emits a
/// `.e2e_keys.dart` copy for the build graph.
Builder e2eKeyInjectorBuilder(BuilderOptions options) => _E2eKeyInjectorBuilder();

class _E2eKeyInjectorBuilder implements Builder {
  static const _injector = KeyInjector();

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.e2e_keys.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (inputId.path.endsWith('.g.dart') ||
        inputId.path.endsWith('.e2e_keys.dart') ||
        inputId.path.contains('.dart_tool')) {
      return;
    }

    final source = await buildStep.readAsString(inputId);
    if (!source.contains('// e2e:auto_keys') &&
        !RegExp(r'@E2eAutoKey\b').hasMatch(source)) {
      return;
    }

    final updated = _injector.inject(source: source, path: inputId.path);
    if (updated == source) return;

    await buildStep.writeAsString(inputId.changeExtension('.e2e_keys.dart'), updated);

    // Rewrite the primary source on disk (run build_runner from the app package root).
    final diskPath = p.join(Directory.current.path, inputId.path);
    final diskFile = File(diskPath);
    if (await diskFile.exists()) {
      await diskFile.writeAsString(updated);
    }
  }
}
