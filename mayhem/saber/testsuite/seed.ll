; ModuleID = 'seed'
; Minimal valid LLVM IR seed so Mayhem has a starting testcase saber can
; parse without aborting (saber SIGABRTs on non-IR input). Exercises the
; malloc/free leak-checker path that `saber` analyzes.
define i32 @main() {
entry:
  %p = call i8* @malloc(i64 8)
  call void @free(i8* %p)
  ret i32 0
}
declare i8* @malloc(i64)
declare void @free(i8*)
