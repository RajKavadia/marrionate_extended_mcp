#!/usr/bin/env bash
# Replays every JSON scenario against a running app.
#
# The app must already be running with a reachable VM service or CDP bridge:
#   flutter run -d windows      (native: marionette + flutter-skill)
#   flutter run -d chrome       (web: flutter-skill JS bridge only)
#
# On native, marionette tools are available; on web they are refused with an
# explanatory error rather than hanging, because no VM service exists there.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
scenarios="${SCENARIOS_DIR:-$here/scenarios}"
format="${1:-text}"

echo "Validating scenarios..."
dart run "$repo/tool/validate_scenarios.dart" "$scenarios"

echo
echo "Replaying scenarios (format: $format)..."
dart run "$repo/packages/flutter-e2e-mcp/bin/replay.dart" \
  --scenarios "$scenarios" \
  --format "$format"
