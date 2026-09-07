# SPDX-License-Identifier: Apache-2.0
# cocotb test: full Ascon-AEAD128 known-answer tests driven through the
# streaming lap interface. The host (this test) performs padding, block
# sequencing and key/nonce column scheduling; the chip performs all state
# processing. Expected values generated offline with pyascon (SP 800-232).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, NextTimeStep, Timer

IV64 = 0x00001000808C0001
LAP_GO, PERM_AFTER, PERM_12 = 1 << 5, 1 << 6, 1 << 7

KATS = [
    (0, 0, "", "4427d64b8e1e1451fc445960f0839bb0"),
    (0, 1, "e7", "9f58f1f541fc51b5d438f8e1dd03f147"),
    (1, 0, "", "103ab79d913a0321287715a979bb8585"),
    (16, 16, "6a28215e4a6023fae42095318b187f99", "e0c479771a09b5d29afd05825b013d0d"),
    (15, 15, "b03e607317a251b08b30f744b71965", "e2cd4bee393f2de0d8cd8b8b4827e6e9"),
    (17, 17, "9813b7013089db863a742a4c13f1408e97", "81d46986cbc03b3e6a335581eb9da954"),
    (32, 32, "4c086d27a3b51a2333cfc7f22172a9bcad88b8d4d77e50622d788345fa7bee44", "68915d3f9422289f2349d6a3b4160397"),
    (5, 40, "1f820273c65246b76d4ff8d1add72d5cc1703338b98ce4b34b5af9ce46120201bab2ef3cfb06ca33", "da6f8eefef6212cebc840a2186808900"),
]

le64 = lambda b: int.from_bytes(b, "little")


async def wait_ready(dut, limit=4000):
    """Settle mid-cycle (falling edge) and return in a writable phase with
    READY high; writes made now are seen by the next rising edge."""
    for _ in range(limit):
        await FallingEdge(dut.clk)
        await ReadOnly()
        ready = (int(dut.uio_out.value) >> 7) & 1
        await Timer(1, units="ns")   # into the cycle interior: writable, before the next rising edge
        if ready:
            return
    raise AssertionError("timeout waiting for READY")


async def lap(dut, planes, xor_mode, perm_after, perm12, capture=False):
    """planes = (c0..c4) 64-bit column planes; returns 64 captured columns."""
    await wait_ready(dut)
    dut.uio_in.value = 1 if xor_mode else 0
    dut.ui_in.value = LAP_GO | (PERM_AFTER if perm_after else 0) | (PERM_12 if perm12 else 0)
    cap = []
    for k in range(64):
        await FallingEdge(dut.clk)      # lap cycle k, mid-cycle
        col = 0
        for w in range(5):
            col |= ((planes[w] >> k) & 1) << w
        dut.ui_in.value = col           # GO dropped from cycle 0 on
        await ReadOnly()                # comb settled with this column
        assert (int(dut.uo_out.value) >> 5) & 1, "LAP_ACTIVE dropped mid-lap"
        if capture:
            cap.append(int(dut.uo_out.value) & 0x1F)
        await NextTimeStep()
    return cap


def blocks(data, with_empty):
    out, i, n = [], 0, len(data)
    while n - i >= 16:
        out.append((le64(data[i:i + 8]), le64(data[i + 8:i + 16])))
        i += 16
    rem = n - i
    if rem > 0 or (n == 0 and with_empty) or (n > 0 and rem == 0):
        buf = bytearray(16)
        buf[:rem] = data[i:]
        buf[rem] = 0x01
        out.append((le64(bytes(buf[:8])), le64(bytes(buf[8:]))))
    return out


def words_to_bytes(w0, w1):
    return w0.to_bytes(8, "little") + w1.to_bytes(8, "little")


async def encrypt(dut, key, nonce, ad, pt):
    K0, K1 = le64(key[:8]), le64(key[8:])
    N0, N1 = le64(nonce[:8]), le64(nonce[8:])
    await lap(dut, (IV64, K0, K1, N0, N1), False, True, True)
    await lap(dut, (0, 0, 0, K0, K1), True, False, False)
    for b0, b1 in blocks(ad, False):
        await lap(dut, (b0, b1, 0, 0, 0), True, True, False)
    await lap(dut, (0, 0, 0, 0, 1 << 63), True, False, False)
    pb = blocks(pt, True)
    ct = b""
    for i, (b0, b1) in enumerate(pb):
        last = i == len(pb) - 1
        cap = await lap(dut, (b0, b1, 0, 0, 0), True, not last, False, capture=True)
        c0 = sum(((cap[k] >> 0) & 1) << k for k in range(64))
        c1 = sum(((cap[k] >> 1) & 1) << k for k in range(64))
        nb = min(16, max(0, len(pt) - 16 * i))
        ct += words_to_bytes(c0, c1)[:nb]
    await lap(dut, (0, 0, K0, K1, 0), True, True, True)
    cap = await lap(dut, (0, 0, 0, K0, K1), True, False, False, capture=True)
    t0 = sum(((cap[k] >> 3) & 1) << k for k in range(64))
    t1 = sum(((cap[k] >> 4) & 1) << k for k in range(64))
    return ct, words_to_bytes(t0, t1)


@cocotb.test()
async def test_ascon_kats(dut):
    dut._log.info("Start")
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    assert int(dut.uio_oe.value) == 0x80, "uio_oe must be 1000_0000"

    key = bytes(range(16))
    nonce = bytes(range(16))
    for adlen, ptlen, ct_hex, tag_hex in KATS:
        ad = bytes(i & 0xFF for i in range(adlen))
        pt = bytes(i & 0xFF for i in range(ptlen))
        ct, tag = await encrypt(dut, key, nonce, ad, pt)
        dut._log.info(f"adlen={adlen} ptlen={ptlen} tag={tag.hex()}")
        assert ct.hex() == ct_hex, f"ct mismatch adlen={adlen} ptlen={ptlen}"
        assert tag.hex() == tag_hex, f"tag mismatch adlen={adlen} ptlen={ptlen}"