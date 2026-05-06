/*
 * mining.c  –  FPGA-Accelerated Blockchain Miner
 * Target: DE1-SoC HPS, SHA256 Avalon peripheral at 0xFF200000
 *
 * Register map (word-addressed via sha256_regs[]):
 *   [0..15]  : 512-bit padded SHA-256 message block (write before starting)
 *   [16..23] : 256-bit winning digest (read after done)
 *   [24]     : control/status
 *                write 1 → start auto-nonce mining
 *                write 0 → reset to IDLE
 *                read  bit[0] → 1 = block mined (difficulty met)
 *
 * Block header layout (55 bytes, packed):
 *   [0..3]   index      (uint32_t)
 *   [4..35]  prev_hash  (32 × uint8_t)
 *   [36..50] data       (15 × uint8_t)
 *   [51..54] nonce      (uint32_t)
 *
 * SHA-256 single-block padding for 55-byte message:
 *   words [0..12] : raw message bytes 0–51
 *   word  [13]    : 0x80_NNNNNN  (0x80 = pad marker, NNNNNN = nonce seed)
 *   word  [14]    : 0x00000000
 *   word  [15]    : 0x000001B8   (55 × 8 = 440 bits)
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <sys/mman.h>
#define _DEFAULT_SOURCE
#include <unistd.h>

/* ── FPGA memory map ──────────────────────────────────────────────────────── */
#define HW_REGS_BASE  (0xFF200000u)
#define HW_REGS_SPAN  (0x00200000u)
#define SHA256_OFFSET (0x00000000u)

/* ── Mining parameters ────────────────────────────────────────────────────── */
#define MAX_BLOCKS      10       /* number of blocks to mine                  */
#define POLL_INTERVAL   50000   /* µs between done-flag polls                 */

/* ── Block header ─────────────────────────────────────────────────────────── */
typedef struct __attribute__((packed)) {
    uint32_t index;          /*  4 B  */
    uint8_t  prev_hash[32];  /* 32 B  */
    uint8_t  data[15];       /* 15 B  */
    uint32_t nonce;          /*  4 B  ← seed / result                        */
} block_header_t;             /* 55 B total                                   */

/* ── Helpers ──────────────────────────────────────────────────────────────── */

static void print_hash(const uint8_t *h)
{
    for (int i = 0; i < 32; i++) printf("%02x", h[i]);
}

/*
 * Read the 8 hash output words (registers 16–23) into a 32-byte byte array.
 * The FPGA stores H0 at reg 16 … H7 at reg 23, each word big-endian.
 */
static void get_hash(volatile uint32_t *regs, uint8_t *out)
{
    for (int i = 0; i < 8; i++) {
        uint32_t w = regs[16 + i];
        out[i*4 + 0] = (w >> 24) & 0xFF;
        out[i*4 + 1] = (w >> 16) & 0xFF;
        out[i*4 + 2] = (w >>  8) & 0xFF;
        out[i*4 + 3] = (w >>  0) & 0xFF;
    }
}

/* ── Core mining function ─────────────────────────────────────────────────── */

/*
 * mine_block() – push a block to the FPGA and wait for the hardware miner to
 * find a nonce that satisfies the difficulty target (top 16 bits == 0x0000).
 *
 * On return:
 *   block->nonce  is updated with the winning value stored in reg[13]
 *   regs[16..23]  hold the corresponding winning digest
 */
void mine_block(volatile uint32_t *sha256_regs, block_header_t *block)
{
    uint32_t padded_block[16] = {0};

    /*
     * Copy the full 55-byte struct into the padded-block buffer.
     * This fills words [0..12] (48 B) plus the first 7 bytes of word 13.
     */
    memcpy(padded_block, block, 55);

    /*
     * Word 13 (bytes 52–55):
     *   Bit 31 (0x80 in MSB)  = SHA-256 '1'-padding marker
     *   Bits 23:0             = lower 24 bits of the caller-supplied nonce
     *                           used as the hardware's starting nonce counter
     */
    padded_block[13] = (block->nonce & 0x00FFFFFFu) | 0x80000000u;

    /* Word 14 – zero padding                                                  */
    padded_block[14] = 0x00000000u;

    /* Word 15 – message bit-length: 55 bytes × 8 = 440 = 0x1B8               */
    padded_block[15] = 0x000001B8u;

    /* Write the padded block into FPGA message registers [0..15]              */
    printf("  Pushing block %u to FPGA... ", block->index);
    fflush(stdout);
    for (int i = 0; i < 16; i++)
        sha256_regs[i] = padded_block[i];
    __sync_synchronize();

    /* Trigger the auto-nonce miner                                            */
    sha256_regs[24] = 0x1u;
    __sync_synchronize();

    /* Poll until the hardware sets the sticky-done flag                       */
    printf("mining");
    fflush(stdout);
    while (!(sha256_regs[24] & 0x1u)) {
        usleep(POLL_INTERVAL);
        printf(".");
        fflush(stdout);
    }
    __sync_synchronize();

    /* Capture winning nonce (word 13 including the 0x80 padding byte)         */
    block->nonce = sha256_regs[13];

    printf(" done!\n");
    printf("  Winning nonce : 0x%08x (%u)\n", block->nonce, block->nonce);
    printf("  Winning hash  : ");
    for (int i = 0; i < 8; i++)
        printf("%08x", sha256_regs[16 + i]);
    printf("\n");
}

/* ── Chain validation ─────────────────────────────────────────────────────── */

/*
 * validate_chain() – structural check only (no re-hashing on hardware).
 * Verifies:
 *   1. block[i].index == i
 *   2. block[i].prev_hash == hashes[i-1]  for i > 0
 *   3. genesis block has all-zero prev_hash
 *
 * Returns 1 if the chain is valid, 0 otherwise.
 */
static int validate_chain(const block_header_t *chain,
                           const uint8_t hashes[][32],
                           int length)
{
    int ok = 1;

    /* Genesis: prev_hash must be all zeros */
    uint8_t zero32[32] = {0};
    if (memcmp(chain[0].prev_hash, zero32, 32) != 0) {
        printf("  [FAIL] Genesis block has non-zero prev_hash\n");
        ok = 0;
    }

    for (int i = 0; i < length; i++) {
        /* Index field */
        if (chain[i].index != (uint32_t)i) {
            printf("  [FAIL] Block %d: index field = %u (expected %d)\n",
                   i, chain[i].index, i);
            ok = 0;
        }
        /* prev_hash linkage */
        if (i > 0 && memcmp(chain[i].prev_hash, hashes[i-1], 32) != 0) {
            printf("  [FAIL] Block %d: prev_hash mismatch (not linked to block %d)\n",
                   i, i-1);
            ok = 0;
        }
    }
    return ok;
}

/* ── Main ─────────────────────────────────────────────────────────────────── */

int main(void)
{
    /* ── Map FPGA lightweight HPS-to-FPGA bridge ── */
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1) { perror("/dev/mem open failed"); return 1; }

    void *vbase = mmap(NULL, HW_REGS_SPAN,
                       PROT_READ | PROT_WRITE, MAP_SHARED,
                       fd, HW_REGS_BASE);
    if (vbase == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return 1;
    }

    volatile uint32_t *sha256_regs =
        (volatile uint32_t *)((uint8_t *)vbase + SHA256_OFFSET);

    /* Ensure the core starts in IDLE */
    sha256_regs[24] = 0x0u;
    usleep(1000);

    /* ── Allocate chain storage ── */
    block_header_t chain[MAX_BLOCKS];
    uint8_t        hashes[MAX_BLOCKS][32];

    /*
     * Block payload strings – exactly 15 bytes each (space-padded).
     * Adjust freely; keep each string ≤ 15 chars.
     */
    const char *payloads[MAX_BLOCKS] = {
        "Genesis Block  ",   /* 15 chars */
        "Block 1        ",
        "Block 2        ",
        "Block 3        ",
        "Block 4        ",
        "Block 5        ",
        "Block 6        ",
        "Block 7        ",
        "Block 8        ",
        "Block 9        "
    };

    /* ── Initialise genesis block ── */
    memset(&chain[0], 0, sizeof(block_header_t));
    chain[0].index = 0;
    memset(chain[0].prev_hash, 0x00, 32);   /* all-zero for genesis           */
    memcpy(chain[0].data, payloads[0], 15);
    chain[0].nonce = 0;

    /* ── Banner ── */
    printf("╔════════════════════════════════════════╗\n");
    printf("║      FPGA-Accelerated Blockchain       ║\n");
    printf("║         DE1-SoC  SHA-256 Miner         ║\n");
    printf("╚════════════════════════════════════════╝\n");
    printf("Difficulty : top 16 bits of hash = 0x0000\n");
    printf("Blocks     : %d\n\n", MAX_BLOCKS);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* ── Mining loop ── */
    for (int i = 0; i < MAX_BLOCKS; i++) {
        printf("┌── Block #%d ─────────────────────────────\n", i);
        printf("│  Data      : \"%.15s\"\n", (char *)chain[i].data);
        printf("│  Prev hash : ");
        print_hash(chain[i].prev_hash);
        printf("\n│\n");

        mine_block(sha256_regs, &chain[i]);
        get_hash(sha256_regs, hashes[i]);

        printf("│  Hash      : ");
        print_hash(hashes[i]);
        printf("\n└─────────────────────────────────────────\n\n");

        /* Link the next block */
        if (i + 1 < MAX_BLOCKS) {
            memset(&chain[i+1], 0, sizeof(block_header_t));
            chain[i+1].index = (uint32_t)(i + 1);
            memcpy(chain[i+1].prev_hash, hashes[i], 32);
            memcpy(chain[i+1].data, payloads[i+1], 15);
            chain[i+1].nonce = 0;   /* FPGA seeds from word 13, starts at 0   */
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (double)(t1.tv_sec  - t0.tv_sec) +
                     (double)(t1.tv_nsec - t0.tv_nsec) * 1e-9;

    /* ── Chain summary table ── */
    printf("╔════════════════════════════════════════╗\n");
    printf("║            Chain Summary               ║\n");
    printf("╚════════════════════════════════════════╝\n");
    printf("%-5s  %-15s  %-12s  %s\n",
           "Blk", "Data", "Nonce", "Hash (first 16 B)...");
    printf("─────  ───────────────  ────────────  ─────────────────────────────────\n");
    for (int i = 0; i < MAX_BLOCKS; i++) {
        printf("[%3u]  %-15.15s  %12u  ",
               chain[i].index,
               (char *)chain[i].data,
               chain[i].nonce);
        for (int j = 0; j < 16; j++) printf("%02x", hashes[i][j]);
        printf("...\n");
    }

    /* ── Validate ── */
    printf("\nValidating chain integrity ... ");
    fflush(stdout);
    if (validate_chain(chain, hashes, MAX_BLOCKS))
        printf("✓  VALID\n");
    else
        printf("✗  INVALID (see errors above)\n");

    printf("\nTotal time : %.2f s  (avg %.2f s / block)\n\n",
           elapsed, elapsed / MAX_BLOCKS);

    /* ── Cleanup ── */
    munmap(vbase, HW_REGS_SPAN);
    close(fd);
    return 0;
}