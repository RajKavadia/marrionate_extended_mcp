#!/usr/bin/env node
// Resolves Dart sources on postinstall.
//
// The Dart server runs from source via `dart run`, which needs a populated
// .dart_tool/package_config.json. Running `dart pub get` here means the first
// MCP handshake works immediately after `npm install`, instead of failing on the
// first request with an opaque "Target of URI doesn't exist".
//
// Failure here is non-fatal: the package is still installed and a later
// `dart pub get` (documented in the README) will fix it. A hard postinstall
// failure would break `npm install` for users who only want the files.

'use strict';

const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');
const quiet = process.env.FLUTTER_E2E_MCP_SKIP_PUB_GET === '1';

if (quiet) {
  process.stdout.write(
    'flutter-e2e-mcp: skipping pub get (FLUTTER_E2E_MCP_SKIP_PUB_GET=1)\n',
  );
  process.exit(0);
}

const result = spawnSync('dart', ['pub', 'get'], {
  cwd: root,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

if (result.error) {
  process.stderr.write(
    'flutter-e2e-mcp: could not run `dart pub get` during postinstall.\n' +
      '  The package is installed, but run `dart pub get` in the package ' +
      'directory before starting the server.\n',
  );
} else if (result.status !== 0) {
  process.stderr.write(
    'flutter-e2e-mcp: `dart pub get` failed during postinstall.\n' +
      '  The package is installed, but run `dart pub get` in the package ' +
      'directory before starting the server.\n',
  );
}
