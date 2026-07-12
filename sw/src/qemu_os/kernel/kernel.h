/*
 * kernel.h — Public declarations for the kernel module
 */
#ifndef KERNEL_H
#define KERNEL_H

#include "../include/types.h"

/**
 * kernel_main() — C entry point called by the assembly boot stub.
 * Initialises all hardware and launches the GUI desktop loop.
 */
void kernel_main(void);

/**
 * syscall_dispatch() — Called from the M-mode trap handler (start.s)
 * when mcause == 11 (ECALL from M-mode).
 *
 * Parameters match the RISC-V calling convention registers:
 *   num  ← a7 (syscall number)
 *   a0   ← a0 (first argument)
 *   a1   ← a1 (second argument)
 *   a2   ← a2 (third argument)
 *
 * Return value is placed back into a0.
 */
uint32_t syscall_dispatch(uint32_t num, uint32_t a0,
                          uint32_t a1, uint32_t a2);

#endif /* KERNEL_H */
