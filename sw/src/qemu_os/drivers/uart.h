/*
 * uart.h — Public API for the NS16550A UART driver
 *
 * The QEMU 'virt' machine maps a 16550A-compatible UART at 0x10000000.
 * All output to the terminal (including the GUI ANSI sequences) goes
 * through this driver.
 */

#ifndef UART_H
#define UART_H

#include "../include/types.h"

/* ── Public API ──────────────────────────────────────────────────── */

/**
 * uart_init() — Configure the 16550A UART for 115200-8N1.
 * Must be called before any uart_putc / uart_puts calls.
 */
void uart_init(void);

/**
 * uart_putc() — Transmit a single character (blocking).
 * Spins on the TX-ready bit; safe to call from interrupt context
 * because the spin is very short on a simulated UART.
 */
void uart_putc(char c);

/**
 * uart_puts() — Transmit a NUL-terminated string (blocking).
 */
void uart_puts(const char *s);

/**
 * uart_put_uint32() — Transmit a 32-bit integer as decimal.
 */
void uart_put_uint32(uint32_t n);

/**
 * uart_put_hex32() — Transmit a 32-bit integer as "0x????????".
 */
void uart_put_hex32(uint32_t n);

/**
 * uart_getc() — Wait until a character arrives and return it.
 */
int uart_getc(void);

/**
 * uart_getc_nb() — Non-blocking receive.
 * Returns the received character, or -1 if no data is available.
 */
int uart_getc_nb(void);

#endif /* UART_H */
