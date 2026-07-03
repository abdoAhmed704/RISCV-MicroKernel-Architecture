.section .text
.global _start
_start:
    addi  x31, x0, 5             # Starting from previous scenario state

    # Read mstatus to check interrupt/privilege attributes
    # Expected: MPIE bit should be 1 (restored by the last executed mret)
    # Expected: MIE bit should match original pre-trap state (0)
    csrrs  x19, mstatus, x0             

    # Read mepc — Should hold the exact return address calculation 
    # pointing past the faulting code in Scenario 4
    csrrs  x20, mepc, x0                

    # Read mcause — Should preserve the final logged code (2 = Illegal Instruction)
    csrrs  x21, mcause, x0              

    # Final Verification Gate
    addi  x31, x0, 6             # Progress tracker = 6 (ALL SYSTEM SUITES PASSED)
done:
    beq   x0, x0, done