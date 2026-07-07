.section .text
.global _start
.global m_trap_handler
.global s_trap_handler

_start:
    li sp, 0x00000F00    # Set stack pointer
    call main            # Jump to main
loop:
    j loop               # Infinite loop when done

# M-mode trap handler
.align 4
m_trap_handler:
    mv t5, a0               # Save a0
    csrr a0, mcause
    li t6, 11
    beq a0, t6, m_syscall_handler
    srli a0, a0, 31         # Extract MSB (interrupt bit)
    bnez a0, m_int_handler  # If interrupt, handle it
    
    # Exception: increment mepc by 2 or 4 to skip the trapping instruction
    csrr a0, mepc
    lhu t6, 0(a0)            # load 16-bit instruction at mepc
    andi t6, t6, 3           # extract lowest 2 bits
    li a7, 3                 # check if uncompressed (3)
    beq t6, a7, m_32bit
    addi a0, a0, 2           # compressed: add 2
    j m_set_epc
m_32bit:
    addi a0, a0, 4           # uncompressed: add 4
m_set_epc:
    csrw mepc, a0
    
    # Mark that M-mode trap occurred
    la a0, m_trap_occurred
    li t6, 1
    sw t6, 0(a0)
    
m_int_handler:
    mv a0, t5               # Restore a0
    mret

m_syscall_handler:
    li t6, 1
    beq a7, t6, m_sys_putc
    li t6, 2
    beq a7, t6, m_sys_getc
    li t5, 0
    j m_sys_done

m_sys_putc:
    li t6, 0x00003FF0
    sb t5, 0(t6)
    li t5, 0
    j m_sys_done

m_sys_getc:
    li t6, 0x00003FF0
    lbu t5, 0(t6)

m_sys_done:
    csrr a0, mepc
    addi a0, a0, 4
    csrw mepc, a0
    mv a0, t5
    mret

# S-mode trap handler
.align 4
s_trap_handler:
    mv t5, a0               # Save a0
    csrr a0, scause
    srli a0, a0, 31
    bnez a0, s_int_handler
    
    # Exception: increment sepc by 2 or 4
    csrr a0, sepc
    lhu t6, 0(a0)            # load 16-bit instruction at sepc
    andi t6, t6, 3           # extract lowest 2 bits
    li a7, 3                 # check if uncompressed (3)
    beq t6, a7, s_32bit
    addi a0, a0, 2           # compressed: add 2
    j s_set_epc
s_32bit:
    addi a0, a0, 4           # uncompressed: add 4
s_set_epc:
    csrw sepc, a0
    
    # Mark S-mode trap occurred
    la a0, s_trap_occurred
    li t6, 1
    sw t6, 0(a0)

s_int_handler:
    mv a0, t5               # Restore a0
    sret
