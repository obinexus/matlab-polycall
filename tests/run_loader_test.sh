#!/bin/sh
# Loader errors through the MEX gateway: a missing libpolycall, an old 1.0
# libpolycall without the binding-ABI-v1 symbols, and a library reporting
# ABI 2 must each give a clear, catchable error in the host -- never a crash.
#
#   sh tests/run_loader_test.sh ENGINE MEXDIR
#     ENGINE  matlab, or octave-cli (GNU Octave: compatibility evidence only)
#     MEXDIR  directory holding the built matlab_polycall_mex (lib/ or build/)
#
# Linux only: the fake libraries (tests/fixtures/fake_polycall.c) are ELF
# shared objects named libpolycall.so.1, selected with LD_LIBRARY_PATH.
# The real core must be found through LD_LIBRARY_PATH as well (control case).
set -u
engine=${1:?usage: run_loader_test.sh ENGINE MEXDIR}
mexdir=${2:?usage: run_loader_test.sh ENGINE MEXDIR}
command -v "$engine" >/dev/null 2>&1 || { echo "SKIP: $engine is not installed"; exit 77; }
[ "$(uname -s)" = Linux ] || { echo "SKIP: the loader test needs Linux (ELF fake libraries)"; exit 77; }
cc=${CC:-cc}
real_libdir=${POLYCALL_LIBDIR:-$(pkg-config --variable=libdir polycall 2>/dev/null)}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/missing" "$tmp/v10" "$tmp/abi2"
$cc -shared -fPIC -Wl,-soname,libpolycall.so.1 -DFAKE_V10 tests/fixtures/fake_polycall.c -o "$tmp/v10/libpolycall.so.1" || exit 2
$cc -shared -fPIC -Wl,-soname,libpolycall.so.1 -DFAKE_ABI=2 tests/fixtures/fake_polycall.c -o "$tmp/abi2/libpolycall.so.1" || exit 2
mexdir=$(cd "$mexdir" && pwd)
probe="addpath('$mexdir'); try, v = matlab_polycall_mex('abi'); fprintf('LOADED abi=%d\n', v); catch err, fprintf('LOADERROR %s | %s\n', err.identifier, err.message); end"

run_probe() {
    case "$engine" in
        *matlab*) LD_LIBRARY_PATH="$1" "$engine" -batch "$probe" ;;
        *)        LD_LIBRARY_PATH="$1" "$engine" --no-gui --norc --quiet --eval "$probe" ;;
    esac
}

fail=0
check() {   # check NAME LIBDIR EXPECTED...
    name=$1; dir=$2; shift 2
    out=$(run_probe "$dir" 2>&1)
    rc=$?
    printf '%s (exit %d): %s\n' "$name" "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
    ok=1
    [ "$rc" -eq 0 ] || ok=0              # the host survived and exited normally
    for want in "$@"; do
        printf '%s' "$out" | grep -F -q -- "$want" || { ok=0; echo "   missing: $want"; }
    done
    if [ "$ok" = 1 ]; then echo "PASS $name"; else echo "FAIL $name"; fail=1; fi
}

[ -n "$real_libdir" ] && check "control: real libpolycall" "$real_libdir" "LOADED abi=1"
check "missing libpolycall" "$tmp/missing" "LOADERROR" "libpolycall.so.1"
check "old 1.0 library (no ABI v1 symbols)" "$tmp/v10" "LOADERROR" "undefined symbol: polycall_"
check "library reporting ABI 2" "$tmp/abi2" "LOADERROR polycall:E_UNSUPPORTED" "binding ABI 2, matlab-polycall needs 1"
exit $fail
