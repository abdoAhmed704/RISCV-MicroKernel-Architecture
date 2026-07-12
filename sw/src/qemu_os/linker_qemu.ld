/* ============================================================
 * linker_qemu.ld — Memory layout for QEMU RISC-V 'virt' machine
 *
 * QEMU virt memory map:
 *   0x00001000          ROM (holds a small reset vector)
 *   0x02000000          CLINT (timer/software IRQs)
 *   0x0C000000          PLIC  (external IRQs)
 *   0x10000000          UART0 (NS16550A)
 *   0x80000000 onwards  DRAM  (128 MiB by default with -m 128M)
 *
 * QEMU loads the ELF and starts executing at the ENTRY point.
 * We place _start at the very beginning of DRAM (0x80000000).
 *
 * Stack:
 *   start.s loads SP = 0x80020000 (128 KiB above code start).
 *   The linker does NOT define the stack; start.s owns it.
 * ============================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    /* 128 MiB of QEMU DRAM, starting at 0x80000000 */
    DRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS {
    /* ─── Text (code) ──────────────────────────────────── */
    . = 0x80000000;

    .text : {
        /* Boot stub must be first so _start lands at 0x80000000 */
        KEEP(*(.text.start))
        *(.text*)
    } > DRAM

    . = ALIGN(4);

    /* ─── Read-only data ────────────────────────────────── */
    .rodata : {
        *(.rodata*)
        *(.srodata*)
    } > DRAM

    . = ALIGN(4);

    /* ─── Initialised data ──────────────────────────────── */
    .data : {
        *(.data*)
        *(.sdata*)
    } > DRAM

    . = ALIGN(4);

    /* ─── Uninitialised data (BSS) ──────────────────────── */
    .bss : {
        _bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _bss_end = .;
    } > DRAM

    . = ALIGN(16);
    _end = .;

    /* ─── Discard unwanted sections ─────────────────────── */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
