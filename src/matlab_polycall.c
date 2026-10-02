#include "matlab_polycall.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static matlab_polycall_alloc_fn g_alloc = malloc;
static matlab_polycall_free_fn g_free = free;

void matlab_polycall_set_allocator(matlab_polycall_alloc_fn alloc_fn, matlab_polycall_free_fn free_fn)
{
    g_alloc = alloc_fn ? alloc_fn : malloc;
    g_free = free_fn ? free_fn : free;
}

void matlab_polycall_free(void *p)
{
    if (p) g_free(p);
}

int32_t matlab_polycall_check_abi(char *msg, size_t cap)
{
    int abi = polycall_ffi_abi_version();
    if (abi != MATLAB_POLYCALL_ABI) {
        if (msg && cap) {
            snprintf(msg, cap, "libpolycall binding ABI %d, matlab-polycall needs %d", abi, MATLAB_POLYCALL_ABI);
        }
        return POLYCALL_E_UNSUPPORTED;
    }
    if (msg && cap) msg[0] = '\0';
    return POLYCALL_OK;
}

int32_t matlab_polycall_version(char *buf, size_t cap)
{
    if (!buf || cap == 0 || cap > 0x7fffffff) return POLYCALL_E_INVALID_ARGUMENT;
    return polycall_ffi_version(buf, (int)cap);
}

int32_t matlab_polycall_run_config(const char *config_path)
{
    return (int32_t)polycall_ffi_run_config(config_path, 1);
}

int32_t matlab_polycall_validate_config(const char *config_path, int strict)
{
    return (int32_t)polycall_ffi_run_config(config_path, strict ? 1 : 0);
}

static char *dup_n(const char *s, size_t n)
{
    char *p = (char *)g_alloc(n + 1);
    if (!p) return NULL;
    if (n) memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

int32_t matlab_polycall_describe(const char *config_path, char **json_out)
{
    size_t cap = 4096;
    if (!json_out) return POLYCALL_E_INVALID_ARGUMENT;
    *json_out = NULL;
    for (;;) {
        char *buf = (char *)malloc(cap);
        int rc;
        if (!buf) return POLYCALL_E_NO_MEMORY;
        rc = polycall_ffi_describe(config_path, buf, (int)cap);
        if (rc < 0) {
            free(buf);
            return rc;
        }
        if ((size_t)rc < cap) {
            *json_out = dup_n(buf, (size_t)rc);
            free(buf);
            return *json_out ? POLYCALL_OK : POLYCALL_E_NO_MEMORY;
        }
        free(buf);
        if ((size_t)rc + 1 > (64u << 20)) return POLYCALL_E_TOO_LARGE;
        cap = (size_t)rc + 1;
    }
}

int32_t matlab_polycall_call(const char *endpoint, const char *service, const char *operation,
                             const char *input_json, uint32_t timeout_ms, char **json_out)
{
    /* the call is never retried (it may not be idempotent), so the buffer is
     * sized for the largest output up front */
    const size_t cap = (size_t)POLYCALL_CALL_MAX_OUTPUT + 1;
    char *buf;
    size_t len = 0;
    int rc;
    if (!json_out) return POLYCALL_E_INVALID_ARGUMENT;
    *json_out = NULL;
    buf = (char *)malloc(cap);
    if (!buf) return POLYCALL_E_NO_MEMORY;
    buf[0] = '\0';
    rc = polycall_call(endpoint, service, operation, input_json, timeout_ms, buf, cap, &len);
    if (buf[0] != '\0' || rc == POLYCALL_OK) {
        *json_out = dup_n(buf, strlen(buf));
        if (!*json_out && rc == POLYCALL_OK) rc = POLYCALL_E_NO_MEMORY;
    }
    free(buf);
    return rc;
}

int32_t matlab_polycall_peer_text(int what, polycall_peer_t handle, char **text_out)
{
    size_t cap = 512, len = 0;
    if (!text_out) return POLYCALL_E_INVALID_ARGUMENT;
    *text_out = NULL;
    for (;;) {
        char *buf = (char *)malloc(cap);
        int rc;
        if (!buf) return POLYCALL_E_NO_MEMORY;
        len = 0;
        switch (what) {
        case MATLAB_POLYCALL_PEER_ENDPOINT: rc = polycall_peer_endpoint(handle, buf, cap); break;
        case MATLAB_POLYCALL_PEER_NODE_ID: rc = polycall_peer_node_id(handle, buf, cap); break;
        case MATLAB_POLYCALL_PEER_LIST: rc = polycall_peer_list(handle, buf, cap, &len); break;
        case MATLAB_POLYCALL_PEER_HEALTH: rc = polycall_peer_health(handle, buf, cap, &len); break;
        default: free(buf); return POLYCALL_E_INVALID_ARGUMENT;
        }
        if (rc == POLYCALL_E_TOO_LARGE && len + 1 > cap && len < (16u << 20)) {
            free(buf);
            cap = len + 1;
            continue;
        }
        if (rc != POLYCALL_OK) {
            free(buf);
            return rc;
        }
        *text_out = dup_n(buf, strlen(buf));
        free(buf);
        return *text_out ? POLYCALL_OK : POLYCALL_E_NO_MEMORY;
    }
}

int32_t matlab_polycall_peer_recv(polycall_peer_t handle, uint32_t timeout_ms,
                                  char sender[POLYCALL_PEER_ID_MAX],
                                  char message_id[POLYCALL_MESSAGE_ID_MAX],
                                  unsigned char **payload_out, size_t *payload_len)
{
    size_t cap = 64u * 1024u;
    if (!payload_out || !payload_len || !sender || !message_id) return POLYCALL_E_INVALID_ARGUMENT;
    *payload_out = NULL;
    *payload_len = 0;
    for (;;) {
        /* +1 so a zero-length payload still has a valid buffer */
        unsigned char *buf = (unsigned char *)g_alloc(cap + 1);
        size_t len = 0;
        int rc;
        if (!buf) return POLYCALL_E_NO_MEMORY;
        rc = polycall_peer_recv(handle, timeout_ms, sender, POLYCALL_PEER_ID_MAX,
                                message_id, POLYCALL_MESSAGE_ID_MAX, buf, cap, &len);
        if (rc == POLYCALL_E_TOO_LARGE && len > cap && len <= POLYCALL_PEER_MAX_PAYLOAD) {
            /* the message stayed queued: retry with a buffer that fits */
            g_free(buf);
            cap = len;
            continue;
        }
        if (rc != POLYCALL_OK) {
            g_free(buf);
            return rc;
        }
        *payload_out = buf;
        *payload_len = len;
        return POLYCALL_OK;
    }
}

void matlab_polycall_error(int32_t status, char *id_buf, size_t id_cap,
                           char *msg_buf, size_t msg_cap)
{
    char detail[1024];
    const char *text = polycall_strerror((int)status);
    const char *colon = strchr(text, ':');
    size_t nlen = colon ? (size_t)(colon - text) : strlen(text);
    const char *name = text;
    size_t shown;
    polycall_last_error(detail, sizeof detail);
    if (nlen > 9 && strncmp(text, "POLYCALL_", 9) == 0) {
        name = text + 9;   /* "E_TIMEOUT" */
        nlen -= 9;
    }
    if (id_buf && id_cap) {
        shown = nlen < 64 ? nlen : 64;
        snprintf(id_buf, id_cap, "polycall:%.*s", (int)shown, name);
    }
    if (msg_buf && msg_cap) {
        if (detail[0]) {
            snprintf(msg_buf, msg_cap, "%.*s (%ld): %s -- %s", (int)(colon ? (size_t)(colon - text) : strlen(text)),
                     text, (long)status, colon ? colon + 2 : "", detail);
        } else {
            snprintf(msg_buf, msg_cap, "%.*s (%ld): %s", (int)(colon ? (size_t)(colon - text) : strlen(text)),
                     text, (long)status, colon ? colon + 2 : "");
        }
    }
}
