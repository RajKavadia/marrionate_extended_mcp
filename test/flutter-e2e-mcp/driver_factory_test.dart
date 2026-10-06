import 'package:marrionate_extended_mcp/src/flutter_e2e_mcp/flutter_e2e_mcp.dart';
import 'package:test/test.dart';

void main() {
  const factory = DriverFactory();

  group('DriverFactory.inferKind', () {
    test('classifies ws and wss as vmService', () {
      expect(
        factory.inferKind('ws://127.0.0.1:9100/ws'),
        DriverKind.vmService,
      );
      expect(
        factory.inferKind('wss://127.0.0.1:9100/abc=/ws'),
        DriverKind.vmService,
      );
    });

    test('classifies Flutter VM http URLs with auth token as vmService', () {
      expect(
        factory.inferKind('http://127.0.0.1:9100/EBNjNSPV0F8=/'),
        DriverKind.vmService,
      );
      expect(
        factory.inferKind('http://127.0.0.1:9100/#/EBNjNSPV0F8='),
        DriverKind.vmService,
      );
    });

    test('classifies bare page origins as webPage', () {
      expect(
        factory.inferKind('http://localhost:8791'),
        DriverKind.webPage,
      );
      expect(
        factory.inferKind('http://localhost:8791/'),
        DriverKind.webPage,
      );
    });

    test('classifies cdp scheme as cdp', () {
      expect(
        factory.inferKind('cdp://127.0.0.1:9222'),
        DriverKind.cdp,
      );
    });
  });

  group('DriverFactory.normalizeVmServiceUri', () {
    test('rewrites http to ws and appends /ws', () {
      expect(
        factory.normalizeVmServiceUri('http://127.0.0.1:9100/TOKEN=/'),
        'ws://127.0.0.1:9100/TOKEN=/ws',
      );
    });

    test('leaves an existing ws suffix unchanged', () {
      expect(
        factory.normalizeVmServiceUri('ws://127.0.0.1:9100/TOKEN=/ws'),
        'ws://127.0.0.1:9100/TOKEN=/ws',
      );
    });
  });

  group('DriverFactory.create', () {
    test('returns MarionetteDriver for vmService', () {
      final driver = factory.create('ws://127.0.0.1:1/ws');
      expect(driver, isA<MarionetteDriver>());
      expect(driver.kind, 'marionette');
    });

    test('returns FlutterSkillDriver for webPage', () {
      final driver = factory.create('http://localhost:8791/');
      expect(driver, isA<FlutterSkillDriver>());
    });

    test('cdp without url throws DriverException with hint', () {
      expect(
        () => factory.create('cdp://127.0.0.1:9222'),
        throwsA(
          isA<DriverException>().having(
            (e) => e.hint,
            'hint',
            contains('url'),
          ),
        ),
      );
    });
  });

  group('LiveSession', () {
    test('supportsMarionette follows driver kind', () {
      final marionette = LiveSession(
        driver: MarionetteDriver(),
        kind: DriverKind.vmService,
        target: 'ws://127.0.0.1:1/ws',
      );
      expect(marionette.supportsMarionette, isTrue);
      expect(marionette.isWeb, isFalse);

      final web = LiveSession(
        driver: FlutterSkillDriver.web(url: 'http://localhost:1/'),
        kind: DriverKind.webPage,
        target: 'http://localhost:1/',
      );
      expect(web.supportsMarionette, isFalse);
      expect(web.isWeb, isTrue);
    });
  });
}
