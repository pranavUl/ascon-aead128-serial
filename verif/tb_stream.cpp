// tb_stream.cpp -- full Ascon-AEAD128 KATs through the streaming lap pins.
// The host (this bench) does everything the buffered core did in hardware:
// padding, block sequencing, key/nonce column scheduling, domain separation.
#include "Vtt_um_pranavUl_ascon_aead128.h"
#include "verilated.h"
#include "vectors_tt.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <vector>
typedef Vtt_um_pranavUl_ascon_aead128 DUT;

static uint64_t g_cycles = 0;
static void tick(DUT* d) { d->clk = 0; d->eval(); d->clk = 1; d->eval(); d->clk = 0; d->eval(); g_cycles++; }

static const uint64_t IV64 = 0x00001000808C0001ULL;
static uint64_t le64(const uint8_t* b) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = (v << 8) | b[i]; return v; }

static bool wait_ready(DUT* d, int limit = 4000) {
    for (int i = 0; i < limit; i++) { d->eval(); if (d->uio_out & 0x80) return true; tick(d); }
    return false;
}

// Run one 64-cycle lap. colfn bit-packs the 5-bit column for cycle k.
// cap != nullptr: capture COL_OUT each cycle into cap[k].
struct Lap { uint64_t c0, c1, c2, c3, c4; };   // per-word 64-bit column planes
static bool lap(DUT* d, const Lap& L, bool xorm, bool perm_after, bool p12, uint8_t* cap) {
    if (!wait_ready(d)) return false;
    d->uio_in = xorm ? 1 : 0;
    d->ui_in = (1 << 5) | (perm_after ? (1 << 6) : 0) | (p12 ? (1 << 7) : 0);
    tick(d);                                   // lap_begin fires on this edge
    d->ui_in &= (uint8_t)~(1 << 5);            // drop GO
    for (int k = 0; k < 64; k++) {
        uint8_t col = (uint8_t)((((L.c0 >> k) & 1)) | (((L.c1 >> k) & 1) << 1) |
                                (((L.c2 >> k) & 1) << 2) | (((L.c3 >> k) & 1) << 3) |
                                (((L.c4 >> k) & 1) << 4));
        d->ui_in = (d->ui_in & 0xE0) | col;
        d->eval();
        if (!((d->uo_out >> 5) & 1)) return false;   // LAP_ACTIVE must be high
        if (cap) cap[k] = d->uo_out & 0x1F;
        tick(d);
    }
    return true;
}

// split data into padded 16-byte blocks per the parallel-core rules
static void blocks(const uint8_t* data, int n, std::vector<std::pair<uint64_t,uint64_t>>& out, bool with_empty) {
    int i = 0;
    while (n - i >= 16) { out.push_back({le64(data + i), le64(data + i + 8)}); i += 16; }
    int rem = n - i;
    if (rem > 0 || (n == 0 && with_empty) || (n > 0 && rem == 0)) {
        uint8_t buf[16]; memset(buf, 0, 16);
        memcpy(buf, data + i, rem);
        buf[rem] = 0x01;
        out.push_back({le64(buf), le64(buf + 8)});
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    DUT* d = new DUT;
    d->ui_in = 0; d->uio_in = 0; d->ena = 1; d->rst_n = 0; tick(d); tick(d); tick(d); d->rst_n = 1; tick(d);
    int pass = 0, fail = 0, shown = 0;
    int NV = getenv("NV") ? atoi(getenv("NV")) : N_CORE_VECS;

    for (int v = 0; v < NV; v++) {
        const CoreVec& tv = CORE_VECS[v];
        uint64_t K0 = le64(tv.key), K1 = le64(tv.key + 8);
        uint64_t N0 = le64(tv.nonce), N1 = le64(tv.nonce + 8);
        bool ok = true;
        uint8_t cap[64];

        // 1) init load lap: {N1,N0,K1,K0,IV}, then p12
        ok = ok && lap(d, {IV64, K0, K1, N0, N1}, false, true, true, nullptr);
        // 2) init key XOR: x4^=K1, x3^=K0
        ok = ok && lap(d, {0, 0, 0, K0, K1}, true, false, false, nullptr);
        // 3) AD blocks (none if adlen==0), p8 after each
        std::vector<std::pair<uint64_t,uint64_t>> ab;
        blocks(tv.ad, tv.adlen, ab, false);
        for (auto& b : ab)
            ok = ok && lap(d, {b.first, b.second, 0, 0, 0}, true, true, false, nullptr);
        // 4) domain separation: x4 ^= 1<<63
        ok = ok && lap(d, {0, 0, 0, 0, 1ULL << 63}, true, false, false, nullptr);
        // 5) PT blocks: p8 after each except the last; capture ct
        std::vector<std::pair<uint64_t,uint64_t>> pb;
        blocks(tv.pt, tv.ptlen, pb, true);
        uint8_t ct[64]; int ct_len = 0;
        for (size_t i = 0; ok && i < pb.size(); i++) {
            bool last = (i == pb.size() - 1);
            ok = lap(d, {pb[i].first, pb[i].second, 0, 0, 0}, true, !last, false, cap);
            if (!ok) break;
            uint64_t c0 = 0, c1 = 0;
            for (int k = 0; k < 64; k++) { c0 |= (uint64_t)(cap[k] & 1) << k; c1 |= (uint64_t)((cap[k] >> 1) & 1) << k; }
            int nb = tv.ptlen - (int)i * 16; if (nb > 16) nb = 16; if (nb < 0) nb = 0;
            uint8_t blk[16];
            for (int j = 0; j < 8; j++) { blk[j] = (uint8_t)(c0 >> (8 * j)); blk[8 + j] = (uint8_t)(c1 >> (8 * j)); }
            memcpy(ct + ct_len, blk, nb); ct_len += nb;
        }
        // 6) final key XOR: x3^=K1, x2^=K0, then p12
        ok = ok && lap(d, {0, 0, K0, K1, 0}, true, true, true, nullptr);
        // 7) tag lap: x4^=K1, x3^=K0; tag on COL_OUT[4:3]
        uint8_t tag[16] = {0};
        ok = ok && lap(d, {0, 0, 0, K0, K1}, true, false, false, cap);
        if (ok) {
            uint64_t t0 = 0, t1 = 0;
            for (int k = 0; k < 64; k++) { t0 |= (uint64_t)((cap[k] >> 3) & 1) << k; t1 |= (uint64_t)((cap[k] >> 4) & 1) << k; }
            for (int j = 0; j < 8; j++) { tag[j] = (uint8_t)(t0 >> (8 * j)); tag[8 + j] = (uint8_t)(t1 >> (8 * j)); }
        }
        bool match = ok && ct_len == tv.ptlen && memcmp(ct, tv.ct, tv.ptlen) == 0 && memcmp(tag, tv.tag, 16) == 0;
        if (match) pass++;
        else { fail++; if (shown++ < 5) {
            printf("FAIL vec %d (ad=%d pt=%d)%s ct_len=%d\n  got tag:", v, tv.adlen, tv.ptlen, ok ? "" : " PROTO", ct_len);
            for (int i = 0; i < 16; i++) printf(" %02x", tag[i]); printf("\n  exp tag:");
            for (int i = 0; i < 16; i++) printf(" %02x", tv.tag[i]); printf("\n"); } }
    }
    printf("tt_um streaming: %d/%d passed (%llu cycles)\n", pass, pass + fail, (unsigned long long)g_cycles);
    delete d;
    return fail ? 1 : 0;
}