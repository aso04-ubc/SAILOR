#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#define _DEFAULT_SOURCE
#include <unistd.h>
#include <string.h>

#define HW_REGS_BASE ( 0xff200000 )
#define HW_REGS_SPAN ( 0x00200000 )
#define SHA256_OFFSET ( 0x00000000 )

typedef struct {
    const char* name;
    uint32_t input[16];
    uint32_t expected[8];
} test_vector_t;

// Test vectors
test_vector_t tests[] = {
    {
        .name = "Empty message",
        .input = {
            0x80000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000
        },
        .expected = {
            0xe3b0c442, 0x98fc1c14, 0x9afbf4c8, 0x996fb924,
            0x27ae41e4, 0x649b934c, 0xa495991b, 0x7852b855
        }
    },
    {
        .name = "abc",
        .input = {
            0x61626380, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000018
        },
        .expected = {
            0xba7816bf, 0x8f01cfea, 0x41410025, 0x5de30d52,
            0x1d06aa04, 0x75ad0d8a, 0xa8c0cb58, 0xa24a3fa5
        }
    }
};

int run_test(volatile uint32_t *sha256_regs, test_vector_t *test) {
    printf("\n========================================\n");
    printf("Test: %s\n", test->name);
    printf("========================================\n");

    // Clear any previous state
    sha256_regs[24] = 0x0;
    usleep(1000);

    // Write input data
    printf("Writing input...\n");
    for (int i = 0; i < 16; i++) {
        sha256_regs[i] = test->input[i];
    }

    __sync_synchronize();

    // Verify writes
    printf("Verifying writes...\n");
    int write_errors = 0;
    for (int i = 0; i < 16; i++) {
        uint32_t readback = sha256_regs[i];
        if (readback != test->input[i]) {
            printf("  ERROR: Reg[%d] = 0x%08x, expected 0x%08x\n",
                   i, readback, test->input[i]);
            write_errors++;
        }
    }

    if (write_errors > 0) {
        printf("⚠ WRITE ERRORS DETECTED - Bus timing issue!\n");
        return 0;
    }
    printf("✓ All writes verified\n");

    // Start computation
    printf("\nStarting computation...\n");
    sha256_regs[24] = 0x1;
    __sync_synchronize();

    // Poll for completion
    int timeout = 1000000;
    int poll_count = 0;
    while (!(sha256_regs[24] & 0x1) && timeout > 0) {
        usleep(10);
        timeout -= 10;
        poll_count++;
    }

    if (timeout <= 0) {
        printf("✗ TIMEOUT - Computation didn't complete!\n");
        return 0;
    }

    printf("✓ Completed in ~%d us\n", poll_count * 10);

    // Read results
    __sync_synchronize();
    uint32_t result[8];
    for (int i = 0; i < 8; i++) {
        result[i] = sha256_regs[16 + i];
    }

    // Compare results
    printf("\nResults:\n");
    printf("  Address | Got        | Expected   | Match\n");
    printf("  --------|------------|------------|-------\n");

    int matches = 0;
    for (int i = 0; i < 8; i++) {
        char match = (result[i] == test->expected[i]) ? '✓' : '✗';
        printf("  [%2d]    | 0x%08x | 0x%08x | %c\n",
               16+i, result[i], test->expected[i], match);
        if (result[i] == test->expected[i]) matches++;
    }

    printf("\n");
    if (matches == 8) {
        printf("✓✓✓ PASS - All words match! ✓✓✓\n");
        return 1;
    } else {
        printf("✗✗✗ FAIL - %d/%d words wrong ✗✗✗\n", 8-matches, 8);

        // Analyze the error pattern
        printf("\nError Analysis:\n");

        // Check for byte swapping
        int byte_swap_matches = 0;
        for (int i = 0; i < 8; i++) {
            uint32_t swapped = __builtin_bswap32(result[i]);
            if (swapped == test->expected[i]) byte_swap_matches++;
        }
        if (byte_swap_matches == 8) {
            printf("  → All words match if byte-swapped (endianness issue)\n");
        }

        // Check for word order reversal
        int reverse_matches = 0;
        for (int i = 0; i < 8; i++) {
            if (result[i] == test->expected[7-i]) reverse_matches++;
        }
        if (reverse_matches == 8) {
            printf("  → All words match if output order reversed\n");
        }

        // Check if consistently wrong
        printf("  → Wrong hash suggests: reset polarity or core config issue\n");

        return 0;
    }
}

int main() {
    int fd;
    void *virtual_base;
    volatile uint32_t *sha256_regs;

    if ((fd = open("/dev/mem", (O_RDWR | O_SYNC))) == -1) {
        perror("/dev/mem open failed");
        return 1;
    }

    virtual_base = mmap(
        NULL,
        HW_REGS_SPAN,
        (PROT_READ | PROT_WRITE),
        MAP_SHARED,
        fd,
        HW_REGS_BASE
    );

    if (virtual_base == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    sha256_regs = (volatile uint32_t *)(virtual_base + SHA256_OFFSET);

    printf("╔════════════════════════════════════════╗\n");
    printf("║   SHA256 Hardware Diagnostic Test     ║\n");
    printf("╚════════════════════════════════════════╝\n");

    int num_tests = sizeof(tests) / sizeof(tests[0]);
    int passed = 0;

    for (int i = 0; i < num_tests; i++) {
        if (run_test(sha256_regs, &tests[i])) {
            passed++;
        }
        usleep(100000); // 100ms between tests
    }

    printf("\n╔════════════════════════════════════════╗\n");
    printf("║            Final Results               ║\n");
    printf("╚════════════════════════════════════════╝\n");
    printf("Passed: %d/%d tests\n\n", passed, num_tests);

    if (passed == num_tests) {
        printf("🎉 SUCCESS! Hardware is working correctly!\n");
    } else {
        printf("⚠ FAILURE - See error analysis above\n");
        printf("\nNext steps:\n");
        printf("1. Check reset polarity in wrapper (try opposite)\n");
        printf("2. If byte-swapped: Check endianness in core\n");
        printf("3. If reversed: Check output word ordering\n");
        printf("4. Compare with simulation results\n");
    }

    munmap(virtual_base, HW_REGS_SPAN);
    close(fd);
    return (passed == num_tests) ? 0 : 1;
}
