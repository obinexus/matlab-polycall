# matlab-polycall: C layer + MEX gateway over the Polycall binding ABI v1.
# libpolycall is found through pkg-config (polycall.pc).
#
#   make                     static C layer (lib/libmatlab_polycall.a)
#   make test-core           C-layer test against the real libpolycall, polycall start,
#                            polycall daemon and polycall peer serve (C-layer evidence,
#                            not MATLAB)
#   make test-core-valgrind  the same under valgrind memcheck
#   make test-core-asan      the same under AddressSanitizer + UBSan
#   make test-core-helgrind  the same under valgrind helgrind (race detector)
#   make test-core-tsan      the same under ThreadSanitizer
#   make mex                 MATLAB MEX gateway (needs MATLAB's mex)
#   make test-matlab         MATLAB tests (needs MATLAB; exit 77 = SKIP otherwise)
#   make test-loader-matlab  MATLAB loader errors (missing / 1.0 / ABI 2 library)
#   make octave              the same gateway built for GNU Octave (mkoctfile --mex)
#   make test-octave         Octave compatibility run (never MATLAB evidence)
#   make test-loader-octave  loader errors through the Octave-built gateway
#   make test-octave-asan    the gateway under ASan + UBSan in Octave
#
# Needs a POSIX shell (Linux/macOS; MSYS2 or Git Bash on Windows) and
# PKG_CONFIG_PATH=<polycall prefix>/lib/pkgconfig. A missing MATLAB, Octave or
# polycall CLI ends the target with exit status 77 (SKIP), never success.

CC ?= cc
AR ?= ar
MEX ?= mex
MATLAB ?= matlab
MKOCTFILE ?= mkoctfile
OCTAVE ?= octave-cli
PKG_CONFIG ?= pkg-config
POLYCALL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags polycall)
POLYCALL_LIBS ?= $(shell $(PKG_CONFIG) --libs polycall)

CPPFLAGS += -Iinclude
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
THREAD_LIBS ?= -lpthread

BUILD_DIR := build
LIB_DIR := lib
EXE_EXT :=
BIND_NOW :=
ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
THREAD_LIBS :=
else
UNAME_S := $(shell uname -s)
# Resolve every libpolycall symbol at load time, so an old 1.0 library fails
# with a clear "undefined symbol" load error instead of killing the host
# process on the first call (Windows import tables always bind at load).
ifeq ($(UNAME_S),Linux)
BIND_NOW := -Wl,-z,now
endif
ifeq ($(UNAME_S),Darwin)
BIND_NOW := -Wl,-bind_at_load
endif
endif
ADAPTER_OBJ := $(BUILD_DIR)/matlab_polycall.o
STATIC_LIB := $(LIB_DIR)/libmatlab_polycall.a
CORE_TEST := $(BUILD_DIR)/matlab_polycall_core_test$(EXE_EXT)

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

.PHONY: check-polycall
check-polycall:
	@$(PKG_CONFIG) --exists polycall || { \
	  echo "polycall.pc not found: set PKG_CONFIG_PATH=<polycall prefix>/lib/pkgconfig" >&2; exit 2; }

$(BUILD_DIR) $(LIB_DIR):
	mkdir -p $@

$(ADAPTER_OBJ): src/matlab_polycall.c include/matlab_polycall.h | $(BUILD_DIR) check-polycall
	$(CC) $(CPPFLAGS) $(POLYCALL_CFLAGS) $(CFLAGS) -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(CORE_TEST): src/matlab_polycall.c tests/matlab_polycall_core_test.c include/matlab_polycall.h | $(BUILD_DIR) check-polycall
	$(CC) $(CPPFLAGS) $(POLYCALL_CFLAGS) $(CFLAGS) src/matlab_polycall.c tests/matlab_polycall_core_test.c \
		$(LDFLAGS) $(BIND_NOW) $(POLYCALL_LIBS) $(THREAD_LIBS) -o $@

.PHONY: test test-core
test test-core: $(CORE_TEST)
	sh tests/run_core_test.sh $(CORE_TEST)

.PHONY: test-core-valgrind
test-core-valgrind: $(CORE_TEST)
	sh tests/run_core_test.sh valgrind --leak-check=full --errors-for-leak-kinds=definite --error-exitcode=9 $(CORE_TEST)

.PHONY: test-core-asan
test-core-asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=undefined" \
		LDFLAGS="-fsanitize=address,undefined" test-core

.PHONY: test-core-helgrind
test-core-helgrind: $(CORE_TEST)
	sh tests/run_core_test.sh valgrind --tool=helgrind --error-exitcode=9 $(CORE_TEST)

# ThreadSanitizer needs an address layout it supports: on kernels with
# vm.mmap_rnd_bits=32 it aborts ("unexpected memory mapping") unless ASLR is
# disabled for the process (setarch -R); use test-core-helgrind there.
.PHONY: test-core-tsan
test-core-tsan:
	$(MAKE) clean
	TSAN_OPTIONS="halt_on_error=1 $$TSAN_OPTIONS" $(MAKE) CFLAGS="-O1 -g -fsanitize=thread -fno-omit-frame-pointer" \
		LDFLAGS="-fsanitize=thread" test-core

.PHONY: mex
mex: | $(LIB_DIR) check-polycall
	$(MEX) -R2018a -Iinclude $(POLYCALL_CFLAGS) \
		src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(POLYCALL_LIBS) $(if $(BIND_NOW),LDFLAGS='$$LDFLAGS $(BIND_NOW)') \
		-outdir $(LIB_DIR) -output matlab_polycall_mex

.PHONY: test-matlab
test-matlab:
	@command -v $(MATLAB) >/dev/null 2>&1 || { echo "SKIP: MATLAB ($(MATLAB)) is not installed; MATLAB tests did not run" >&2; exit 77; }
	$(MAKE) mex
	EXPECT_C_NODE_PAYLOADS=1 sh tests/run_core_test.sh $(MATLAB) -batch "addpath(fullfile(pwd, 'src')); addpath(fullfile(pwd, 'lib')); \
		results = runtests(fullfile(pwd, 'tests', 'test_matlab_polycall.m')); disp(table(results)); assertSuccess(results);"

.PHONY: test-loader-matlab
test-loader-matlab:
	@command -v $(MATLAB) >/dev/null 2>&1 || { echo "SKIP: MATLAB ($(MATLAB)) is not installed; loader tests did not run" >&2; exit 77; }
	$(MAKE) mex
	sh tests/run_loader_test.sh $(MATLAB) $(LIB_DIR)

.PHONY: octave
octave: | $(BUILD_DIR) check-polycall
	@command -v $(MKOCTFILE) >/dev/null 2>&1 || { echo "SKIP: $(MKOCTFILE) is not installed" >&2; exit 77; }
	$(MKOCTFILE) --mex -Iinclude $(POLYCALL_CFLAGS) src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(BIND_NOW) $(POLYCALL_LIBS) -o $(BUILD_DIR)/matlab_polycall_mex

.PHONY: test-octave
test-octave: octave
	sh tests/run_octave_test.sh

.PHONY: test-loader-octave
test-loader-octave: octave
	sh tests/run_loader_test.sh $(OCTAVE) $(BUILD_DIR)

# The gateway itself under AddressSanitizer + UBSan, loaded into GNU Octave
# (libasan preloaded; Octave's own exit-time leaks are not checked).
.PHONY: test-octave-asan
test-octave-asan: | $(BUILD_DIR) check-polycall
	@command -v $(MKOCTFILE) >/dev/null 2>&1 || { echo "SKIP: $(MKOCTFILE) is not installed" >&2; exit 77; }
	CFLAGS="$$($(MKOCTFILE) -p CFLAGS) -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=undefined" \
	LDFLAGS="$$($(MKOCTFILE) -p LDFLAGS) -fsanitize=address,undefined" \
	$(MKOCTFILE) --mex -Iinclude $(POLYCALL_CFLAGS) src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(BIND_NOW) $(POLYCALL_LIBS) -o $(BUILD_DIR)/matlab_polycall_mex
	LD_PRELOAD="$$($(CC) -print-file-name=libasan.so)" ASAN_OPTIONS=detect_leaks=0:halt_on_error=1:abort_on_error=1 \
	UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 sh tests/run_octave_test.sh
	rm -f $(BUILD_DIR)/matlab_polycall_mex.*

.PHONY: verify-dry
verify-dry:
	sh scripts/verify-dry.sh

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(LIB_DIR)
