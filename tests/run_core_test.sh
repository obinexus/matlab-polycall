#!/bin/sh
# Run a C-layer test binary against the REAL Polycall core:
#   - `polycall start` (RPC runtime)            -> MATLAB_POLYCALL_RUNTIME
#   - `polycall peer serve --print-messages`    -> MATLAB_POLYCALL_PEER
# then check that every payload the test sent to the C node arrived with
# exactly the bytes, sender id and message id it wrote to <scratch>/ml2c-*.bin.
#
#   sh tests/run_core_test.sh COMMAND [ARGS...]
#     e.g.  sh tests/run_core_test.sh build/matlab_polycall_core_test
#           sh tests/run_core_test.sh valgrind --error-exitcode=9 build/matlab_polycall_core_test
# The scratch directory is passed as MATLAB_POLYCALL_SCRATCH. Set
# EXPECT_C_NODE_PAYLOADS=0 for commands that do not send to the C node.
#
# Needs: the polycall CLI ($POLYCALL_CLI or `polycall` on PATH), base64, od.
set -u
[ $# -ge 1 ] || { echo "usage: run_core_test.sh COMMAND [ARGS...]"; exit 2; }
cli=${POLYCALL_CLI:-$(command -v polycall || true)}
[ -n "$cli" ] || { echo "SKIP: no polycall CLI (set POLYCALL_CLI)"; exit 77; }
export POLYCALL_CLI="$cli"

scratch=$(mktemp -d 2>/dev/null || mktemp -d -t mlpolycall)
POLYCALL_DEV_TOKEN="ml-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
export POLYCALL_DEV_TOKEN
pids=''
cleanup() {
    for p in $pids; do kill "$p" 2>/dev/null; done
    sleep 0.3
    rm -rf "$scratch"
}
trap cleanup EXIT

( cd "$scratch" && exec "$cli" start --endpoint 127.0.0.1:0 --endpoint-file "$scratch/rt.ep" ) >"$scratch/rt.log" 2>&1 &
pids="$pids $!"
( cd "$scratch" && exec "$cli" peer serve --node-id c-printer --endpoint 127.0.0.1:0 \
    --endpoint-file "$scratch/peer.ep" --print-messages ) >"$scratch/peer.out" 2>&1 &
pids="$pids $!"
i=0
while [ ! -s "$scratch/rt.ep" ] || [ ! -s "$scratch/peer.ep" ]; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { echo "FAIL: polycall start / peer serve did not come up"; cat "$scratch"/*.log "$scratch/peer.out"; exit 1; }
    sleep 0.1
done
MATLAB_POLYCALL_RUNTIME=$(tr -d '\r\n' < "$scratch/rt.ep")
MATLAB_POLYCALL_PEER=$(tr -d '\r\n' < "$scratch/peer.ep")
MATLAB_POLYCALL_SCRATCH=$scratch
# native Windows programs (MSYS2 / Git Bash) need a Windows path
command -v cygpath >/dev/null 2>&1 && MATLAB_POLYCALL_SCRATCH=$(cygpath -m "$scratch")
export MATLAB_POLYCALL_RUNTIME MATLAB_POLYCALL_PEER MATLAB_POLYCALL_SCRATCH
echo "runtime $MATLAB_POLYCALL_RUNTIME, C peer node $MATLAB_POLYCALL_PEER, CLI $cli"

"$@"
rc=$?

# what the C node printed for each ml2c-* payload must match the file
sleep 0.5
bad=0
checked=0
for f in "$scratch"/ml2c-*.bin; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .bin)
    expect=$(base64 < "$f" | tr -d '\r\n')
    line=$(grep "\"id\":\"$id\"" "$scratch/peer.out" | head -n 1)
    got=$(printf '%s' "$line" | sed -n 's/.*"payload_b64":"\([^"]*\)".*/\1/p')
    from=$(printf '%s' "$line" | sed -n 's/.*"from":"\([^"]*\)".*/\1/p')
    count=$(grep -c "\"id\":\"$id\"" "$scratch/peer.out")
    checked=$((checked + 1))
    if [ "$got" = "$expect" ] && [ "$from" = "matlab-a" ] && [ "$count" = 1 ]; then
        echo "PASS polycall peer serve received $id: exact bytes, sender matlab-a, once"
    else
        echo "FAIL polycall peer serve received $id (from='$from', count=$count)"
        bad=1
    fi
done
if [ "${EXPECT_C_NODE_PAYLOADS:-1}" = 1 ] && [ "$checked" -eq 0 ]; then
    echo "FAIL no payloads were sent to the C node"
    bad=1
fi
[ "$rc" -eq 0 ] && [ "$bad" -eq 0 ]
