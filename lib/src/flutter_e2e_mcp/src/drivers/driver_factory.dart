import 'flutter_skill_driver.dart';
import 'live_driver.dart';
import 'marionette_driver.dart';

/// How a target is reached.
enum DriverKind {
  /// Dart VM service. Native and debug-web Flutter apps.
  vmService,

  /// A page served over http, driven through Chrome.
  webPage,

  /// An already-running Chrome with remote debugging enabled.
  cdp,
}

/// Builds the right [LiveDriver] for a target.
///
/// The interesting decision is [inferKind]. A VM service URI and a web page URL
/// are both `http://127.0.0.1:PORT/...`, so they are told apart by Flutter's
/// auth token, which appears as a path segment (`/EBNjNSPV0F8=/`) or a fragment
/// in newer SDKs. Guessing wrong here is expensive: a VM service URI handed to
/// the CDP driver fails with a confusing Chrome error, and vice versa.
class DriverFactory {
  const DriverFactory();

  /// Classifies [target] without connecting to it.
  DriverKind inferKind(String target) {
    final trimmed = target.trim();

    if (trimmed.startsWith('cdp://')) return DriverKind.cdp;
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      return DriverKind.vmService;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return DriverKind.webPage;

    // A bare origin such as http://localhost:8791 or http://localhost:8791/ is a
    // served page. Flutter's VM service always carries a token, which shows up
    // as "=" in the path (older SDKs) or "#" in the fragment (3.41+).
    final hasToken = uri.path.contains('=') ||
        uri.path.contains('#') ||
        (uri.fragment.contains('=') || uri.fragment.contains('#'));
    final isBareOrigin = uri.path.isEmpty || uri.path == '/';

    if (hasToken) return DriverKind.vmService;
    if (isBareOrigin) return DriverKind.webPage;
    return DriverKind.webPage;
  }

  /// Whether [target] looks like a Dart VM service URI.
  bool isVmServiceTarget(String target) =>
      inferKind(target) == DriverKind.vmService;

  /// Rewrites a VM service URI into the form `vmServiceConnectUri` expects.
  ///
  /// `flutter run` prints an `http://` URL, but the connector wants `ws://`,
  /// and the trailing `/ws` is optional in what the tool prints but not in what
  /// the socket needs.
  String normalizeVmServiceUri(String uri) {
    var out = uri.trim();
    if (out.startsWith('http://')) {
      out = 'ws://${out.substring('http://'.length)}';
    } else if (out.startsWith('https://')) {
      out = 'wss://${out.substring('https://'.length)}';
    }
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    if (!out.endsWith('/ws')) out = '$out/ws';
    return out;
  }

  /// Creates a driver for [target] without connecting it.
  ///
  /// Throws [DriverException] when the requested combination is impossible, so
  /// the caller gets one clear message instead of a transport-level failure.
  LiveDriver create(
    String target, {
    DriverKind? kind,
    int cdpPort = 9222,
    bool launchChrome = true,
    bool headless = false,
    String? chromePath,
    String? url,
  }) {
    final resolved = kind ?? inferKind(target);
    switch (resolved) {
      case DriverKind.vmService:
        return MarionetteDriver();
      case DriverKind.webPage:
        return FlutterSkillDriver.web(
          url: url ?? target,
          cdpPort: cdpPort,
          launchChrome: launchChrome,
          headless: headless,
          chromePath: chromePath,
        );
      case DriverKind.cdp:
        final port = Uri.parse(target.replaceFirst('cdp://', 'http://')).port;
        if (url == null || url.isEmpty) {
          throw DriverException(
            'A cdp:// target addresses Chrome, not a page, so a page "url" is '
            'also required.',
            hint: 'connect_app {"target":"cdp://127.0.0.1:9222",'
                '"url":"http://localhost:8791/"}',
          );
        }
        return FlutterSkillDriver.web(
          url: url,
          cdpPort: port == 0 ? cdpPort : port,
          launchChrome: false,
          headless: headless,
          chromePath: chromePath,
        );
    }
  }

  /// Creates and connects a driver in one step.
  Future<LiveSession> connect(
    String target, {
    DriverKind? kind,
    int cdpPort = 9222,
    bool launchChrome = true,
    bool headless = false,
    String? chromePath,
    String? url,
  }) async {
    final resolved = kind ?? inferKind(target);
    final driver = create(
      target,
      kind: resolved,
      cdpPort: cdpPort,
      launchChrome: launchChrome,
      headless: headless,
      chromePath: chromePath,
      url: url,
    );
    final effectiveTarget =
        resolved == DriverKind.vmService ? normalizeVmServiceUri(target) : target;
    final info = await driver.connect(effectiveTarget);
    return LiveSession(
      driver: driver,
      kind: resolved,
      target: effectiveTarget,
      connectInfo: info,
    );
  }
}

/// An attached driver plus what the server needs to know about it.
class LiveSession {
  LiveSession({
    required this.driver,
    required this.kind,
    required this.target,
    Map<String, Object?>? connectInfo,
  }) : connectInfo = connectInfo ?? const {};

  final LiveDriver driver;
  final DriverKind kind;
  final String target;

  /// Whatever the driver's `connect` reported, surfaced back to the caller.
  final Map<String, Object?> connectInfo;

  /// Whether this session can serve marionette's VM-service tools.
  ///
  /// True for [DriverKind.vmService], which covers native *and* Flutter web in
  /// debug builds. False for the CDP transports, which never touch the Dart VM
  /// service.
  bool get supportsMarionette => kind == DriverKind.vmService;

  /// Whether the app under test is a web app.
  ///
  /// Only meaningful for CDP sessions. A VM service URI does not reveal whether
  /// the app is web or native, which is exactly why marionette availability is
  /// derived from [kind] rather than from a platform guess.
  bool get isWeb => kind != DriverKind.vmService;

  Map<String, Object?> toJson() => {
        'target': target,
        'kind': kind.name,
        'driver': driver.kind,
        'connected': driver.isConnected,
        'supportsMarionette': supportsMarionette,
        'isWeb': isWeb,
        'tools': driver.supportedTools.length,
        ...connectInfo,
      };
}
