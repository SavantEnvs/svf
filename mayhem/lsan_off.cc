// Build-time LeakSanitizer opt-out: leak reports are not the bug class this
// target is fuzzed for. ASan memory-error checks and UBSan stay active.
extern "C" int __lsan_is_turned_off() { return 1; }
