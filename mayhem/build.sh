#!/usr/bin/env bash
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Project + saber are built with the base image's $SANITIZER_FLAGS (ASan + UBSan,
# both halting). Overridable via --build-arg SANITIZER_FLAGS=...; an explicit empty
# value is kept (= not :=) and builds with no sanitizers. Upstream's own CI builds
# SVF with -fsanitize=address against the same prebuilt libLLVM (SVF_SANITIZE=address).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS

cd "$SRC"

# LLVM 21 (RTTI build) and Z3 are baked into the image by mayhem/Dockerfile under
# $SVF_DEPS (pinned by sha256), outside the source tree. They must NOT live in the
# tree: upstream's .gitignore ignores *.obj, so an in-tree copy is deleted by
# `git clean -ffdX` and the offline PATCH re-build could not fetch it again.
: "${SVF_DEPS:=/opt/toolchains/svf}"
export LLVM_DIR="$SVF_DEPS/llvm"
export Z3_DIR="$SVF_DEPS/z3"
[ -f "$LLVM_DIR/lib/cmake/llvm/LLVMConfig.cmake" ] || { echo "missing LLVM under $LLVM_DIR (built by mayhem/Dockerfile)" >&2; exit 1; }
[ -f "$Z3_DIR/bin/libz3.so" ] || { echo "missing Z3 under $Z3_DIR (built by mayhem/Dockerfile)" >&2; exit 1; }
export PATH="$Z3_DIR/bin:$PATH"

BUILD_DIR="$SRC/Release-build"
rm -rf "$BUILD_DIR"

# LeakSanitizer off at build time (fleet policy): leaks are not the bug class this
# target fuzzes for. ASan and UBSan stay fully active. Linked into saber only when
# the build actually uses ASan.
LSAN_OBJ=""
case "$SANITIZER_FLAGS" in
  *address*)
    mkdir -p "$BUILD_DIR"; LSAN_OBJ="$BUILD_DIR/lsan_off.o"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$LSAN_OBJ" ;;
esac

# Build with the org-base clang (has ASan/UBSan runtimes), link against downloaded LLVM+Z3.
cmake -S "$SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $LSAN_OBJ" \
  -DCMAKE_SHARED_LINKER_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DSVF_ENABLE_ASSERTIONS=ON \
  -DSVF_SANITIZE="" \
  -DBUILD_SHARED_LIBS=ON \
  -DLLVM_DIR="$LLVM_DIR/lib/cmake/llvm"

cmake --build "$BUILD_DIR" -j"$MAYHEM_JOBS" --target saber

SABER="$BUILD_DIR/bin/saber"
[ -x "$SABER" ] || { echo "missing $SABER" >&2; exit 1; }

install -m755 "$SABER" /mayhem/saber
install -m755 "$SABER" /mayhem/saber-standalone

LD_PATH="$LLVM_DIR/lib:$Z3_DIR/bin:$BUILD_DIR/lib"
printf "%s\n" "$LD_PATH" > "$SRC/mayhem/.ld_library_path"

if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath "$LD_PATH" /mayhem/saber /mayhem/saber-standalone
fi

echo "Built /mayhem/saber (LLVM $LLVM_DIR, sanitizers: $SANITIZER_FLAGS)"
