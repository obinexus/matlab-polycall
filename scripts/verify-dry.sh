#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/matlab_polycall.c" \
    "$root/src/matlab_polycall_mex.c" \
    "$root/src/+obinexus/+polycall/runConfig.m" \
    "$root/src/+obinexus/+polycall/runConfigOrError.m"; then
    echo "matlab-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/matlab_polycall.c"
grep -F -q 'mxArrayToUTF8String' "$root/src/matlab_polycall_mex.c"
grep -F -q 'mxFree(config_path)' "$root/src/matlab_polycall_mex.c"
grep -F -q 'mxINT32_CLASS' "$root/src/matlab_polycall_mex.c"

echo "matlab-polycall thin-adapter check: PASS"
