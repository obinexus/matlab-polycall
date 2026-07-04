CC ?= gcc
AR ?= ar
MEX ?= mex
MATLAB ?= matlab

CPPFLAGS ?=
CPPFLAGS += -Iinclude -Igenerated
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic

BUILD_DIR := build
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/matlab_polycall.o
STATIC_LIB := $(LIB_DIR)/libmatlab_polycall.a
TEST_BIN := $(BUILD_DIR)/matlab_polycall_adapter_test

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
TEST_BIN := $(TEST_BIN)$(EXE_EXT)
endif

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

$(BUILD_DIR) $(LIB_DIR):
ifeq ($(OS),Windows_NT)
	@if not exist "$@" mkdir "$@"
else
	@mkdir -p $@
endif

$(ADAPTER_OBJ): src/matlab_polycall.c include/matlab_polycall.h generated/polycall/polycall_ffi.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(TEST_BIN): src/matlab_polycall.c tests/polycall_ffi_mock.c tests/matlab_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(TEST_BIN)
	$(TEST_BIN)

.PHONY: mex
mex: | $(LIB_DIR)
ifeq ($(OS),Windows_NT)
	@if "$(strip $(POLYCALL_LDFLAGS))"=="" (echo Set POLYCALL_LDFLAGS to the libpolycall import or static library & exit /b 2)
else
	@test -n "$(POLYCALL_LDFLAGS)" || (echo "Set POLYCALL_LDFLAGS to the libpolycall linker flags" && exit 2)
endif
	$(MEX) -R2018a -Iinclude -Igenerated \
		src/matlab_polycall_mex.c src/matlab_polycall.c \
		$(POLYCALL_LDFLAGS) -outdir $(LIB_DIR) -output matlab_polycall_mex

.PHONY: test-matlab
test-matlab: | $(BUILD_DIR)
	$(MEX) -R2018a -Iinclude -Igenerated -Itests \
		src/matlab_polycall_mex.c src/matlab_polycall.c \
		tests/polycall_ffi_mock.c -outdir $(BUILD_DIR) \
		-output matlab_polycall_mex
	$(MATLAB) -batch "addpath('src'); addpath('build'); results = runtests('tests/test_matlab_polycall.m'); assertSuccess(results);"

.PHONY: verify-dry
verify-dry:
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-dry.ps1
else
	sh scripts/verify-dry.sh
endif

.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@if exist "$(BUILD_DIR)" rmdir /s /q "$(BUILD_DIR)"
	@if exist "$(LIB_DIR)" rmdir /s /q "$(LIB_DIR)"
else
	rm -rf $(BUILD_DIR) $(LIB_DIR)
endif

-include $(ADAPTER_OBJ:.o=.d)
