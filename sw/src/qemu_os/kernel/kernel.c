/*
 * kernel.c — Main kernel entry point for the RISC-V QEMU OS
 *
 * Call sequence after start.s completes:
 *   kernel_main()
 *     ├── uart_init()        Initialise the NS16550A UART
 *     ├── fb_init()          Prepare the virtual framebuffer
 *     └── desktop_run()      Enter the GUI event loop (never returns)
 *
 * Trap/syscall infrastructure:
 *   The C trap dispatcher syscall_dispatch() is called from the
 *   M-mode trap handler in start.s when mcause == 11 (ECALL).
 *   It switches on the value of register a7 (syscall number).
 *
 * Global kernel state flags m_trap_occurred and s_trap_occurred are
 * defined in start.s (.bss section) and declared extern here.
 */

#include "kernel.h"
#include "../drivers/uart.h"
#include "../drivers/framebuffer.h"
#include "../apps/desktop.h"
#include "../include/types.h"

/* ── Trap occurrence flags (defined in start.s .bss) ────────────── */
extern volatile uint32_t m_trap_occurred;
extern volatile uint32_t s_trap_occurred;

/* ── UART base (for direct MMIO putc inside syscall_dispatch) ────── */
#define UART0_THR  MMIO8(0x10000000)
#define UART0_LSR  MMIO8(0x10000005)

/* ─────────────────────────────────────────────────────────────────
 * syscall_dispatch() — called from the M-mode trap handler
 *
 * Arguments (matching RISC-V calling convention from start.s):
 *   a7 → syscall number
 *   a0 → first argument
 *   a1 → second argument
 *   a2 → third argument
 *
 * Returns: a0 (return value passed back to user).
 *
 * Syscall table:
 *   1  SYS_PUTC   — write char in a0 to UART
 *   2  SYS_GETC   — read char from UART (blocking), return in a0
 *   3  SYS_YIELD  — cooperative yield (nop for now)
 *   4  SYS_EXIT   — halt the hart
 * ─────────────────────────────────────────────────────────────────*/
uint32_t syscall_dispatch(uint32_t num, uint32_t a0,
                          uint32_t a1, uint32_t a2)
{
    (void)a1; (void)a2;

    switch (num) {
    case 1: /* SYS_PUTC */
        while (!(UART0_LSR & 0x20));
        UART0_THR = (uint8_t)(a0 & 0xFF);
        return 0;

    case 2: /* SYS_GETC */
        while (!(UART0_LSR & 0x01));
        return (uint32_t)(uint8_t)MMIO8(0x10000000);

    case 3: /* SYS_YIELD */
        /* In a fully preemptive kernel this would context-switch;
         * here we simply return, letting the cooperative loop tick. */
        return 0;

    case 4: /* SYS_EXIT */
        /* Park the hart */
        while (1) asm volatile ("wfi");
        return 0;

    default:
        return (uint32_t)-1;
    }
}

/* ─────────────────────────────────────────────────────────────────
 * kernel_main() — C entry point called from _start in start.s
 * ───────────────────────────────────────────────────────────────── */
void kernel_main(void)
{
    /* 1. Bring up the serial console */
    uart_init();

    /* 2. Print a brief banner over raw UART before the GUI starts.
     *    This is visible even if the terminal doesn't support ANSI. */
    uart_puts("\r\n\r\n");
    uart_puts("=========================================\r\n");
    uart_puts("  RISC-V MicroKernel OS  (QEMU virt)   \r\n");
    uart_puts("  Build: RV32IMA_Zicsr  |  M-mode boot \r\n");
    uart_puts("  Starting GUI...                       \r\n");
    uart_puts("=========================================\r\n");
    uart_puts("\r\n");

    /* 3. Launch the GUI desktop shell (does not return) */
    desktop_run();

    /* Unreachable — halt just in case */
    while (1) asm volatile ("wfi");
}
