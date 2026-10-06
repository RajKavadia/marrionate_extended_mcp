import 'package:marrionate_extended_mcp/src/marionette_flutter/e2e_marionette_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marrionate_extended_mcp/src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'E2eBinding installs Marionette before flutter-skill on native VM',
    () {
      // Must run before TestWidgetsFlutterBinding: MarionetteBinding owns
      // WidgetsBinding.instance and throws if another binding exists first.
      final binding = E2eBinding.ensureInitialized(
        const E2eConfig(verbose: false, autoEnableIndicators: false),
      );

      expect(binding.platform, E2ePlatform.nativeVmService);
      expect(binding.marionetteAvailable, isTrue);
      expect(binding.marionetteFullySupported, isTrue);
      expect(binding.capability.marionetteTools, isNotEmpty);
      expect(binding.flutterSkillAvailable, isTrue);

      expect(WidgetsBinding.instance, isA<MarionetteBinding>());
      expect(E2eBinding.isInitialized, isTrue);
      expect(E2eBinding.instance, same(binding));

      // Idempotent second call returns the same binding.
      expect(E2eBinding.ensureInitialized(), same(binding));
    },
    skip: kIsWeb ? 'Web binding path is exercised in E2eCapability tests.' : false,
  );

  test(
    'chained FlutterError.onError forwards without swallowing',
    () {
      E2eBinding.ensureInitialized(const E2eConfig(verbose: false));
      var forwarded = false;
      final prior = FlutterError.onError;
      FlutterError.onError = (details) {
        forwarded = true;
        prior?.call(details);
      };
      addTearDown(() => FlutterError.onError = prior);

      FlutterError.reportError(
        FlutterErrorDetails(exception: Exception('e2e binding chain probe')),
      );
      expect(forwarded, isTrue);
    },
    skip: kIsWeb ? 'Native-only binding install.' : false,
  );
}
