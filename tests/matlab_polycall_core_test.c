/*
 * matlab-polycall C layer against the REAL libpolycall -- C-layer evidence,
 * not MATLAB (MATLAB itself is not run here).
 *
 *   matlab_polycall_core_test [scratch dir]   (default $MATLAB_POLYCALL_SCRATCH)
 *
 * Environment (set by tests/run_core_test.sh):
 *   POLYCALL_CLI             the polycall CLI (for C CLI -> C layer sends)
 *   MATLAB_POLYCALL_RUNTIME  host:port of a running `polycall start`
 *   MATLAB_POLYCALL_PEER     host:port of `polycall peer serve -n c-printer --print-messages`
 *   POLYCALL_DEV_TOKEN       the shared token of that node
 * Payloads sent to the printer node are also written to <scratch>/ml2c-*.bin
 * so the runner can compare them with what the C node printed.
 */
#include "matlab_polycall.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <process.h>
#include <windows.h>
typedef HANDLE thread_t;
#define THREAD_FN unsigned __stdcall
#define THREAD_RET return 0
static void thread_start(thread_t *t, unsigned (__stdcall *fn)(void *), void *arg)
{ *t = (HANDLE)_beginthreadex(NULL, 0, fn, arg, 0, NULL); }
static void thread_join(thread_t t) { WaitForSingleObject(t, INFINITE); CloseHandle(t); }
static void sleep_ms(unsigned ms) { Sleep(ms); }
#else
#include <pthread.h>
#include <time.h>
typedef pthread_t thread_t;
#define THREAD_FN void *
#define THREAD_RET return NULL
static void thread_start(thread_t *t, void *(*fn)(void *), void *arg) { pthread_create(t, NULL, fn, arg); }
static void thread_join(thread_t t) { pthread_join(t, NULL); }
static void sleep_ms(unsigned ms) { struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L }; nanosleep(&ts, NULL); }
#endif

static int checks = 0, failures = 0;
#define CHECK(cond, what) do { ++checks; if (cond) printf("PASS %s\n", what); \
    else { ++failures; printf("FAIL %s (%s:%d)\n", what, __FILE__, __LINE__); } } while (0)

static const char *dir;
static const char *token;

static void write_file(const char *path, const void *data, size_t len)
{
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(2); }
    if (len) fwrite(data, 1, len, f);
    fclose(f);
}

typedef struct { const char *name; unsigned char *data; size_t len; } payload_t;

static payload_t payloads[4];

static void make_payloads(void)
{
    static const char utf8[] = "h\xc3\xa9llo w\xc3\xb6rld \xe2\x80\x93 \xe6\xbc\xa2\xe5\xad\x97 \xf0\x9f\x9a\x80";
    size_t i;
    payloads[0].name = "empty"; payloads[0].data = (unsigned char *)malloc(1); payloads[0].len = 0;
    payloads[1].name = "utf8"; payloads[1].len = sizeof utf8 - 1;
    payloads[1].data = (unsigned char *)malloc(payloads[1].len); memcpy(payloads[1].data, utf8, payloads[1].len);
    payloads[2].name = "binaryNul"; payloads[2].len = 262;
    payloads[2].data = (unsigned char *)malloc(262);
    payloads[2].data[0] = 0; payloads[2].data[1] = 0; payloads[2].data[2] = 10; payloads[2].data[3] = 13; payloads[2].data[4] = 0;
    for (i = 0; i < 256; ++i) payloads[2].data[5 + i] = (unsigned char)i;
    payloads[2].data[261] = 0;
    payloads[3].name = "exactlyOneMiB"; payloads[3].len = POLYCALL_PEER_MAX_PAYLOAD;
    payloads[3].data = (unsigned char *)malloc(payloads[3].len);
    for (i = 0; i < payloads[3].len; ++i) payloads[3].data[i] = (unsigned char)((i * 31 + 7) & 0xff);
}

/* ------------------------------------------------------------------ config */

static void test_config(void)
{
    char path[1024], v[32], id[96], msg[1400];
    char *json = NULL;
    CHECK(polycall_ffi_abi_version() == 1, "binding ABI is 1");
    CHECK(matlab_polycall_check_abi(msg, sizeof msg) == POLYCALL_OK, "check_abi");
    CHECK(matlab_polycall_version(v, sizeof v) > 0 && strncmp(v, "1.", 2) == 0, "library version 1.x");
    CHECK(matlab_polycall_run_config("matlab-polycallrc") == POLYCALL_OK, "matlab-polycallrc valid (strict)");
    CHECK(matlab_polycall_run_config("examples/matlab-polycallrc") == POLYCALL_OK, "examples/matlab-polycallrc valid (strict)");
    snprintf(path, sizeof path, "%s/missing-polycallrc", dir);
    remove(path);
    CHECK(matlab_polycall_run_config(path) == POLYCALL_E_NOT_FOUND, "missing -> E_NOT_FOUND");
    CHECK(matlab_polycall_run_config("") == POLYCALL_E_INVALID_ARGUMENT, "empty path -> E_INVALID_ARGUMENT");
    CHECK(matlab_polycall_run_config(NULL) == POLYCALL_E_INVALID_ARGUMENT, "NULL path -> E_INVALID_ARGUMENT");
    snprintf(path, sizeof path, "%s/bad-polycallrc", dir);
    write_file(path, "a = b = c\n", 10);
    CHECK(matlab_polycall_run_config(path) == POLYCALL_E_CONFIG, "malformed -> E_CONFIG");
    matlab_polycall_error(POLYCALL_E_CONFIG, id, sizeof id, msg, sizeof msg);
    CHECK(strcmp(id, "polycall:E_CONFIG") == 0, "error id polycall:E_CONFIG");
    CHECK(strstr(msg, "POLYCALL_E_CONFIG (-13): invalid configuration -- ") == msg && strstr(msg, "malformed"),
          "error message carries name, code and polycall_last_error detail");
    snprintf(path, sizeof path, "%s/unknown-polycallrc", dir);
    write_file(path, "log_level=info\nnope_key=1\n", 26);
    CHECK(matlab_polycall_validate_config(path, 0) == POLYCALL_OK, "unknown key, validate mode -> OK");
    CHECK(matlab_polycall_run_config(path) == POLYCALL_E_CONFIG, "unknown key, strict -> E_CONFIG");
    snprintf(path, sizeof path, "%s/tls-polycallrc", dir);
    write_file(path, "tls_enabled=true\ncert_file=/c.pem\nkey_file=/k.pem\n", 49);
    CHECK(matlab_polycall_run_config(path) == POLYCALL_E_UNSUPPORTED, "tls_enabled=true -> E_UNSUPPORTED");
    CHECK(matlab_polycall_describe("matlab-polycallrc", &json) == POLYCALL_OK && json && json[0] == '{' &&
          strstr(json, "log_level"), "describe -> JSON with the file's keys");
    matlab_polycall_free(json);
}

/* -------------------------------------------------------------------- call */

static void test_call(const char *rt)
{
    char *out = NULL, id[96], msg[1400];
    int32_t rc;
    if (!rt) {
        printf("SKIP call checks: MATLAB_POLYCALL_RUNTIME not set\n");
        return;
    }
    rc = matlab_polycall_call(rt, "inventory", "get", "{\"item_id\":\"widget-a\"}", 2000, &out);
    CHECK(rc == POLYCALL_OK && out && strcmp(out, "{\"item_id\":\"widget-a\",\"quantity\":42,\"in_stock\":true}") == 0,
          "call inventory.get widget-a -> exact output");
    matlab_polycall_free(out); out = NULL;
    rc = matlab_polycall_call(rt, "debug", "echo", NULL, 2000, &out);
    CHECK(rc == POLYCALL_OK && out && strcmp(out, "{\"echo\":null}") == 0, "call with NULL input -> null");
    matlab_polycall_free(out); out = NULL;
    rc = matlab_polycall_call(rt, "nope", "op", "{}", 2000, &out);
    matlab_polycall_error(rc, id, sizeof id, msg, sizeof msg);
    CHECK(rc == POLYCALL_E_NOT_FOUND && out && strstr(out, "operation.unknown"), "unknown operation -> E_NOT_FOUND + remote error");
    CHECK(strcmp(id, "polycall:E_NOT_FOUND") == 0 && strstr(msg, "(-7)"), "error id/message for E_NOT_FOUND");
    matlab_polycall_free(out); out = NULL;
    rc = matlab_polycall_call(rt, "debug", "sleep", "{\"ms\":2000}", 200, &out);
    CHECK(rc == POLYCALL_E_TIMEOUT && out && strstr(out, "deadline.exceeded"), "deadline -> E_TIMEOUT");
    matlab_polycall_free(out); out = NULL;
    rc = matlab_polycall_call(rt, "inventory", "get", "{}", 2000, &out);
    CHECK(rc == POLYCALL_E_REMOTE && out && strstr(out, "input.invalid"), "invalid input -> E_REMOTE input.invalid");
    matlab_polycall_free(out); out = NULL;
    rc = matlab_polycall_call(rt, "debug", "echo", "{not json", 2000, &out);
    CHECK(rc == POLYCALL_E_INVALID_ARGUMENT && out == NULL, "invalid JSON -> E_INVALID_ARGUMENT");
    rc = matlab_polycall_call(rt, "debug", "echo", "1", 0, &out);
    CHECK(rc == POLYCALL_E_INVALID_ARGUMENT, "timeout 0 -> E_INVALID_ARGUMENT");
    rc = matlab_polycall_call("127.0.0.1:1", "debug", "echo", "1", 1000, &out);
    CHECK(rc == POLYCALL_E_TRANSPORT, "no runtime -> E_TRANSPORT");
    matlab_polycall_free(out);
}

/* ------------------------------------------------------------------- peers */

typedef struct { polycall_peer_t h; int32_t rc; } waiter_t;

static THREAD_FN blocked_recv(void *arg)
{
    waiter_t *w = (waiter_t *)arg;
    char s[POLYCALL_PEER_ID_MAX], m[POLYCALL_MESSAGE_ID_MAX];
    unsigned char *p = NULL;
    size_t n = 0;
    w->rc = matlab_polycall_peer_recv(w->h, UINT32_MAX, s, m, &p, &n);
    matlab_polycall_free(p);
    THREAD_RET;
}

typedef struct { polycall_peer_t h; const char *to; int index; int32_t rc; } sender_t;

static THREAD_FN concurrent_send(void *arg)
{
    sender_t *s = (sender_t *)arg;
    char mid[32], body[32];
    snprintf(mid, sizeof mid, "conc-%d", s->index);
    snprintf(body, sizeof body, "payload-%d", s->index);
    s->rc = polycall_peer_send(s->h, s->to, body, strlen(body), mid, 5000);
    THREAD_RET;
}

static int recv_expect(polycall_peer_t h, const char *from, const char *mid, const unsigned char *data, size_t len)
{
    char s[POLYCALL_PEER_ID_MAX], m[POLYCALL_MESSAGE_ID_MAX];
    unsigned char *p = NULL;
    size_t n = 0;
    int ok = matlab_polycall_peer_recv(h, 5000, s, m, &p, &n) == POLYCALL_OK &&
             strcmp(s, from) == 0 && strcmp(m, mid) == 0 && n == len && (len == 0 || memcmp(p, data, len) == 0);
    matlab_polycall_free(p);
    return ok;
}

static void test_peers(const char *printer, const char *cli)
{
    polycall_peer_t a = 0, b = 0, c = 0, bad = 0;
    char *text = NULL, ep_a[POLYCALL_ENDPOINT_MAX], ep_b[POLYCALL_ENDPOINT_MAX], what[160], cmd[2048], path[1024];
    char s[POLYCALL_PEER_ID_MAX], m[POLYCALL_MESSAGE_ID_MAX];
    unsigned char *p = NULL;
    size_t i, n = 0;
    waiter_t w;
    thread_t t, ts[8];
    sender_t senders[8];

    CHECK(polycall_peer_open("matlab-a", "127.0.0.1:0", token, &a) == POLYCALL_OK && a > 0, "open node A");
    CHECK(polycall_peer_open("matlab-b", "127.0.0.1:0", token, &b) == POLYCALL_OK && b > 0, "open node B");
    CHECK(matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_ENDPOINT, a, &text) == POLYCALL_OK, "endpoint A");
    snprintf(ep_a, sizeof ep_a, "%s", text ? text : ""); matlab_polycall_free(text); text = NULL;
    matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_ENDPOINT, b, &text);
    snprintf(ep_b, sizeof ep_b, "%s", text ? text : ""); matlab_polycall_free(text); text = NULL;
    CHECK(matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_NODE_ID, a, &text) == POLYCALL_OK && strcmp(text, "matlab-a") == 0, "node id A");
    matlab_polycall_free(text); text = NULL;
    CHECK(polycall_peer_register(a, "matlab-b", ep_b) == POLYCALL_OK, "A registers B");
    CHECK(polycall_peer_register(b, "matlab-a", ep_a) == POLYCALL_OK, "B registers A");
    CHECK(polycall_peer_ping(a, "matlab-b", 2000) == POLYCALL_OK, "A pings B by id");

    for (i = 0; i < 4; ++i) {
        char mid[64];
        snprintf(mid, sizeof mid, "a2b-%s", payloads[i].name);
        snprintf(what, sizeof what, "A -> B %s: exact bytes, sender, id", payloads[i].name);
        CHECK(polycall_peer_send(a, "matlab-b", payloads[i].data, payloads[i].len, mid, 10000) == POLYCALL_OK &&
              recv_expect(b, "matlab-a", mid, payloads[i].data, payloads[i].len), what);
        snprintf(mid, sizeof mid, "b2a-%s", payloads[i].name);
        snprintf(what, sizeof what, "B -> A %s: exact bytes, sender, id", payloads[i].name);
        CHECK(polycall_peer_send(b, "matlab-a", payloads[i].data, payloads[i].len, mid, 10000) == POLYCALL_OK &&
              recv_expect(a, "matlab-b", mid, payloads[i].data, payloads[i].len), what);
    }
    p = (unsigned char *)calloc(1, POLYCALL_PEER_MAX_PAYLOAD + 1);
    CHECK(polycall_peer_send(a, "matlab-b", p, POLYCALL_PEER_MAX_PAYLOAD + 1, "too-big", 2000) == POLYCALL_E_TOO_LARGE,
          "1 MiB + 1 -> E_TOO_LARGE");
    free(p); p = NULL;

    CHECK(polycall_peer_send(a, "matlab-b", "d", 1, "dup-1", 2000) == POLYCALL_OK &&
          polycall_peer_send(a, "matlab-b", "d", 1, "dup-1", 2000) == POLYCALL_OK, "duplicate id acknowledged twice");
    CHECK(recv_expect(b, "matlab-a", "dup-1", (const unsigned char *)"d", 1) &&
          matlab_polycall_peer_recv(b, 200, s, m, &p, &n) == POLYCALL_E_TIMEOUT, "duplicate delivered once; then timeout");

    CHECK(polycall_peer_open("matlab-c", NULL, token, &c) == POLYCALL_OK, "open send-only node C");
    CHECK(polycall_peer_send(c, ep_b, "x", 1, "from-c", 2000) == POLYCALL_OK && recv_expect(b, "matlab-c", "from-c", (const unsigned char *)"x", 1),
          "C -> B by host:port");
    CHECK(matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_LIST, b, &text) == POLYCALL_OK && !strstr(text, "matlab-c"),
          "registry ownership: receiving never registered the sender");
    matlab_polycall_free(text); text = NULL;
    CHECK(polycall_peer_unregister(b, "nobody") == POLYCALL_E_NOT_FOUND, "unregister unknown -> E_NOT_FOUND");

    CHECK(polycall_peer_open("matlab-bad", NULL, "wrong-token", &bad) == POLYCALL_OK &&
          polycall_peer_send(bad, ep_b, "x", 1, "auth-1", 2000) == POLYCALL_E_AUTH, "wrong token -> E_AUTH");
    CHECK(polycall_peer_send(a, "127.0.0.1:1", "x", 1, "dead-1", 2000) == POLYCALL_E_TRANSPORT, "dead peer -> E_TRANSPORT");
    CHECK(polycall_peer_register(a, "impostor", ep_b) == POLYCALL_OK &&
          polycall_peer_send(a, "impostor", "x", 1, "imp-1", 2000) == POLYCALL_E_PROTOCOL, "wrong identity -> E_PROTOCOL");
    matlab_polycall_peer_recv(b, 500, s, m, &p, &n);   /* the impostor message did reach B: drop it */
    matlab_polycall_free(p); p = NULL;

    /* too-small buffer: the C layer's growth path keeps the message queued */
    CHECK(polycall_peer_send(a, "matlab-b", payloads[3].data, payloads[3].len, "grow-1", 10000) == POLYCALL_OK, "send 1 MiB for growth");
    {
        unsigned char small[16];
        size_t need = 0;
        int32_t rc = polycall_peer_recv(b, 2000, s, sizeof s, m, sizeof m, small, sizeof small, &need);
        CHECK(rc == POLYCALL_E_TOO_LARGE && need == payloads[3].len, "raw recv with a small buffer -> E_TOO_LARGE, needed size");
    }
    CHECK(recv_expect(b, "matlab-a", "grow-1", payloads[3].data, payloads[3].len), "message stayed queued; C layer grows and receives it");

    /* concurrent senders */
    for (i = 0; i < 8; ++i) {
        senders[i].h = (i % 2) ? a : c;
        senders[i].to = ep_b;
        senders[i].index = (int)i;
        thread_start(&ts[i], concurrent_send, &senders[i]);
    }
    for (i = 0; i < 8; ++i) thread_join(ts[i]);
    {
        int all_ok = 1, got = 0;
        for (i = 0; i < 8; ++i) all_ok &= senders[i].rc == POLYCALL_OK;
        while (matlab_polycall_peer_recv(b, 500, s, m, &p, &n) == POLYCALL_OK) {
            ++got;
            matlab_polycall_free(p); p = NULL;
        }
        CHECK(all_ok && got == 8, "8 concurrent senders: each delivered exactly once");
    }

    /* cancel / close wake a blocked receive */
    w.h = b; w.rc = 0;
    thread_start(&t, blocked_recv, &w);
    sleep_ms(200);
    polycall_peer_cancel(b);
    thread_join(t);
    CHECK(w.rc == POLYCALL_E_CANCELLED, "cancel wakes a blocked recv (E_CANCELLED)");

    /* interop with the C CLI node */
    if (printer && cli) {
        CHECK(polycall_peer_register(a, "c-printer", printer) == POLYCALL_OK && polycall_peer_ping(a, "c-printer", 2000) == POLYCALL_OK,
              "ping the polycall peer serve node by id");
        for (i = 0; i < 4; ++i) {
            char mid[64];
            snprintf(mid, sizeof mid, "ml2c-%s", payloads[i].name);
            snprintf(path, sizeof path, "%s/%s.bin", dir, mid);
            write_file(path, payloads[i].data, payloads[i].len);
            snprintf(what, sizeof what, "C layer -> polycall peer serve: %s acknowledged", payloads[i].name);
            CHECK(polycall_peer_send(a, "c-printer", payloads[i].data, payloads[i].len, mid, 10000) == POLYCALL_OK, what);
#if defined(_WIN32)
            /* cmd.exe strips one outer pair of quotes */
            snprintf(cmd, sizeof cmd, "\"\"%s\" peer send --to %s --payload-file \"%s\" --from cli-sender --id c2ml-%s -t 10000\"",
                     cli, ep_a, path, payloads[i].name);
#else
            snprintf(cmd, sizeof cmd, "\"%s\" peer send --to %s --payload-file \"%s\" --from cli-sender --id c2ml-%s -t 10000",
                     cli, ep_a, path, payloads[i].name);
#endif
            snprintf(what, sizeof what, "polycall peer send -> C layer: %s exact bytes, sender, id", payloads[i].name);
            {
                char cmid[64];
                int sys = system(cmd);
                snprintf(cmid, sizeof cmid, "c2ml-%s", payloads[i].name);
                CHECK(sys == 0 && recv_expect(a, "cli-sender", cmid, payloads[i].data, payloads[i].len), what);
            }
        }
    } else {
        printf("SKIP C CLI interop: MATLAB_POLYCALL_PEER / POLYCALL_CLI not set\n");
    }

    w.h = a; w.rc = 0;
    thread_start(&t, blocked_recv, &w);
    sleep_ms(200);
    CHECK(polycall_peer_close(a) == POLYCALL_OK, "close A while a recv is blocked");
    thread_join(t);
    CHECK(w.rc == POLYCALL_E_CLOSED, "close wakes a blocked recv (E_CLOSED)");
    CHECK(polycall_peer_close(a) == POLYCALL_E_INVALID_HANDLE, "double close -> E_INVALID_HANDLE");
    CHECK(polycall_peer_send(a, ep_b, "x", 1, NULL, 1000) == POLYCALL_E_INVALID_HANDLE &&
          matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_HEALTH, a, &text) == POLYCALL_E_INVALID_HANDLE &&
          matlab_polycall_peer_recv(a, 0, s, m, &p, &n) == POLYCALL_E_INVALID_HANDLE, "calls after close -> E_INVALID_HANDLE");
    CHECK(polycall_peer_close(0) == POLYCALL_E_INVALID_HANDLE && polycall_peer_close(-5) == POLYCALL_E_INVALID_HANDLE &&
          polycall_peer_close(0x7fffff01) == POLYCALL_E_INVALID_HANDLE, "invalid handles -> E_INVALID_HANDLE");
    CHECK(matlab_polycall_peer_text(MATLAB_POLYCALL_PEER_HEALTH, b, &text) == POLYCALL_OK && strstr(text, "\"node_id\":\"matlab-b\""),
          "health JSON of B");
    matlab_polycall_free(text);
    polycall_peer_close(b);
    polycall_peer_close(c);
    polycall_peer_close(bad);
}

int main(int argc, char **argv)
{
    dir = argc > 1 ? argv[1] : getenv("MATLAB_POLYCALL_SCRATCH");
    if (!dir || !*dir) dir = ".";
    token = getenv("POLYCALL_DEV_TOKEN");
    if (!token || !*token) token = "matlab-c-layer-test-token";
    make_payloads();
    test_config();
    test_call(getenv("MATLAB_POLYCALL_RUNTIME"));
    test_peers(getenv("MATLAB_POLYCALL_PEER"), getenv("POLYCALL_CLI"));
    printf("%d checks, %d failed\n", checks, failures);
    {
        int i;
        for (i = 0; i < 4; ++i) free(payloads[i].data);
    }
    return failures ? 1 : 0;
}
