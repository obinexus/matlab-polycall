'use strict';

// Runs the thin-adapter audit with the platform's own shell, so `npm test`
// (and `npm pack`, whose prepack runs it) also works on Windows without a
// POSIX sh: scripts/verify-dry.ps1 on Windows, scripts/verify-dry.sh elsewhere.
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const result = process.platform === 'win32'
  ? spawnSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    path.join(__dirname, 'verify-dry.ps1')], { stdio: 'inherit' })
  : spawnSync('sh', [path.join(__dirname, 'verify-dry.sh')], { stdio: 'inherit' });

if (result.error) {
  console.error(`verify-dry: ${result.error.message}`);
  process.exit(2);
}
process.exit(result.status === null ? 1 : result.status);
