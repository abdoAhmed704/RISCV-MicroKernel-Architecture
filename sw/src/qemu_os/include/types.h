/*
 * types.h — Primitive type definitions for the RISC-V QEMU OS
 *
 * This file is self-contained and does not depend on any host
 * standard library, making it safe for freestanding bare-metal builds.
 */

#ifndef TYPES_H
#define TYPES_H

/* ── Unsigned integer types ──────────────────────────────────────── */
typedef unsigned char      uint8_t;
typedef unsigned short     uint16_t;
typedef unsigned int       uint32_t;
typedef unsigned long long uint64_t;

/* ── Signed integer types ────────────────────────────────────────── */
typedef signed char      int8_t;
typedef signed short     int16_t;
typedef signed int       int32_t;
typedef signed long long int64_t;

/* ── Size and pointer types ─────────────────────────────────────── */
typedef uint32_t  size_t;
typedef int32_t   ssize_t;
typedef uint32_t  uintptr_t;

/* ── Boolean: In GCC 15+ (C23), 'bool' and 'true'/'false' are
 *   built-in keywords.  We use a plain uint32_t alias 'BOOL'
 *   for our own code so there is no conflict at all.             */
typedef uint32_t BOOL;
#define BOOL_TRUE  1u
#define BOOL_FALSE 0u

/* ── Null pointer ───────────────────────────────────────────────── */
#ifndef NULL
#define NULL ((void *)0)
#endif

/* ── Utility macros ─────────────────────────────────────────────── */
#define ARRAY_SIZE(a)   (sizeof(a) / sizeof((a)[0]))
#define MIN(a, b)       ((a) < (b) ? (a) : (b))
#define MAX(a, b)       ((a) > (b) ? (a) : (b))
#define CLAMP(v, lo, hi) (MIN(MAX((v),(lo)),(hi)))

/* ── MMIO register accessor ─────────────────────────────────────── */
#define MMIO8(addr)   (*(volatile uint8_t  *)(uintptr_t)(addr))
#define MMIO16(addr)  (*(volatile uint16_t *)(uintptr_t)(addr))
#define MMIO32(addr)  (*(volatile uint32_t *)(uintptr_t)(addr))

/* ── String length helper (no stdlib) ───────────────────────────── */
static inline size_t kstrlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}

/* ── Integer to decimal string (no stdlib) ──────────────────────── */
static inline void kitoa(uint32_t n, char *buf) {
    char tmp[11];
    int  i = 0, j = 0;
    if (n == 0) { buf[j++] = '0'; buf[j] = '\0'; return; }
    while (n) { tmp[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) buf[j++] = tmp[--i];
    buf[j] = '\0';
}

/* ── Integer to hex string, zero-padded to 8 digits ────────────── */
static inline void kitohex(uint32_t n, char *buf) {
    const char *hex = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--) {
        buf[i] = hex[n & 0xF];
        n >>= 4;
    }
    buf[8] = '\0';
}


#endif /* TYPES_H */
