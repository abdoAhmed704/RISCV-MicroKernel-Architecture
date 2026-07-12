/*
 * start.s — Bare-metal boot entry for QEMU RISC-V 'virt' machine (RV32IMA_Zicsr)
 *
 * QEMU boots this code at physical address 0x80000000.
 * Only hart 0 runs the kernel; all other harts park at wfi.
 *
 * Responsibilities:
 *   1. Halt secondary harts
 *   2. Disable all interrupts and delegate nothing
 *   3. Set up a 128 KiB kernel stack
 *   4. Zero the .bss section
 *   5. Call kernel_main()
 *   6. Provide the M-mode trap vector (m_trap_handler)
 *   7. Provide the S-mode trap vector (s_trap_handler)
 */

    .section .text.start
    .global  _start

_start:
    /* ── Hart filtering: only hart 0 proceeds ─────────────────── */
    csrr    t0, mhartid
    bnez    t0, _halt

    /* ── Disable all M-mode interrupts ───────────────────────── */
    csrw    mstatus, zero
    csrw    mie,     zero

    /* ── Stack pointer: top of a 128 KiB stack at 0x80020000 ─── */
    lui     sp, 0x80020       /* sp = 0x80020000                  */

    /* ── Zero .bss ───────────────────────────────────────────── */
    la      t0, _bss_start
    la      t1, _bss_end
    beq     t0, t1, _bss_done
_bss_loop:
    sw      zero, 0(t0)
    addi    t0,   t0, 4
    blt     t0,   t1, _bss_loop
_bss_done:

    /* ── Install M-mode trap vector (direct mode) ─────────────── */
    la      t0, m_trap_handler
    csrw    mtvec, t0

    /* ── Install S-mode trap vector ─────────────────────────── */
    la      t0, s_trap_handler
    csrw    stvec, t0

    /* ── Call kernel main (never returns under normal operation) ─ */
    call    kernel_main

_halt:
    wfi
    j       _halt


/* ─────────────────────────────────────────────────────────────────
 * M-MODE TRAP HANDLER
 * Handles:
 *   • ECALL from M-mode (cause 11) — dispatches to syscall table
 *   • All other exceptions         — records occurrence and returns
 * ───────────────────────────────────────────────────────────────── */
    .section .text
    .global  m_trap_handler
    .align   4
m_trap_handler:
    /* Save caller-saved registers we will clobber */
    addi    sp, sp, -40
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a7, 36(sp)

    csrr    a0, mcause
    li      t0, 11              /* ECALL from M-mode */
    beq     a0, t0, _m_ecall

    /* ── Generic exception: skip trapping instruction and return ─ */
    csrr    a0, mepc
    lhu     t1, 0(a0)
    andi    t1, t1, 3
    li      t2, 3
    beq     t1, t2, _m_32bit
    addi    a0, a0, 2           /* Compressed instruction (16-bit) */
    j       _m_set_epc
_m_32bit:
    addi    a0, a0, 4           /* Standard instruction (32-bit)   */
_m_set_epc:
    csrw    mepc, a0

    /* Record trap */
    la      t0, m_trap_occurred
    li      t1, 1
    sw      t1, 0(t0)
    j       _m_ret

    /* ── ECALL handler: dispatch via syscall_dispatch() ────────── */
_m_ecall:
    lw      a7, 36(sp)          /* Restore a7 (syscall number)    */
    lw      a0, 16(sp)          /* Restore a0 (first argument)    */
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    call    syscall_dispatch    /* C function: (a7, a0, a1, a2)   */
    sw      a0, 16(sp)          /* Store return value back        */

    /* Advance mepc past ecall instruction */
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

_m_ret:
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a7, 36(sp)
    addi    sp, sp, 40
    mret


/* ─────────────────────────────────────────────────────────────────
 * S-MODE TRAP HANDLER
 * ───────────────────────────────────────────────────────────────── */
    .global  s_trap_handler
    .align   4
s_trap_handler:
    addi    sp, sp, -8
    sw      t0, 0(sp)
    sw      t1, 4(sp)

    csrr    t0, sepc
    lhu     t1, 0(t0)
    andi    t1, t1, 3
    li      t1, 3
    beq     t1, t1, _s_32bit
    addi    t0, t0, 2
    j       _s_set_epc
_s_32bit:
    addi    t0, t0, 4
_s_set_epc:
    csrw    sepc, t0

    la      t0, s_trap_occurred
    li      t1, 1
    sw      t1, 0(t0)

    lw      t0, 0(sp)
    lw      t1, 4(sp)
    addi    sp, sp, 8
    sret


/* ─────────────────────────────────────────────────────────────────
 * BSS SYMBOLS — defined by the linker script
 * ───────────────────────────────────────────────────────────────── */
    .global _bss_start
    .global _bss_end


/* ─────────────────────────────────────────────────────────────────
 * KERNEL STATE FLAGS — accessed by trap handlers and C kernel
 * ───────────────────────────────────────────────────────────────── */
    .section .bss
    .global  m_trap_occurred
    .global  s_trap_occurred
m_trap_occurred:  .word 0
s_trap_occurred:  .word 0
