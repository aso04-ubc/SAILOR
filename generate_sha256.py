import struct

def rotate(x, n): return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF # clip the output
def sha256_compress(block_hex, H):
    
    K = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    W = list(struct.unpack(">16I", bytes.fromhex(block_hex))) + [0]*48

    for t in range(16, 64):
        s0 = rotate(W[t-15], 7) ^ rotate(W[t-15], 18) ^ (W[t-15] >> 3)
        s1 = rotate(W[t-2], 17) ^ rotate(W[t-2], 19) ^ (W[t-2] >> 10)
        W[t] = (W[t-16] + s0 + W[t-7] + s1) & 0xFFFFFFFF

    a, b, c, d, e, f, g, h = H

    for t in range(64):
        S1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
        choose = (e & f) ^ ((~e) & g)
        temp1 = (h + S1 + choose + K[t] + W[t]) & 0xFFFFFFFF
        S0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
        majority = (a & b) ^ (a & c) ^ (b & c)
        temp2 = (S0 + majority) & 0xFFFFFFFF

        h = g
        g = f
        f = e
        e = (d + temp1) & 0xFFFFFFFF
        d = c
        c = b
        b = a
        a = (temp1 + temp2) & 0xFFFFFFFF

    return [(x + y) & 0xFFFFFFFF for x, y in zip(H, [a,b,c,d,e,f,g,h])]


import random
with open("examples.txt", "w") as f:

    H_init = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    
    for _ in range(5):

        block_bytes = random.randbytes(64) 
        block_hex = block_bytes.hex()
        
        new_H = sha256_compress(block_hex, H_init)
        
        expected_hex = ''.join(f'{val:08x}' for val in new_H)
        
        f.write(f"{block_hex} {expected_hex}\n")

print("Finished Generation")