'use strict';

const path = require('node:path');

const fromPackageRoot = (...parts) => path.join(__dirname, ...parts);

module.exports = Object.freeze({
  packageName: 'matlab-polycall',
  matlabPackage: fromPackageRoot('src', '+obinexus', '+polycall'),
  runConfig: fromPackageRoot('src', '+obinexus', '+polycall', 'runConfig.m'),
  runConfigOrError: fromPackageRoot('src', '+obinexus', '+polycall', 'runConfigOrError.m'),
  call: fromPackageRoot('src', '+obinexus', '+polycall', 'call.m'),
  peer: fromPackageRoot('src', '+obinexus', '+polycall', 'Peer.m'),
  mexSource: fromPackageRoot('src', 'matlab_polycall_mex.c'),
  nativeSource: fromPackageRoot('src', 'matlab_polycall.c'),
  nativeHeader: fromPackageRoot('include', 'matlab_polycall.h'),
  buildScript: fromPackageRoot('build_matlab_polycall.m'),
  config: fromPackageRoot('matlab-polycallrc'),
  manifest: fromPackageRoot('polycall-binding.json'),
  makefile: fromPackageRoot('Makefile')
});
