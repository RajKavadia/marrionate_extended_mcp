import 'dart:io';

import 'package:marrionate_extended_mcp/src/marionette_cli/src/cli/marionette_command_runner.dart';

Future<void> main(List<String> arguments) async {
  final exitCode = await MarionetteCommandRunner().run(arguments);
  exit(exitCode);
}
