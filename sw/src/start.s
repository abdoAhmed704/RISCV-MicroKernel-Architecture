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
    
    # Exception: increment mepc by 4 to skip the trapping instruction
    csrr a0, mepc
    addi a0, a0, 4
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
    
    # Exception: increment sepc by 4
    csrr a0, sepc
    addi a0, a0, 4
    csrw sepc, a0
    
    # Mark S-mode trap occurred
    la a0, s_trap_occurred
    li t6, 1
    sw t6, 0(a0)

s_int_handler:
    mv a0, t5               # Restore a0
    sret
