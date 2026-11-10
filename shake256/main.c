#include <stdio.h>

extern int test_interleave(void);

int main(void) {
    int rc = test_interleave();
    if (rc == 0) printf("interleave/deinterleave: OK\n");
    else         printf("FAILED at test %d\n", rc);
    return rc;
}