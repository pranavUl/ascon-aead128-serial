# SPDX-License-Identifier: Apache-2.0
# cocotb test for tt_um_pranavUl_ascon_aead128: drives the byte-wide host
# protocol and checks ciphertext + tag against Ascon-AEAD128 known answers
# (expected values generated offline with pyascon, NIST SP 800-232 variant).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

CMD_READ, CMD_KEY, CMD_NONCE, CMD_DATA = 0, 1, 2, 3
STROBE, START, BLOCK_GO = 1 << 2, 1 << 3, 1 << 4
IN_READY, BUSY, OUT_VALID = 5, 6, 7

# (adlen, ptlen, ciphertext_hex, tag_hex); key = nonce = 00 01 .. 0f,
# ad = 00 01 .. (adlen-1), pt = 00 01 .. (ptlen-1) -- NIST KAT pattern
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


async def pulse(dut, bit, cmd, data=0):
    """Rising edge on a control bit with CMD/data held (inputs are registered)."""
    dut.ui_in.value = data
    dut.uio_in.value = cmd
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = cmd | bit
    await ClockCycles(dut.clk, 2)
    dut.uio_in.value = cmd
    await ClockCycles(dut.clk, 2)


async def wait_bit(dut, bit, val, limit=20000):
    for _ in range(limit):
        if (int(dut.uio_out.value) >> bit) & 1 == val:
            return
        await ClockCycles(dut.clk, 1)
    raise AssertionError(f"timeout waiting for uio[{bit}] == {val}")


async def send_block(dut, data, is_ad, last):
    await wait_bit(dut, IN_READY, 1)
    for b in data:
        await pulse(dut, STROBE, CMD_DATA, b)
    await pulse(dut, BLOCK_GO, CMD_READ, (1 if is_ad else 0) | (2 if last else 0))


async def read_bytes(dut, n):
    out = bytearray()
    for _ in range(n):
        await wait_bit(dut, OUT_VALID, 1)
        out.append(int(dut.uo_out.value))
        await pulse(dut, STROBE, CMD_READ)
    return bytes(out)


async def encrypt(dut, key, nonce, ad, pt):
    for b in key:
        await pulse(dut, STROBE, CMD_KEY, b)
    for b in nonce:
        await pulse(dut, STROBE, CMD_NONCE, b)
    await pulse(dut, START, CMD_READ, 0)          # ui_in[0] = DECRYPT = 0
    for off in range(0, len(ad), 16):
        blk = ad[off:off + 16]
        await send_block(dut, blk, True, off + len(blk) == len(ad))
    if len(pt) == 0:
        await send_block(dut, b"", False, True)
    for off in range(0, len(pt), 16):
        blk = pt[off:off + 16]
        await send_block(dut, blk, False, off + len(blk) == len(pt))
    ct = await read_bytes(dut, len(pt))
    tag = await read_bytes(dut, 16)
    await wait_bit(dut, BUSY, 0)
    return ct, tag


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

    assert int(dut.uio_oe.value) == 0xE0, "uio_oe must be 1110_0000"

    key = bytes(range(16))
    nonce = bytes(range(16))
    for adlen, ptlen, ct_hex, tag_hex in KATS:
        ad = bytes(i & 0xFF for i in range(adlen))
        pt = bytes(i & 0xFF for i in range(ptlen))
        ct, tag = await encrypt(dut, key, nonce, ad, pt)
        dut._log.info(f"adlen={adlen} ptlen={ptlen} tag={tag.hex()}")
        assert ct.hex() == ct_hex, f"ciphertext mismatch adlen={adlen} ptlen={ptlen}"
        assert tag.hex() == tag_hex, f"tag mismatch adlen={adlen} ptlen={ptlen}"