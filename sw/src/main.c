volatile int m_trap_occurred = 0;
volatile int s_trap_occurred = 0;
volatile int s_mode_entered = 0;

void m_trap_handler(void);
void s_trap_handler(void);

int main()
{
    // 1. Test basic CSR read/write in M-mode
    asm volatile ("csrw mscratch, %0" :: "r"(0xDEADBEEF));
    unsigned int scratch_val = 0;
    asm volatile ("csrr %0, mscratch" : "=r"(scratch_val));
    if (scratch_val != 0xDEADBEEF) return 1; // Basic CSR write/read failed

    // 2. Register M-mode trap handler
    asm volatile ("csrw mtvec, %0" :: "r"((unsigned int)m_trap_handler & ~0x3)); // Direct mode, aligned

    // 3. Test ECALL trap in M-mode
    m_trap_occurred = 0;
    asm volatile ("ecall");
    if (m_trap_occurred != 1) return 2; // M-mode ECALL trap failed

    // 4. Test Illegal Instruction exception in M-mode (write to read-only CSR)
    m_trap_occurred = 0;
    asm volatile ("csrw mhartid, %0" :: "r"(1)); // mhartid is read-only
    if (m_trap_occurred != 1) return 3; // M-mode illegal instruction trap failed

    // 5. Test trap delegation to S-mode
    // Set stvec to s_trap_handler
    asm volatile ("csrw stvec, %0" :: "r"(s_trap_handler));
    
    // Delegate illegal instruction exception (cause 2) to S-mode by setting bit 2 in medeleg
    asm volatile ("csrw medeleg, %0" :: "r"(1 << 2));

    // Set mstatus MPP to S-mode (2'b01)
    // mstatus.MPP is bits 12:11. Clear them and set to 2'b01
    unsigned int mstatus_val = 0;
    asm volatile ("csrr %0, mstatus" : "=r"(mstatus_val));
    mstatus_val = (mstatus_val & ~(3 << 11)) | (1 << 11);
    asm volatile ("csrw mstatus, %0" :: "r"(mstatus_val));

    // Transition to S-mode and execute S-mode tests inline
    m_trap_occurred = 0;
    s_trap_occurred = 0;
    s_mode_entered = 0;

    asm volatile (
        "la t0, s_test_start\n\t"
        "csrw mepc, t0\n\t"
        "mret\n\t"
        
        "s_test_start:\n\t"
        // Now in S-mode!
        "li t1, 1\n\t"
        "la t2, s_mode_entered\n\t"
        "sw t1, 0(t2)\n\t"
        
        // Try to write to M-mode CSR mscratch (privilege violation -> traps to s_trap_handler)
        "csrw mscratch, t1\n\t"
        
        // Exit S-mode by doing an ECALL (traps to M-mode, which increments mepc and returns here)
        "ecall\n\t"
        
        // S-mode will continue executing from here!
        "nop\n\t"
        :: : "t0", "t1", "t2"
    );

    // Verify results
    if (s_mode_entered != 1) return 4;
    if (s_trap_occurred != 1) return 5;
    if (m_trap_occurred != 1) return 6;

    // All tests passed! Return 15 (0xF)
    return 15;
}