<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Ascon-AEAD128 authenticated encryption (NIST SP 800-232) with a bit-serial datapath. The 320-bit state lives in five 64-bit recirculating shift registers, processed one bit-column per cycle through a single shared 5-bit S-box. A permutation round takes two 64-cycle laps (substitution, then linear diffusion), so p8 = 1024 cycles and p12 = 1536. All other protocol steps — key XORs, block absorption, domain separation, padding, tag generation — reuse the same shift path as 64-cycle XOR laps.

The host loads key, nonce, and data over a byte-wide command interface (CMD selects the target, STROBE clocks a byte in, byte 0 first, little-endian within each word). Ciphertext and the 16-byte tag stream out one byte per read. Encrypt/tag-generation only.

## How to test

`cd test && make` runs 8 known-answer tests through the pin protocol; expected values come from the pyascon reference implementation. A 1113-vector KAT sweep for the same design is in `verif/`.

On hardware: drive the pins from any MCU — 16 key bytes, 16 nonce bytes, pulse START, then per block stage up to 16 data bytes and pulse BLOCK_GO (flags on DATA_IN: bit 0 = AD block, bit 1 = last). Read a byte whenever OUT_VALID is high; ciphertext bytes come first, then the tag.

## External hardware

None.
