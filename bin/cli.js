#!/usr/bin/env node
// npm wrapper for the flutter-e2e-mcp server.
//
// Deliberately different from the vendored flutter-skill wrapper, which
// downloads a prebuilt binary from GitHub releases on first run. That approach
// needs network access at install time, leaves a machine-wide cache in
// ~/.flutter-skill, and can serve a binary that does not match the Dart source
// shipped alongside it. This wrapper instead runs the Dart source that ships in
// the package, so what executes is exactly what was published.
//
// Requires the Dart SDK on PATH.

'use strict';

const { spawn } = require('child_process');
const path = require('path');

const serverEntry = path.join(__dirname, '..', 'bin', 'server.dart');
const args = process.argv.slice(2);

function fail(message, code) {
  process.stderr.write(`flutter-e2e-mcp: ${message}\n`);
  process.exit(code);
}

const child = spawn('dart', ['run', serverEntry, ...args], {
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

child.on('error', (err) => {
  if (err.code === 'ENOENT') {
    fail(
      'the Dart SDK was not found on PATH.\n' +
        '  flutter-e2e-mcp runs the server from Dart source, so `dart` must be ' +
        'available.\n' +
        '  Install Flutter (which bundles Dart) from https://docs.flutter.dev/get-started/install',
      127,
    );
  }
  fail(`failed to start the Dart server: ${err.message}`, 1);
});

child.on('close', (code, signal) => {
  if (signal) {
    process.stderr.write(`flutter-e2e-mcp: terminated by signal ${signal}\n`);
    process.exit(1);
  }
  process.exit(code === null ? 1 : code);
});

// Forward termination so Ctrl-C and container stops shut the child down too.
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    if (!child.killed) child.kill(signal);
  });
}
