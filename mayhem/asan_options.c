/*
 * asan_options.c — bake detect_leaks=0 into the SVF saber binary.
 *
 * WHY: Building with -fsanitize=address enables LeakSanitizer (LSan) by
 * default on Linux. Under Mayhem's ptrace-based coverage collection, LSan
 * tries to ptrace-attach to its own threads to scan for leaks — but a Linux
 * process can have only one tracer at a time. LSan's attach fails with
 * "LeakSanitizer has encountered a fatal error … does not work under ptrace
 * (strace, gdb, etc.)" and the process exits non-zero before any edges are
 * recorded → 0-edge "Run Failed" / has_critical_errors.
 *
 * saber links against large LLVM shared libraries (libLLVM-21.so and
 * friends) that are themselves instrumented with ASan and brought in via
 * shared-library loading. The sanitizer runtime's weak __asan_default_options
 * / __lsan_default_options symbols can be shadowed by a library's own weak
 * copy, causing the user's weak override to lose. Using STRONG symbols
 * (no __attribute__((weak))) guarantees this TU wins at link time regardless
 * of --whole-archive or link order.
 *
 * detect_leaks=0 is supplied in BOTH hooks to cover whichever sanitizer's
 * flag parser initializes first. Full ASan + UBSan memory/UB detection is
 * preserved; only the leak scanner (useless for short fuzzing iterations) is
 * disabled.
 *
 * Same pattern as mayhemheroes/VC4C, mayhemheroes/botan, mayhemheroes/my_basic.
 */

const char *__asan_default_options(void) {
    return "detect_leaks=0";
}

const char *__lsan_default_options(void) {
    return "detect_leaks=0";
}
