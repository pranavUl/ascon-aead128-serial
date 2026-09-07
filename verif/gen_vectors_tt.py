#!/usr/bin/env python3
"""KAT-style vectors for the TT wrapper bench: 33x33 (adlen,ptlen) sweep with
00 01 02.. key/nonce/ad/pt patterns (mirrors NIST KAT layout) + 24 random."""
import random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pyascon as oracle
random.seed(7)
vecs = []
for al in range(33):
    for pl in range(33):
        key = bytes(range(16)); nonce = bytes(range(16))
        ad = bytes(i & 0xff for i in range(al)); pt = bytes(i & 0xff for i in range(pl))
        r = oracle.ascon_encrypt(key, nonce, ad, pt, variant='Ascon-AEAD128')
        vecs.append((key, nonce, ad, pt, r[:pl], r[pl:]))
for _ in range(24):
    key = random.randbytes(16); nonce = random.randbytes(16)
    ad = random.randbytes(random.randint(0, 48)); pt = random.randbytes(random.randint(0, 48))
    r = oracle.ascon_encrypt(key, nonce, ad, pt, variant='Ascon-AEAD128')
    vecs.append((key, nonce, ad, pt, r[:len(pt)], r[len(pt):]))
def carr(b, pad):
    b = b.ljust(pad, b'\0'); return '{' + ','.join(f'0x{x:02x}' for x in b) + '}'
out = ['#pragma once', '#include <cstdint>',
       'struct CoreVec { int adlen, ptlen; uint8_t key[16], nonce[16], ad[48], pt[48], ct[48], tag[16]; };',
       f'static const int N_CORE_VECS = {len(vecs)};', 'static const CoreVec CORE_VECS[] = {']
for key, nonce, ad, pt, ct, tag in vecs:
    out.append(f'  {{{len(ad)}, {len(pt)}, {carr(key,16)}, {carr(nonce,16)}, {carr(ad,48)}, {carr(pt,48)}, {carr(ct,48)}, {carr(tag,16)}}},')
out.append('};')
open(os.path.dirname(os.path.abspath(__file__)) + '/vectors_tt.h', 'w').write('\n'.join(out) + '\n')
print(f'wrote {len(vecs)} vectors', file=sys.stderr)
