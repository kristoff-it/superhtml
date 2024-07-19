#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <limits.h>

/* Main entry point. */

/* To ensure checks are not optimized out it is recommended to disable
   code optimization for the fuzzer harness main() */
#pragma clang optimize off
#pragma GCC            optimize("O0")

void zig_fuzz_test_direct(unsigned char *, ssize_t);
void zig_fuzz_test_astgen(unsigned char *, ssize_t);

__AFL_FUZZ_INIT();

int main(int argc, char **argv) {

  __AFL_INIT();
  unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;

  while (__AFL_LOOP(UINT_MAX)) {
    int len = __AFL_FUZZ_TESTCASE_LEN;
    zig_fuzz_test_astgen(buf, len);
  }

  return 0;
}
