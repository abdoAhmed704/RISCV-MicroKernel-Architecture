/*
 * uart.c — NS16550A UART driver for QEMU RISC-V 'virt' machine
 *
 * Register map (at base 0x10000000, 1-byte stride):
 *   Offset 0  DLAB=0: THR (write) / RBR (read)
 *   Offset 1  DLAB=0: IER (Interrupt Enable Register)
 *   Offset 2  FCR (write) / IIR (read)
 *   Offset 3  LCR (Line Control Register)
 *   Offset 4  MCR (Modem Control Register)
 *   Offset 5  LSR (Line Status Register)
 *   Offset 0  DLAB=1: DLL (Divisor Latch Low)
 *   Offset 1  DLAB=1: DLH (Divisor Latch High)
 *
 * QEMU's simulated 16550A clock is 1843200 Hz.
 * Divisor for 115200 baud = 1843200 / (16 × 115200) = 1.
 */

#include "uart.h"

/* ── Register base address (QEMU virt UART0) ────────────────────── */
#define UART0_BASE  0x10000000UL
#define REG(n)      MMIO8(UART0_BASE + (n))

/* ── Register offsets ──────────────────────────────────────────── */
#define THR  0   /* Transmit Holding Register (DLAB=0, write)       */
#define RBR  0   /* Receive Buffer Register   (DLAB=0, read)        */
#define IER  1   /* Interrupt Enable Register                        */
#define FCR  2   /* FIFO Control Register     (write)                */
#define LCR  3   /* Line Control Register                            */
#define MCR  4   /* Modem Control Register                           */
#define LSR  5   /* Line Status Register                             */
#define DLL  0   /* Divisor Latch Low  (DLAB=1)                     */
#define DLH  1   /* Divisor Latch High (DLAB=1)                     */

/* ── LSR bits ───────────────────────────────────────────────────── */
#define LSR_RX_READY  0x01   /* Bit 0: data available in RBR       */
#define LSR_TX_READY  0x20   /* Bit 5: THR empty, ready to send    */

/* ── hex characters ─────────────────────────────────────────────── */
static const char HEX[] = "0123456789ABCDEF";

/* ================================================================= */
void uart_init(void)
{
    /* Disable all interrupts (we use polling) */
    REG(IER) = 0x00;

    /* Enable DLAB to set baud rate divisor */
    REG(LCR) = 0x80;
    REG(DLL) = 0x01;   /* Divisor = 1 → 115200 baud at 1.8432 MHz */
    REG(DLH) = 0x00;

    /* 8 data bits, no parity, 1 stop bit (8N1), DLAB=0 */
    REG(LCR) = 0x03;

    /* Enable FIFOs, clear TX/RX FIFOs, trigger at 8 bytes */
    REG(FCR) = 0xC7;

    /* Assert RTS and DTR (required by some real hardware) */
    REG(MCR) = 0x0B;
}

/* ================================================================= */
void uart_putc(char c)
{
    /* Spin until the transmit holding register is empty */
    while (!(REG(LSR) & LSR_TX_READY))
        ;
    REG(THR) = (uint8_t)c;
}

/* ================================================================= */
void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* ================================================================= */
void uart_put_uint32(uint32_t n)
{
    char buf[11];
    kitoa(n, buf);
    uart_puts(buf);
}

/* ================================================================= */
void uart_put_hex32(uint32_t n)
{
    uart_puts("0x");
    for (int i = 7; i >= 0; i--)
        uart_putc(HEX[(n >> (i * 4)) & 0xF]);
}

/* ================================================================= */
int uart_getc(void)
{
    while (!(REG(LSR) & LSR_RX_READY))
        ;
    return (int)(uint8_t)REG(RBR);
}

/* ================================================================= */
int uart_getc_nb(void)
{
    if (REG(LSR) & LSR_RX_READY)
        return (int)(uint8_t)REG(RBR);
    return -1;
}
