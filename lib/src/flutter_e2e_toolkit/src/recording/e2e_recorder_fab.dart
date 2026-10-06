import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mcp/mcp_scenario_export.dart';
import 'e2e_recorder_scope.dart';
import 'interaction_recorder.dart';

/// Floating control to start/stop recording and export Marionette MCP JSON.
class E2eRecorderFab extends StatelessWidget {
  const E2eRecorderFab({super.key});

  static const String fabKey = 'e2e_recorder_fab';

  @override
  Widget build(BuildContext context) {
    final recorder = E2eRecorderScope.of(context);
    final recording = recorder.isRecording;
    final count = recorder.steps.length;

    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final theme = Theme.of(context);

    return Directionality(
      textDirection: direction,
      child: Theme(
        data: theme,
        child: Material(
          type: MaterialType.transparency,
          child: FloatingActionButton.extended(
            key: const ValueKey<String>(fabKey),
            heroTag: 'e2e_recorder_fab',
            backgroundColor: recording ? Colors.red.shade700 : null,
            onPressed: () => _onPressed(context, recorder),
            icon: Icon(recording ? Icons.stop_rounded : Icons.fiber_manual_record),
            label: Text(recording ? 'Stop ($count)' : 'Record E2E'),
          ),
        ),
      ),
    );
  }

  Future<void> _onPressed(BuildContext context, InteractionRecorder recorder) async {
    if (recorder.isRecording) {
      E2eRecorderScope.flushPendingInput(context);
      recorder.stop();
      if (!context.mounted) return;
      // The live session is the place to replay. A modal export sheet covers
      // the home screen, so the next run cannot find those widgets.
      if (E2eRecorderScope.liveSessionUriOf(context) != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Recording saved. Run it from the live session.'),
          ),
        );
        return;
      }
      await _showExportSheet(context, recorder);
      return;
    }
    recorder.start();
    if (context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final watch = E2eRecorderScope.liveSessionUriOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            watch == null
                ? 'Recording — tap widgets with ValueKeys. Text fields flush on blur.'
                : 'Recording — watch the live session at $watch',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showExportSheet(
    BuildContext context,
    InteractionRecorder recorder,
  ) async {
    if (recorder.steps.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No steps recorded.')),
      );
      return;
    }

    final scenario = recorder.toScenario();
    const exporter = McpScenarioExporter();
    final mcpScript = exporter.exportScript(scenario);
    final batchAttach = mcpScript.attach.encode();
    final mcpBody = mcpScript.encode();

    if (!context.mounted) return;

    final targetContext = _findModalContext(context);
    if (targetContext == null) {
      // Fallback: Copy directly to clipboard if no navigator is in tree.
      Clipboard.setData(ClipboardData(text: mcpBody));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No Navigator found — copied MCP script to clipboard.'),
        ),
      );
      return;
    }

    try {
      await showModalBottomSheet<void>(
        context: targetContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return DefaultTabController(
            length: 3,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
                left: 16,
                right: 16,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${recorder.steps.length} steps → Marionette MCP',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const TabBar(
                    tabs: [
                      Tab(text: 'MCP script'),
                      Tab(text: 'Scenario'),
                      Tab(text: 'Attach only'),
                    ],
                  ),
                  SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * 0.45,
                    child: TabBarView(
                      children: [
                        _JsonPane(text: mcpBody),
                        _JsonPane(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(scenario.toJson()),
                        ),
                        _JsonPane(text: batchAttach),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mcpBody));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                        const SnackBar(
                          content: Text('MCP instruction JSON copied.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy MCP script'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (_) {
      // Fallback: Copy to clipboard and inform user
      Clipboard.setData(ClipboardData(text: mcpBody));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Copied MCP instructions to clipboard.'),
        ),
      );
    }
  }

  static BuildContext? _findModalContext(BuildContext context) {
    if (Navigator.maybeOf(context) != null) return context;

    BuildContext? found;
    void search(Element element) {
      if (found != null) return;
      // Must be a child of Navigator to have Navigator in its ancestry
      if (element.widget is Navigator) {
        element.visitChildren((navChild) {
          if (found == null && navChild.mounted) {
            found = navChild;
          }
        });
        return;
      }
      element.visitChildren(search);
    }

    if (context is Element) {
      context.visitChildren(search);
    }
    return found;
  }
}

class _JsonPane extends StatelessWidget {
  const _JsonPane({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
      ),
    );
  }
}
