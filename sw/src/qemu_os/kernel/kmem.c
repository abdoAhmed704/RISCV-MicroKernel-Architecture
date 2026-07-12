/*
 * kmem.c — Minimal memory primitives required by GCC's freestanding build.
 *
 * GCC (even with -ffreestanding -nostdlib) may generate calls to memset
 * and memcpy for:
 *   - Zero-initialising global arrays/structs  (.bss section)
 *   - Copying string literals into local char arrays
 *   - Struct compound literals
 *
 * These are NOT provided by libgcc in a -nostdlib build, so we supply
 * our own implementations here.  They are intentionally simple and
 * correct for small embedded use.
 *
 * IMPORTANT: These must be compiled as regular (non-inline, non-static)
 * functions so the linker can resolve the external references that GCC emits.
 */

#include "../include/types.h"

/* Prevent GCC from turning these implementations into recursive calls */
#pragma GCC optimize("no-tree-loop-distribute-patterns")

void *memset(void *dst, int c, size_t n)
{
    unsigned char *d = (unsigned char *)dst;
    while (n--)
        *d++ = (unsigned char)c;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
    unsigned char       *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n; s += n;
        while (n--) *--d = *--s;
    }
    return dst;
}
