import 'package:marrionate_extended_mcp/src/flutter_e2e_mcp/flutter_e2e_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('parseServeArgs', () {
    test('defaults prefix to namespaced', () {
      final options = parseServeArgs([]);
      expect(options.prefixPolicy, ToolPrefixPolicy.namespaced);
      expect(options.verbose, isFalse);
      expect(options.scenariosPath, isNull);
    });

    test('reads scenarios path and verbose flag', () {
      final options = parseServeArgs([
        '-s',
        '/tmp/scenarios',
        '--verbose',
        '--connect',
        'ws://127.0.0.1:1/t=/ws',
        '--kind',
        'vmService',
      ]);
      expect(options.scenariosPath, '/tmp/scenarios');
      expect(options.verbose, isTrue);
      expect(options.connectTarget, 'ws://127.0.0.1:1/t=/ws');
      expect(options.connectKind, 'vmService');
    });

    test('rejects unknown prefix with FormatException', () {
      expect(
        () => parseServeArgs(['--prefix', 'invalid']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
