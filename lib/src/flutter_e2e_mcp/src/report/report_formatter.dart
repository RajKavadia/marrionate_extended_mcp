import 'dart:convert';

import '../replay/batch_executor.dart';
import '../replay/scenario_replayer.dart';

/// Output formats for replay results.
enum ReportFormat {
  /// Human-readable summary.
  text,

  /// Machine-readable JSON.
  json,

  /// JUnit XML for CI test reporters.
  junit,
}

/// Renders replay results in the supported formats.
class ReportFormatter {
  const ReportFormatter._();

  /// Renders a [BatchResult] as text.
  static String batchToText(BatchResult result) {
    final b = StringBuffer();
    for (final report in result.stepReports) {
      b.writeln(report.summary);
    }
    if (result.validationError) {
      b.writeln('\nvalidation failed:');
      for (final issue in result.validation!.issues) {
        b.writeln('  $issue');
      }
    }
    b.writeln('\n${result.success ? "PASS" : "FAIL"}: '
        '${result.passedCount} passed, ${result.failedCount} failed');
    if (!result.success && result.failedStep >= 0) {
      b.writeln('first failure at step ${result.failedStep}');
    }
    return b.toString();
  }

  /// Renders a [ReplayReport] as text.
  static String toText(ReplayReport report) {
    final b = StringBuffer()
      ..writeln('flutter-e2e replay')
      ..writeln('=' * 40);

    for (final outcome in report.scenarios) {
      final status = outcome.passed ? 'PASS' : 'FAIL';
      b.writeln('$status  ${outcome.name}');
      if (!outcome.passed) {
        if (outcome.error != null) {
          b.writeln('      error: ${outcome.error}');
        }
        final failure = outcome.result?.firstFailure;
        if (failure != null) {
          b.writeln('      step ${failure.step} (${failure.action}): '
              '${failure.error}');
          if (failure.expected != null || failure.actual != null) {
            b.writeln('      expected: ${failure.expected}');
            b.writeln('      actual:   ${failure.actual}');
          }
        }
      }
    }

    b
      ..writeln('=' * 40)
      ..writeln('${report.passed}/${report.scenarios.length} scenarios passed, '
          '${report.totalSteps} steps executed');
    return b.toString();
  }

  /// Renders a [ReplayReport] as pretty JSON.
  static String toJson(ReplayReport report) =>
      const JsonEncoder.withIndent('  ').convert(report.toJson());

  /// Renders a [ReplayReport] as JUnit XML.
  ///
  /// Each scenario becomes a single test case whose failure carries the failing
  /// step number, so a CI reporter links back to the exact step.
  static String toJunit(ReplayReport report, {String suiteName = 'flutter-e2e'}) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<testsuites name="$suiteName" '
          'tests="${report.scenarios.length}" '
          'failures="${report.failed}" '
          'errors="0">')
      ..writeln('  <testsuite name="$suiteName" '
          'tests="${report.scenarios.length}" '
          'failures="${report.failed}" errors="0">');

    for (final outcome in report.scenarios) {
      final failure = outcome.result?.firstFailure;
      final expected = failure?.expected;
      final actual = failure?.actual;
      final failureXml = outcome.passed
          ? ''
          : '      <failure message="${_escapeXml(outcome.error ?? failure?.error ?? 'scenario failed')}">'
              '${_escapeXml(outcome.name)}'
              '${failure == null ? '' : '\n  step ${failure.step}: ${failure.action}'}'
              '${expected == null ? '' : '\n  expected: $expected'}'
              '${actual == null ? '' : '\n  actual: $actual'}'
              '</failure>\n';

      b
        ..writeln('    <testcase name="${_escapeXml(outcome.name)}" '
            'classname="$suiteName">')
        ..write(failureXml)
        ..writeln('    </testcase>');
    }

    b
      ..writeln('  </testsuite>')
      ..writeln('</testsuites>');
    return b.toString();
  }

  /// Renders [report] in the requested [format].
  static String render(ReplayReport report, ReportFormat format) {
    switch (format) {
      case ReportFormat.text:
        return toText(report);
      case ReportFormat.json:
        return toJson(report);
      case ReportFormat.junit:
        return toJunit(report);
    }
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
