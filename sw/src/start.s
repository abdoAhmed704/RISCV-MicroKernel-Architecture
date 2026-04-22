.section .text
.global _start

_start:
    li sp, 0x3000      # Set Stack Pointer to top of RAM (adjust as needed)
    call main          # Jump to C code
loop:
    j loop             # Infinite loop if main returns
