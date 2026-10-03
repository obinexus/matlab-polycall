'use strict';

// npm metadata and packaged files (no MATLAB, no core).

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const binding = require('..');
const metadata = require('../package.json');
const manifest = require('../polycall-binding.json');

test('npm metadata', () => {
  assert.equal(metadata.name, 'matlab-polycall');
  assert.equal(metadata.license, 'MIT');
  assert.equal(metadata.publishConfig.access, 'public');
  assert.equal(metadata.author, 'Nnamdi Michael Okpala <okpalan@protonmail.com>');
  assert.equal(metadata.repository.url, 'git+https://github.com/obinexus/matlab-polycall.git');
  assert.equal(manifest.version, metadata.version);
  assert.equal(manifest.core, 'polycall >= 1.1.0 (binding ABI 1)');
  assert.equal(manifest.core_repository, 'https://github.com/obinexus/polycall');
  assert.doesNotMatch(JSON.stringify(metadata) + JSON.stringify(manifest), /libpolycall 1\.5|\.\.\/\.\.\/src/);
});

test('every exported path exists', () => {
  for (const [name, file] of Object.entries(binding)) {
    if (name === 'packageName') continue;
    assert.equal(fs.existsSync(file), true, `missing ${name}: ${file}`);
  }
  assert.equal(fs.existsSync(path.join(__dirname, '..', 'generated')), false, 'the stub FFI header is gone');
});

test('rc files cite the real grammar', () => {
  for (const rc of ['matlab-polycallrc', path.join('examples', 'matlab-polycallrc')]) {
    const text = fs.readFileSync(path.join(__dirname, '..', rc), 'utf8');
    assert.match(text, /polycall config validate/);
    assert.doesNotMatch(text, /polycall_config_schema\.c/);
  }
});
