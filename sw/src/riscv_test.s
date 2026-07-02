.section .text
.global _start
_start:
    addi x31, x0, 1              # Progress tracker = 1 (START)

    # ── Test 1a: CSRRW — write and read back ────────────────────────────────
    addi  x1, x0, 0x55           # x1 = 0x55 (test pattern)
    csrrw x2, mscratch, x1       # mscratch ← 0x55 ; x2 ← old value (was 0)
    csrrw x3, mscratch, x0       # mscratch ← 0x00 ; x3 ← old value

    # ── Test 1b: CSRRS — set specific bits ──────────────────────────────────
    addi  x4, x0, 0x0F           # x4 = 0x0F (mask: set lower 4 bits)
    csrrw x0, mscratch, x0       # clear mscratch first
    csrrs x5, mscratch, x4       # mscratch |= 0x0F ; x5 ← old (0)
    csrrs x6, mscratch, x0       # read mscratch into x6

    # ── Test 1c: CSRRC — clear specific bits ────────────────────────────────
    addi  x7, x0, 0x05           # x7 = 0x05 (mask: clear bits 0 and 2)
    csrrc x8, mscratch, x7       # mscratch &= ~0x05 ; x8 ← old (0x0F)
    csrrs x9, mscratch, x0       # read mscratch after clear

    # ── Test 1d: CSRRWI — write immediate ───────────────────────────────────
    csrrwi x0, mscratch, 31      # mscratch ← 31 (0x1F) using 5-bit uimm
    csrrs  x10, mscratch, x0     # read it back

    # ── Test 1e: CSRRSI — set bits immediate ────────────────────────────────
    csrrsi x0, mscratch, 0       # uimm=0 → NO WRITE, just read old
    csrrwi x0, mscratch, 0       # clear mscratch
    csrrsi x11, mscratch, 16     # mscratch |= 16 (0x10) ; x11 ← old (0)
    csrrs  x12, mscratch, x0

    # ── Test 1f: CSRRCI — clear bits immediate ──────────────────────────────
    csrrci x0, mscratch, 16      # mscratch &= ~16 → clears bit 4
    csrrs  x13, mscratch, x0

    # ── Test 1g: Read-only CSRs (mhartid, mvendorid, misa) ──────────────────
    csrrs  x14, mhartid, x0      # 0xF14 → always 0 (single hart)
    csrrs  x15, mvendorid, x0    # 0xF11 → always 0 (non-commercial)
    csrrs  x16, misa, x0         # 0x301 → RV32I encoding

    # ── Test 1h: Performance counters ───────────────────────────────────────
    csrrs  x17, mcycle, x0       # read cycle counter (low 32)
    nop                          # burn cycles
    nop
    nop
    csrrs  x18, mcycle, x0       # read again (should be > x17)

    addi  x31, x0, 2             # Progress tracker = 2 (SCENARIO 1 PASSED)
done:
    beq   x0, x0, done           # Infinite loop