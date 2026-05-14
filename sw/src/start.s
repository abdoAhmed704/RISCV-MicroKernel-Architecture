.section .text
.global _start

_start:
    li sp, 0x00000F00    # Set stack pointer
    call main            # Jump to main
loop:
    j loop               # Infinite loop when done