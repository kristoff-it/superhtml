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

void zig_fuzz_test(unsigned char *, ssize_t);

int main(int argc, char **argv) {

  ssize_t len;                              
  unsigned char buf[4096]; 
  
  __AFL_INIT();

  while (__AFL_LOOP(UINT_MAX)) {
    len = read(0, buf, 4096);
    zig_fuzz_test(buf, len);
  }

  return 0;
}
