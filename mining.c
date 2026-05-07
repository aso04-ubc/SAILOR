#define _POSIX_C_SOURCE 200112L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

/* ── FPGA memory map ──────────────────────────────────────────────────────── */
#define HW_REGS_BASE  (0xFF200000u)
#define HW_REGS_SPAN  (0x00200000u)
#define SHA256_OFFSET (0x00000000u)
#define SHA256_DEBUG_REG  (26)

/* ── Mining parameters ────────────────────────────────────────────────────── */
#define MAX_BLOCKS      10
#define POLL_INTERVAL   1000

/* ── Block header ─────────────────────────────────────────────────────────── */
typedef struct __attribute__((packed)) {
    uint32_t index;        
    uint8_t  prev_hash[32];
    uint8_t  data[15];     
    uint32_t nonce;        
} block_header_t;          

/* ── Helpers ──────────────────────────────────────────────────────────────── */

static void print_hash(const uint8_t *h)
{
    for (int i = 0; i < 32; i++) printf("%02x", h[i]);
}

static void print_debug_reg(uint32_t dbg)
{
    static const char *state_names[] = { "IDLE", "WARMUP", "RUNNING", "DONE" };
    unsigned state      = (dbg >> 28) & 0x3;
    unsigned count      = (dbg >> 21) & 0x7F;
    unsigned finish_r   = (dbg >> 20) & 0x1;
    uint16_t top16      = (dbg >> 4) & 0xFFFF;

    printf("[DEBUG] state=%s count=%02u finish_r=%u top16_hash=0x%04x\n",
           state_names[state], count, finish_r, top16);
}

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
void mine_block(volatile uint32_t *sha256_regs, block_header_t *block)
{
    uint32_t padded_block[16] = {0};
    memcpy(padded_block, block, 55);
    padded_block[13] = (block->nonce & 0x00FFFFFFu) | 0x80000000u;
    padded_block[14] = 0x00000000u;
    padded_block[15] = 0x000001B8u;
    sha256_regs[24] = 0x0u;
    __sync_synchronize();

    printf("  After reset to IDLE: ");
    print_debug_reg(sha256_regs[SHA256_DEBUG_REG]);

    printf("  Pushing block %u to FPGA... ", block->index);
    fflush(stdout);
    for (int i = 0; i < 16; i++)
        sha256_regs[i] = padded_block[i];
    __sync_synchronize();

    printf("  After block write: ");
    print_debug_reg(sha256_regs[SHA256_DEBUG_REG]);

    sha256_regs[24] = 0x1u;
    __sync_synchronize();

    printf("  After start command: ");
    print_debug_reg(sha256_regs[SHA256_DEBUG_REG]);

    printf("mining");
    fflush(stdout);
    int poll_count = 0;
    while (!(sha256_regs[24] & 0x1u)) {
        usleep(POLL_INTERVAL);
        printf(".");
        fflush(stdout);

        if (++poll_count % 50 == 0) {
            printf("\n  [POLL %d] ", poll_count);
            print_debug_reg(sha256_regs[SHA256_DEBUG_REG]);
        }
    }
    __sync_synchronize();

    printf(" done!\n  At finish: ");
    print_debug_reg(sha256_regs[SHA256_DEBUG_REG]);
    printf("  At finish: raw reg[24] = 0x%08x\n", sha256_regs[24]);

    block->nonce = sha256_regs[13] & 0x00FFFFFFu;

    printf(" done!\n");
    printf("  Winning nonce : 0x%06x (%u)\n", block->nonce, block->nonce);
    printf("  Winning hash  : ");
    for (int i = 0; i < 8; i++)
        printf("%08x", sha256_regs[16 + i]);
    printf("\n");
}

/* ── Chain validation ─────────────────────────────────────────────────────── */
static int validate_chain(const block_header_t *chain,
                           uint8_t hashes[][32],
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

    sha256_regs[24] = 0x0u;
    usleep(1000);


    block_header_t chain[MAX_BLOCKS];
    uint8_t        hashes[MAX_BLOCKS][32];

    const char *payloads[MAX_BLOCKS] = {
        "Genesis Block  ",
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


    memset(&chain[0], 0, sizeof(block_header_t));
    chain[0].index = 0;
    memset(chain[0].prev_hash, 0x00, 32);
    memcpy(chain[0].data, payloads[0], 15);
    chain[0].nonce = 0;

    /* ── Banner ── */
    printf("╔════════════════════════════════════════╗\n");
    printf("║      FPGA-Accelerated Blockchain       ║\n");
    printf("║    DE1-SoC  SHA-256 Pipelined Miner    ║\n");
    printf("╚════════════════════════════════════════╝\n");
    printf("Difficulty : top 16 bits of hash = 0x0000\n");
    printf("Throughput : 1 hash/cycle  (~1.3 ms per block @ 50 MHz)\n");
    printf("Blocks     : %d\n\n", MAX_BLOCKS);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

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

        if (i + 1 < MAX_BLOCKS) {
            memset(&chain[i+1], 0, sizeof(block_header_t));
            chain[i+1].index = (uint32_t)(i + 1);
            memcpy(chain[i+1].prev_hash, hashes[i], 32);
            memcpy(chain[i+1].data, payloads[i+1], 15);
            chain[i+1].nonce = 0;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (double)(t1.tv_sec  - t0.tv_sec) +
                     (double)(t1.tv_nsec - t0.tv_nsec) * 1e-9;

    /* ── Chain summary table ── */
    printf("╔════════════════════════════════════════╗\n");
    printf("║            Chain Summary               ║\n");
    printf("╚════════════════════════════════════════╝\n");
    printf("%-5s  %-15s  %-10s  %s\n",
           "Blk", "Data", "Nonce", "Hash (first 16 B)...");
    printf("─────  ───────────────  ──────────  ─────────────────────────────────\n");
    for (int i = 0; i < MAX_BLOCKS; i++) {
        printf("[%3u]  %-15.15s  %10u  ",
               chain[i].index,
               (char *)chain[i].data,
               chain[i].nonce);
        for (int j = 0; j < 16; j++) printf("%02x", hashes[i][j]);
        printf("...\n");
    }

    printf("\nValidating chain integrity ... ");
    fflush(stdout);
    if (validate_chain(chain, hashes, MAX_BLOCKS))
        printf("✓  VALID\n");
    else
        printf("✗  INVALID (see errors above)\n");

    printf("\nTotal time : %.2f s  (avg %.2f s / block)\n\n",
           elapsed, elapsed / MAX_BLOCKS);

    munmap(vbase, HW_REGS_SPAN);
    close(fd);
    return 0;
}