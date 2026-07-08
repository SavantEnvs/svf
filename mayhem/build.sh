#!/usr/bin/env bash
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# UBSan only — no ASan. Mayhem's coverage collection executes the target under
# qemu-user, and ASan's shadow-memory mapping segfaults there (SIGSEGV on every
# input, including valid seeds → "crashes on every test case" Run Failed).
# UBSan has no shadow memory and runs fine under qemu.
# Unconditional assignment: the org base image sets ENV SANITIZER_FLAGS=address,undefined,
# so a parameter-default (:=) would never take effect.
SANITIZER_FLAGS="-fsanitize=undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS

cd "$SRC"

MajorLLVMVer=$(grep -E "^MajorLLVMVer=" build.sh | cut -d= -f2)
LLVMVer="${MajorLLVMVer}.1.0"
LLVMHome="llvm-${LLVMVer}.obj"
Z3Home="z3.obj"
UbuntuLLVM_RTTI="https://github.com/bjjwwang/SVF-LLVM/releases/download/${LLVMVer}/llvm-${LLVMVer}-ubuntu22-rtti-x86-64.tar.gz"
UbuntuZ3="https://github.com/Z3Prover/z3/releases/download/z3-4.8.8/z3-4.8.8-x64-ubuntu-16.04.zip"

fetch() {
  local url="$1" out="$2"
  [ -f "$out" ] && return 0
  curl -fsSL "$url" -o "$out"
}

if [ ! -d "$LLVMHome" ]; then
  echo "Downloading LLVM ${LLVMVer} (RTTI)..."
  fetch "$UbuntuLLVM_RTTI" llvm.tar.xz
  mkdir -p "$LLVMHome"
  tar -xf llvm.tar.xz -C "$LLVMHome" --strip-components 1
  rm -f llvm.tar.xz
fi

if [ ! -d "$Z3Home" ]; then
  echo "Downloading Z3..."
  fetch "$UbuntuZ3" z3.zip
  unzip -q z3.zip
  rm -rf "$Z3Home"
  mv z3-* "$Z3Home"
  rm -f z3.zip
fi

export LLVM_DIR="$SRC/$LLVMHome"
export Z3_DIR="$SRC/$Z3Home"
export PATH="$Z3_DIR/bin:$PATH"

BUILD_DIR="$SRC/Release-build"
rm -rf "$BUILD_DIR"

# Compile asan_options.c with STRONG symbols so detect_leaks=0 overrides the ASan/LSan
# runtime's weak defaults even when large LLVM shared libs are linked.  LSan fatal-errors
# under Mayhem's ptrace-based coverage collector → 0-edge has_critical_errors if not disabled.
ASAN_OBJ="/tmp/svf_asan.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/asan_options.c" -o "$ASAN_OBJ"

# Build with the org-base clang (has ASan/UBSan runtimes), link against downloaded LLVM+Z3.
cmake -S "$SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $ASAN_OBJ" \
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

echo "Built /mayhem/saber (LLVM ${LLVMVer}, sanitizers: $SANITIZER_FLAGS)"
