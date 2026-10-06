// ignore_for_file: avoid_print
//
// Converts JSON scenario files into MCP JSON-RPC instruction scripts for live apps.
//
// Usage:
//   dart run tool/export_mcp_instructions.dart --scenarios e2e/scenarios --out e2e/mcp-instructions
//   dart run tool/export_mcp_instructions.dart --scenario e2e/scenarios/01_profile_submit_valid.json

import 'dart:convert';
import 'dart:io';

import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

void main(List<String> args) {
  String? single;
  String? dir;
  String outDir = 'e2e/mcp-instructions';
  var preference = McpTransportPreference.marionetteFirst;
  var batchOnly = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--scenario':
        single = args[++i];
      case '--scenarios':
        dir = args[++i];
      case '--out':
        outDir = args[++i];
      case '--web':
        preference = McpTransportPreference.flutterSkillFirst;
      case '--batch-only':
        batchOnly = true;
      case '--help':
      case '-h':
        _usage();
        exit(0);
    }
  }

  final exporter = McpScenarioExporter(preference: preference);
  final scenarios = <E2eScenario>[];

  if (single != null) {
    scenarios.add(E2eScenario.loadFile(File(single)));
  } else if (dir != null) {
    scenarios.addAll(E2eScenario.loadDirectory(Directory(dir)));
  } else {
    stderr.writeln('Provide --scenario or --scenarios');
    _usage();
    exit(64);
  }

  final out = Directory(outDir);
  out.createSync(recursive: true);

  for (final scenario in scenarios) {
    final validation = const ScenarioValidator().validate(scenario);
    if (validation.hasErrors) {
      stderr.writeln('REFUSE ${scenario.name}:');
      for (final issue in validation.errors) {
        stderr.writeln('  $issue');
      }
      exit(1);
    }

    final base = '${scenario.name}.mcp.json';
    final file = File('${out.path}${Platform.pathSeparator}$base');

    if (batchOnly) {
      final attach = McpJsonRpcMessage.toolsCall(
        1,
        'connect_app',
        arguments: {
          'target': McpInstructionScript.attachTargetPlaceholder,
          'kind': preference == McpTransportPreference.marionetteFirst
              ? 'vmService'
              : 'webPage',
        },
      );
      final batch = exporter.exportBatchCall(scenario, id: 2);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'format': 'flutter-e2e-mcp-instructions',
          'formatVersion': 1,
          'mode': 'batch',
          'scenario': scenario.name,
          'attach': attach.toJson(),
          'execute_batch': batch.toJson(),
        }),
      );
    } else {
      file.writeAsStringSync(exporter.exportScript(scenario).encode());
    }
    print('WROTE ${file.path}');
  }
}

void _usage() {
  print('''
Export JSON scenarios as MCP JSON-RPC instruction scripts.

  dart run tool/export_mcp_instructions.dart --scenarios e2e/scenarios --out e2e/mcp-instructions

Options:
  --scenario PATH    One scenario file
  --scenarios DIR    All .json scenarios in a directory
  --out DIR          Output directory (default: e2e/mcp-instructions)
  --web              Prefer skill_* tools (web/CDP) instead of mcp_* (Marionette)
  --batch-only       Emit connect_app + one execute_batch instead of per-step calls
''');
}
