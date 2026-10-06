// Resolves dependencies for every package in the repository.
//
// Vendored packages cannot be Dart workspace members, because `dart pub publish`
// rejects any package declaring `resolution: workspace`. That means there is no
// single `dart pub get` at the root, and this walks each package instead.
//
// Usage:
//   dart run tool/bootstrap.dart
import 'dart:io';

/// Packages to resolve, in dependency order.
const List<String> packageDirs = [
  'vendor/flutter_skill',
  'vendor/marionette_flutter',
  'vendor/marionette_mcp',
  'vendor/marionette_logging',
  'vendor/marionette_logger',
  'vendor/marionette_cli',
  'packages/flutter_e2e_toolkit',
  'packages/flutter-e2e-mcp',
  'packages/app',
];

/// Whether [dir]'s pubspec depends on the Flutter SDK.
bool _isFlutterPackage(String pubspecText) =>
    RegExp(r'^\s+flutter:\s*$', multiLine: true).hasMatch(pubspecText);

Future<void> main(List<String> args) async {
  final scriptDir = File.fromUri(Platform.script).parent;
  final root = Directory('${scriptDir.path}${Platform.pathSeparator}..');

  final failures = <String>[];

  for (final relative in packageDirs) {
    final dir = Directory('${root.path}${Platform.pathSeparator}$relative');
    if (!dir.existsSync()) {
      stderr.writeln('SKIP     $relative (missing)');
      failures.add(relative);
      continue;
    }

    final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (!pubspec.existsSync()) {
      stderr.writeln('SKIP     $relative (no pubspec.yaml)');
      continue;
    }

    // Flutter packages must resolve through `flutter pub get`, because their
    // dependency on the Flutter SDK is not resolvable by the standalone Dart
    // tool.
    final useFlutter = _isFlutterPackage(pubspec.readAsStringSync());
    final executable = useFlutter ? 'flutter' : 'dart';

    stdout.write('RESOLVE  $relative ($executable pub get) ... ');
    final result = await Process.run(
      executable,
      ['pub', 'get'],
      workingDirectory: dir.path,
      runInShell: true,
    );

    if (result.exitCode == 0) {
      stdout.writeln('ok');
    } else {
      stdout.writeln('FAILED');
      stderr.writeln(result.stderr.toString().trim());
      failures.add(relative);
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('\nFAILED for ${failures.length} package(s): '
        '${failures.join(", ")}');
    exit(1);
  }
  stdout.writeln('\nResolved ${packageDirs.length} package(s).');
}
