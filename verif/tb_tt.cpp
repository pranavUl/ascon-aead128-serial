// tb_tt.cpp -- drive the TT wrapper through its 8-bit pin protocol only.
// Host model: registered inputs + rising-edge strobes, so every pulse is held
// for a random 1..3 cycles high then 1..3 low. Polls IN_READY / OUT_VALID.
#include "Vtt_um_pranavUl_ascon_aead128.h"
#include "verilated.h"
#include "vectors_tt.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
typedef Vtt_um_pranavUl_ascon_aead128 DUT;
static uint64_t g_cycles = 0;
static const uint64_t TIMEOUT = 4000000;
static uint32_t rs = 0xC0FFEE01;
static uint32_t rnd() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static void tick(DUT* d) { d->clk = 0; d->eval(); d->clk = 1; d->eval(); d->clk = 0; d->eval(); g_cycles++; }
static void idle(DUT* d, int n) { for (int i = 0; i < n; i++) tick(d); }
// uio bits: [1:0] CMD, [2] STROBE, [3] START, [4] BLOCK_GO ; outputs [5] IN_READY [6] BUSY [7] OUT_VALID
static void pulse(DUT* d, int bit, int cmd, int data) {
    d->ui_in = data; d->uio_in = cmd; idle(d, 1 + (rnd() % 2));
    d->uio_in = cmd | (1 << bit); idle(d, 1 + (rnd() % 3));
    d->uio_in = cmd; idle(d, 1 + (rnd() % 3));
}
static bool wait_bit(DUT* d, int bit, int val) {
    uint64_t t0 = g_cycles;
    while (((d->uio_out >> bit) & 1) != val) { tick(d); if (g_cycles - t0 > TIMEOUT) return false; }
    return true;
}
static bool send_block(DUT* d, const uint8_t* p, int n, bool ad, bool last) {
    if (!wait_bit(d, 5, 1)) return false;                 // IN_READY
    for (int i = 0; i < n; i++) pulse(d, 2, 3, p[i]);     // DATA bytes
    pulse(d, 4, 0, (ad ? 1 : 0) | (last ? 2 : 0));        // BLOCK_GO with flags on ui_in
    return true;
}
static bool read_bytes(DUT* d, uint8_t* out, int n) {
    for (int i = 0; i < n; i++) {
        if (!wait_bit(d, 7, 1)) return false;             // OUT_VALID
        out[i] = d->uo_out;
        pulse(d, 2, 0, 0);                                // CMD=00 + STROBE pops
    }
    return true;
}
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    DUT* d = new DUT;
    d->ui_in = 0; d->uio_in = 0; d->ena = 1; d->rst_n = 0; idle(d, 3); d->rst_n = 1; idle(d, 2);
    int pass = 0, fail = 0, shown = 0;
    for (int v = 0; v < (getenv("NV") ? atoi(getenv("NV")) : N_CORE_VECS); v++) {
        const CoreVec& tv = CORE_VECS[v];
        bool ok = true;
        for (int i = 0; i < 16; i++) pulse(d, 2, 1, tv.key[i]);
        for (int i = 0; i < 16; i++) pulse(d, 2, 2, tv.nonce[i]);
        pulse(d, 3, 0, 0);                                  // START, DECRYPT=0
        for (int off = 0; ok && off < tv.adlen; off += 16) {
            int nb = tv.adlen - off; if (nb > 16) nb = 16;
            ok = send_block(d, tv.ad + off, nb, true, off + nb == tv.adlen);
        }
        uint8_t ct[64]; int got = 0;
        if (ok && tv.ptlen == 0) ok = send_block(d, tv.pt, 0, false, true);
        for (int off = 0; ok && off < tv.ptlen; off += 16) {
            int nb = tv.ptlen - off; if (nb > 16) nb = 16;
            ok = send_block(d, tv.pt + off, nb, false, off + nb == tv.ptlen);
            // read this block's ciphertext before staging the next (host knows lengths)
            if (ok && (rnd() & 1)) { ok = read_bytes(d, ct + got, nb); got += nb; }
        }
        if (ok && got < tv.ptlen) { ok = read_bytes(d, ct + got, tv.ptlen - got); got = tv.ptlen; }
        uint8_t tag[16] = {0};
        if (ok) ok = read_bytes(d, tag, 16);
        if (ok) ok = wait_bit(d, 6, 0);                     // BUSY low
        bool match = ok && memcmp(ct, tv.ct, tv.ptlen) == 0 && memcmp(tag, tv.tag, 16) == 0;
        if (match) pass++; else { fail++; if (shown++ < 5) {
            printf("FAIL vec %d (ad=%d pt=%d)%s\n  got tag:", v, tv.adlen, tv.ptlen, ok ? "" : " TIMEOUT");
            for (int i = 0; i < 16; i++) printf(" %02x", tag[i]); printf("\n  exp tag:");
            for (int i = 0; i < 16; i++) printf(" %02x", tv.tag[i]); printf("\n"); } }
    }
    printf("tt_um_pranavUl_ascon_aead128: %d/%d passed (%llu cycles)\n", pass, pass + fail, (unsigned long long)g_cycles);
    delete d; return fail ? 1 : 0;
}
