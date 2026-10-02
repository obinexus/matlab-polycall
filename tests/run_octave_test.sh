#!/bin/sh
# GNU Octave COMPATIBILITY run of the MATLAB API (the MEX gateway built with
# `mkoctfile --mex`) against the real libpolycall. This is evidence that the
# gateway and the +obinexus/+polycall package work in Octave -- it is NOT a
# MATLAB test.
set -eu
cd "$(dirname "$0")/.."
octave=${OCTAVE:-octave-cli}
command -v "$octave" >/dev/null 2>&1 || { echo "SKIP: $octave is not installed"; exit 77; }
"$octave" --version | head -n 1
exec sh tests/run_core_test.sh "$octave" --no-gui --norc --eval \
    "addpath('src'); addpath('build'); run('tests/test_matlab_polycall.m');"
