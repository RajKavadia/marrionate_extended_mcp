Third-party notices
===================

This repository vendors two upstream projects under `vendor/`. Each keeps its
original license file, reproduced verbatim in its package directory. The forks
are published to pub.dev under `e2e_*` names with no behavioural changes; see
UPSTREAM.lock for the exact revisions.

--------------------------------------------------------------------------
1. flutter-skill  (vendored as `e2e_flutter_skill`)
--------------------------------------------------------------------------

Upstream:  https://github.com/ai-dashboad/flutter-skill
Revision:  c31a08ead80e0678373e6fb2835b2ffd81ce2716 (v0.9.37)
License:   MIT
Full text: vendor/flutter_skill/LICENSE

Changes made in this fork:

  * `pubspec.yaml` name changed to `e2e_flutter_skill`, version reset to 0.1.0.
  * `package:flutter_skill/` imports rewritten to `package:e2e_flutter_skill/`.
  * `lib/flutter_skill.dart` renamed to `lib/e2e_flutter_skill.dart`.
  * The `flutter_skill` executable renamed to `e2e_flutter_skill` so the fork
    does not claim the upstream global command name.

No source logic was modified.

--------------------------------------------------------------------------
2. marionette_mcp  (vendored as five `e2e_marionette_*` packages)
--------------------------------------------------------------------------

Upstream:  https://github.com/leancodepl/marionette_mcp
Revision:  027440c87460317cf445f33daa2e02f00c524bd4 (v0.6.0)
License:   Apache-2.0
Full text: vendor/marionette_mcp/LICENSE
           vendor/marionette_flutter/LICENSE
           vendor/marionette_cli/LICENSE
           vendor/marionette_logging/LICENSE
           vendor/marionette_logger/LICENSE

Vendored packages:

  upstream                 published as                 license
  ----------------------  ---------------------------  ---------
  marionette_flutter       e2e_marionette_flutter       Apache-2.0
  marionette_mcp           e2e_marionette_mcp           Apache-2.0
  marionette_cli           e2e_marionette_cli           Apache-2.0
  marionette_logging       e2e_marionette_logging       Apache-2.0
  marionette_logger        e2e_marionette_logger        Apache-2.0

Changes made in these forks:

  * `pubspec.yaml` names changed to the `e2e_*` form, versions reset to 0.1.0,
    `resolution: workspace` removed (which `dart pub publish` rejects).
  * Cross-package `package:marionette_*/` imports rewritten repo-wide to their
    `e2e_*` equivalents.
  * Top-level library files renamed to match their package names.
  * Executables renamed (`marionette_mcp` -> `e2e_marionette_mcp`,
    `marionette` -> `e2e_marionette`) so the forks do not claim upstream global
    command names.
  * `vm_service` dependency given an upper bound, as pub.dev requires.
  * CHANGELOG.md entries added; upstream's were symlinks into the parent repo.

No source logic was modified.

--------------------------------------------------------------------------
Apache-2.0 attribution
--------------------------------------------------------------------------

The marionette_mcp project is Copyright the leancodepl contributors. This
distribution includes derivative works that must retain the Apache License 2.0
notice; see each vendored LICENSE file. Notably, section 4(c) requires that
modified files carry prominent notices stating that they were changed — the
modifications here are limited to package identity, imports, and metadata, and
`tool/check_drift.dart` records the exact set of files that differ from the
pinned upstream revisions.
