/*
 * matlab_polycall_mex -- MEX gateway over the Polycall binding ABI v1.
 *
 *   out = matlab_polycall_mex(command, args...)
 *
 * Only mxArray conversion happens here; the C layer (matlab_polycall.c)
 * does the work. Failures raise an MException with identifier
 * "polycall:E_<NAME>" and a message carrying the status code, its
 * polycall_strerror() text and the polycall_last_error() detail -- except
 * 'run_config', which returns the int32 status (the documented
 * obinexus.polycall.runConfig contract).
 *
 * Commands:
 *   abi -> double            version -> char           strerror(code) -> char
 *   run_config(path[, strict=1]) -> int32 status       describe(path) -> char JSON
 *   call(endpoint, service, operation, input_json, timeout_ms) -> char JSON
 *   peer_open(node_id, bind_or_empty, token_or_empty) -> int32 handle
 *   peer_close(h)  peer_cancel(h)  peer_register(h, id, endpoint)  peer_unregister(h, id)
 *   peer_endpoint(h) peer_node_id(h) peer_list(h) peer_health(h) -> char
 *   peer_ping(h, peer, timeout_ms)
 *   peer_send(h, peer, payload(uint8|char), message_id_or_empty, timeout_ms)
 *   [sender, id, payload(uint8)] = peer_recv(h, timeout_ms)   (Inf = wait)
 *
 * Builds with MATLAB `mex -R2018a` and with GNU Octave `mkoctfile --mex`.
 */
#include "mex.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "matlab_polycall.h"

static char *arg_string(const mxArray *a, const char *what)
{
    char *s;
    if (!mxIsChar(a)) {
        mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "%s must be a character vector", what);
    }
    s = mxArrayToUTF8String(a);
    if (!s) mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "%s could not be converted to UTF-8", what);
    return s;
}

/* "" -> NULL (send-only node, no token, generated message id) */
static char *arg_optional_string(const mxArray *a, const char *what)
{
    char *s = arg_string(a, what);
    if (s[0] == '\0') {
        mxFree(s);
        return NULL;
    }
    return s;
}

static double arg_scalar(const mxArray *a, const char *what)
{
    if (!mxIsNumeric(a) || mxGetNumberOfElements(a) != 1 || mxIsComplex(a)) {
        mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "%s must be a real numeric scalar", what);
    }
    return mxGetScalar(a);
}

static uint32_t arg_timeout(const mxArray *a, const char *what)
{
    double v = arg_scalar(a, what);
    if (mxIsInf(v) && v > 0) return UINT32_MAX;
    if (!(v >= 0) || v > 4294967294.0 || v != floor(v)) {
        mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "%s must be a non-negative integer number of ms or Inf", what);
    }
    return (uint32_t)v;
}

static polycall_peer_t arg_handle(const mxArray *a)
{
    double v = arg_scalar(a, "handle");
    if (v != floor(v) || v < -2147483648.0 || v > 2147483647.0) {
        mexErrMsgIdAndTxt("polycall:E_INVALID_HANDLE", "handle must be an int32 peer handle");
    }
    return (polycall_peer_t)v;
}

static void raise_status(int32_t status)
{
    char id[96], msg[1400];
    matlab_polycall_error(status, id, sizeof id, msg, sizeof msg);
    mexErrMsgIdAndTxt(id, "%s", msg);
}

static void check(int32_t status)
{
    if (status != POLYCALL_OK) raise_status(status);
}

static mxArray *int32_scalar(int32_t v)
{
    mxArray *m = mxCreateNumericMatrix(1, 1, mxINT32_CLASS, mxREAL);
    *(int32_t *)mxGetData(m) = v;
    return m;
}

static mxArray *bytes_array(const unsigned char *p, size_t n)
{
    mxArray *m = mxCreateNumericMatrix(1, (mwSize)n, mxUINT8_CLASS, mxREAL);
    if (n) memcpy(mxGetData(m), p, n);
    return m;
}

static void need_args(int nrhs, int n, const char *cmd)
{
    if (nrhs != n) {
        mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "'%s' takes %d argument(s)", cmd, n - 1);
    }
}

/* mxMalloc/mxFree take mwSize, which is not size_t everywhere (Octave) */
static void *mx_alloc(size_t n) { return mxMalloc((mwSize)n); }
static void mx_free(void *p) { mxFree(p); }

static int abi_checked = 0;

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    char *cmd;
    (void)nlhs;
    if (nrhs < 1) mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "usage: matlab_polycall_mex(command, args...)");
    if (!abi_checked) {
        char msg[200];
        if (matlab_polycall_check_abi(msg, sizeof msg) != POLYCALL_OK) {
            mexErrMsgIdAndTxt("polycall:E_UNSUPPORTED", "%s", msg);
        }
        matlab_polycall_set_allocator(mx_alloc, mx_free);
        abi_checked = 1;
    }
    cmd = arg_string(prhs[0], "command");

    if (!strcmp(cmd, "abi")) {
        plhs[0] = mxCreateDoubleScalar((double)polycall_ffi_abi_version());
    } else if (!strcmp(cmd, "version")) {
        char v[64];
        int32_t rc = matlab_polycall_version(v, sizeof v);
        if (rc < 0) raise_status(rc);
        plhs[0] = mxCreateString(v);
    } else if (!strcmp(cmd, "strerror")) {
        need_args(nrhs, 2, cmd);
        plhs[0] = mxCreateString(polycall_strerror((int)arg_scalar(prhs[1], "code")));
    } else if (!strcmp(cmd, "run_config")) {
        char *path;
        int strict = 1;
        if (nrhs != 2 && nrhs != 3) mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "run_config(path[, strict])");
        path = arg_string(prhs[1], "configPath");
        if (nrhs == 3) strict = arg_scalar(prhs[2], "strict") != 0;
        plhs[0] = int32_scalar(matlab_polycall_validate_config(path, strict));
        mxFree(path);
    } else if (!strcmp(cmd, "describe")) {
        char *path, *json = NULL;
        int32_t rc;
        need_args(nrhs, 2, cmd);
        path = arg_string(prhs[1], "configPath");
        rc = matlab_polycall_describe(path, &json);
        mxFree(path);
        if (rc != POLYCALL_OK) raise_status(rc);
        plhs[0] = mxCreateString(json);
        matlab_polycall_free(json);
    } else if (!strcmp(cmd, "call")) {
        char *ep, *svc, *op, *input, *json = NULL;
        uint32_t timeout;
        int32_t rc;
        need_args(nrhs, 6, cmd);
        ep = arg_string(prhs[1], "endpoint");
        svc = arg_string(prhs[2], "service");
        op = arg_string(prhs[3], "operation");
        input = arg_optional_string(prhs[4], "inputJson");
        timeout = arg_timeout(prhs[5], "timeoutMs");
        rc = matlab_polycall_call(ep, svc, op, input, timeout, &json);
        mxFree(ep); mxFree(svc); mxFree(op);
        if (input) mxFree(input);
        if (rc != POLYCALL_OK) {
            char id[96], msg[1400];
            matlab_polycall_error(rc, id, sizeof id, msg, sizeof msg);
            if (json) {
                size_t n = strlen(msg);
                snprintf(msg + n, sizeof msg - n, " [remote: %.600s]", json);
                matlab_polycall_free(json);
            }
            mexErrMsgIdAndTxt(id, "%s", msg);
        }
        plhs[0] = mxCreateString(json);
        matlab_polycall_free(json);
    } else if (!strcmp(cmd, "peer_open")) {
        char *node, *bind, *token;
        polycall_peer_t h = 0;
        int32_t rc;
        need_args(nrhs, 4, cmd);
        node = arg_string(prhs[1], "nodeId");
        bind = arg_optional_string(prhs[2], "bindEndpoint");
        token = arg_optional_string(prhs[3], "authToken");
        rc = polycall_peer_open(node, bind, token, &h);
        mxFree(node);
        if (bind) mxFree(bind);
        if (token) {
            memset(token, 0, strlen(token));
            mxFree(token);
        }
        check(rc);
        plhs[0] = int32_scalar(h);
    } else if (!strcmp(cmd, "peer_close")) {
        need_args(nrhs, 2, cmd);
        check(polycall_peer_close(arg_handle(prhs[1])));
    } else if (!strcmp(cmd, "peer_cancel")) {
        need_args(nrhs, 2, cmd);
        check(polycall_peer_cancel(arg_handle(prhs[1])));
    } else if (!strcmp(cmd, "peer_register")) {
        char *id, *ep;
        int32_t rc;
        need_args(nrhs, 4, cmd);
        id = arg_string(prhs[2], "peerId");
        ep = arg_string(prhs[3], "endpoint");
        rc = polycall_peer_register(arg_handle(prhs[1]), id, ep);
        mxFree(id); mxFree(ep);
        check(rc);
    } else if (!strcmp(cmd, "peer_unregister")) {
        char *id;
        int32_t rc;
        need_args(nrhs, 3, cmd);
        id = arg_string(prhs[2], "peerId");
        rc = polycall_peer_unregister(arg_handle(prhs[1]), id);
        mxFree(id);
        check(rc);
    } else if (!strcmp(cmd, "peer_endpoint") || !strcmp(cmd, "peer_node_id") ||
               !strcmp(cmd, "peer_list") || !strcmp(cmd, "peer_health")) {
        int what = !strcmp(cmd, "peer_endpoint") ? MATLAB_POLYCALL_PEER_ENDPOINT
                 : !strcmp(cmd, "peer_node_id") ? MATLAB_POLYCALL_PEER_NODE_ID
                 : !strcmp(cmd, "peer_list") ? MATLAB_POLYCALL_PEER_LIST : MATLAB_POLYCALL_PEER_HEALTH;
        char *text = NULL;
        need_args(nrhs, 2, cmd);
        check(matlab_polycall_peer_text(what, arg_handle(prhs[1]), &text));
        plhs[0] = mxCreateString(text);
        matlab_polycall_free(text);
    } else if (!strcmp(cmd, "peer_ping")) {
        char *peer;
        int32_t rc;
        uint32_t timeout;
        need_args(nrhs, 4, cmd);
        peer = arg_string(prhs[2], "peer");
        timeout = arg_timeout(prhs[3], "timeoutMs");
        rc = polycall_peer_ping(arg_handle(prhs[1]), peer, timeout);
        mxFree(peer);
        check(rc);
    } else if (!strcmp(cmd, "peer_send")) {
        char *peer, *mid;
        const void *data;
        size_t len;
        char *text = NULL;
        uint32_t timeout;
        int32_t rc;
        need_args(nrhs, 6, cmd);
        peer = arg_string(prhs[2], "peer");
        if (mxIsUint8(prhs[3]) || mxIsInt8(prhs[3])) {
            data = mxGetData(prhs[3]);
            len = mxGetNumberOfElements(prhs[3]);
        } else if (mxIsChar(prhs[3])) {
            text = arg_string(prhs[3], "payload");
            data = text;
            len = strlen(text);
        } else {
            mxFree(peer);
            mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "payload must be uint8/int8 or a character vector");
            return;
        }
        mid = arg_optional_string(prhs[4], "messageId");
        timeout = arg_timeout(prhs[5], "timeoutMs");
        rc = polycall_peer_send(arg_handle(prhs[1]), peer, data, len, mid, timeout);
        mxFree(peer);
        if (mid) mxFree(mid);
        if (text) mxFree(text);
        check(rc);
    } else if (!strcmp(cmd, "peer_recv")) {
        char sender[POLYCALL_PEER_ID_MAX], mid[POLYCALL_MESSAGE_ID_MAX];
        unsigned char *payload = NULL;
        size_t len = 0;
        need_args(nrhs, 3, cmd);
        check(matlab_polycall_peer_recv(arg_handle(prhs[1]), arg_timeout(prhs[2], "timeoutMs"),
                                        sender, mid, &payload, &len));
        plhs[0] = mxCreateString(sender);
        if (nlhs > 1) plhs[1] = mxCreateString(mid);
        if (nlhs > 2) plhs[2] = bytes_array(payload, len);
        matlab_polycall_free(payload);
    } else {
        mexErrMsgIdAndTxt("polycall:E_INVALID_ARGUMENT", "unknown command '%s'", cmd);
    }
    mxFree(cmd);
}
