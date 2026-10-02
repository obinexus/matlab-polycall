#ifndef MATLAB_POLYCALL_H
#define MATLAB_POLYCALL_H

/*
 * matlab-polycall C layer over the Polycall binding ABI v1 (<polycall.h>).
 *
 * The MEX gateway (src/matlab_polycall_mex.c) only converts mxArrays; all
 * buffer sizing, retry-on-E_TOO_LARGE and error formatting lives here so it
 * can be tested against the real libpolycall without MATLAB. Variable-size
 * outputs are allocated with the allocator set by
 * matlab_polycall_set_allocator() (mxMalloc in MEX, malloc by default) and
 * released by the caller with the matching free.
 */

#include <stddef.h>
#include <stdint.h>

#include <polycall.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MATLAB_POLYCALL_ABI 1

typedef void *(*matlab_polycall_alloc_fn)(size_t);
typedef void (*matlab_polycall_free_fn)(void *);

void matlab_polycall_set_allocator(matlab_polycall_alloc_fn alloc_fn, matlab_polycall_free_fn free_fn);
void matlab_polycall_free(void *p);

/* POLYCALL_OK when the loaded library speaks binding ABI 1, else
 * POLYCALL_E_UNSUPPORTED with a message in msg (snprintf rules). */
int32_t matlab_polycall_check_abi(char *msg, size_t cap);

/* Library version ("1.1.0") into buf. Returns its length or a negative status. */
int32_t matlab_polycall_version(char *buf, size_t cap);

/* Exactly polycall_ffi_run_config(config_path, 1). */
int32_t matlab_polycall_run_config(const char *config_path);

/* polycall_ffi_run_config(config_path, strict ? 1 : 0). */
int32_t matlab_polycall_validate_config(const char *config_path, int strict);

/* polycall_ffi_describe() into an allocated, NUL-terminated JSON string. */
int32_t matlab_polycall_describe(const char *config_path, char **json_out);

/* polycall_call() with a growing output buffer. On POLYCALL_OK *json_out is
 * the output JSON; on E_REMOTE / E_NOT_FOUND / E_TIMEOUT / E_BUSY / E_AUTH
 * it is the remote error object (when the runtime sent one). */
int32_t matlab_polycall_call(const char *endpoint, const char *service, const char *operation,
                             const char *input_json, uint32_t timeout_ms, char **json_out);

/* Peer text outputs with automatic sizing. */
enum {
    MATLAB_POLYCALL_PEER_ENDPOINT = 1,
    MATLAB_POLYCALL_PEER_NODE_ID = 2,
    MATLAB_POLYCALL_PEER_LIST = 3,
    MATLAB_POLYCALL_PEER_HEALTH = 4
};
int32_t matlab_polycall_peer_text(int what, polycall_peer_t handle, char **text_out);

/* polycall_peer_recv() that grows its payload buffer when the message is
 * larger than the first guess (the message stays queued in between). */
int32_t matlab_polycall_peer_recv(polycall_peer_t handle, uint32_t timeout_ms,
                                  char sender[POLYCALL_PEER_ID_MAX],
                                  char message_id[POLYCALL_MESSAGE_ID_MAX],
                                  unsigned char **payload_out, size_t *payload_len);

/* MATLAB error identifier ("polycall:E_TIMEOUT") and message
 * ("POLYCALL_E_TIMEOUT (-4): deadline exceeded -- <polycall_last_error>")
 * for a failed status. Call it right after the failing call, on the same
 * thread. */
void matlab_polycall_error(int32_t status, char *id_buf, size_t id_cap,
                           char *msg_buf, size_t msg_cap);

#ifdef __cplusplus
}
#endif

#endif
