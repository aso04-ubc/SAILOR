#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct Block {
    int index;
    long timestamp;
    char data[256];
    int prev_hash;
    int hash;
    struct Block *next;
} Block;