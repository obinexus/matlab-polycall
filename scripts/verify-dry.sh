#!/usr/bin/env sh
# Boundary check: the C layer / MEX gateway forward to the real ABI
# (<polycall.h>) and implement no configuration parsing or networking.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/matlab_polycall.c" \
    "$root/src/matlab_polycall_mex.c" \
    "$root/src/+obinexus/+polycall/runConfig.m" \
    "$root/src/+obinexus/+polycall/runConfigOrError.m"; then
    echo "matlab-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q '#include <polycall.h>' "$root/include/matlab_polycall.h"
grep -F -q 'polycall_ffi_run_config(config_path, 1)' "$root/src/matlab_polycall.c"
grep -F -q 'polycall_ffi_abi_version()' "$root/src/matlab_polycall.c"
grep -F -q 'mxArrayToUTF8String' "$root/src/matlab_polycall_mex.c"
grep -F -q 'mxINT32_CLASS' "$root/src/matlab_polycall_mex.c"
if [ -e "$root/generated/polycall/polycall_ffi.h" ]; then
    echo "stub header generated/polycall/polycall_ffi.h must not exist (use <polycall.h>)" >&2
    exit 1
fi

echo "matlab-polycall thin-adapter check: PASS"
