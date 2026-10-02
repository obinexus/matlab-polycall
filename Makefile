# matlab-polycall: C layer + MEX gateway over the Polycall binding ABI v1.
# libpolycall is found through pkg-config (polycall.pc).
#
#   make                 static C layer (lib/libmatlab_polycall.a)
#   make test-core       C-layer test against the real libpolycall, polycall start
#                        and polycall peer serve (C-layer evidence, not MATLAB)
#   make test-core-asan  the same under AddressSanitizer + UBSan
#   make mex             MATLAB MEX gateway (needs MATLAB's mex)
#   make test-matlab     MATLAB unit tests (needs MATLAB; SKIP otherwise)
#   make octave          the same gateway built for GNU Octave (mkoctfile --mex)
#   make test-octave     Octave compatibility run (not MATLAB evidence)
#
# Needs a POSIX shell (Linux/macOS; MSYS2 or Git Bash on Windows) and
# PKG_CONFIG_PATH=<polycall prefix>/lib/pkgconfig.

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
ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
THREAD_LIBS :=
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
		$(LDFLAGS) $(POLYCALL_LIBS) $(THREAD_LIBS) -o $@

.PHONY: test test-core
test test-core: $(CORE_TEST)
	sh tests/run_core_test.sh $(CORE_TEST)

.PHONY: test-core-valgrind
test-core-valgrind: $(CORE_TEST)
	sh tests/run_core_test.sh valgrind --leak-check=full --errors-for-leak-kinds=definite --error-exitcode=9 $(CORE_TEST)

.PHONY: test-core-asan
test-core-asan:
	$(MAKE) clean
	$(MAKE) CFLAGS="-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer" \
		LDFLAGS="-fsanitize=address,undefined" test-core

.PHONY: mex
mex: | $(LIB_DIR) check-polycall
	$(MEX) -R2018a -Iinclude $(POLYCALL_CFLAGS) \
		src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(POLYCALL_LIBS) -outdir $(LIB_DIR) -output matlab_polycall_mex

.PHONY: test-matlab
test-matlab:
	@command -v $(MATLAB) >/dev/null 2>&1 || { echo "SKIP: MATLAB ($(MATLAB)) is not installed"; exit 0; }
	$(MAKE) mex
	EXPECT_C_NODE_PAYLOADS=0 sh tests/run_core_test.sh $(MATLAB) -batch "addpath('src'); addpath('lib'); \
		results = runtests('tests/test_matlab_polycall.m'); assertSuccess(results);"

.PHONY: octave
octave: | $(BUILD_DIR) check-polycall
	$(MKOCTFILE) --mex -Iinclude $(POLYCALL_CFLAGS) src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(POLYCALL_LIBS) -o $(BUILD_DIR)/matlab_polycall_mex

.PHONY: test-octave
test-octave: octave
	sh tests/run_octave_test.sh

.PHONY: verify-dry
verify-dry:
	sh scripts/verify-dry.sh

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(LIB_DIR)
