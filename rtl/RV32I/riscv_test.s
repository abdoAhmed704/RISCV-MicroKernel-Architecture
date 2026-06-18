.section .text
.global _start
_start:
    # =================================================================
    # BLOCK 1: Arithmetic, Logic & Forwarding
    # STRESS TEST: Forwarding Unit (E->E and M->E)
    # =================================================================
    addi x31, x0, 1       # Progress Tracker = 1
    addi x1, x0, 10       # Load 10
    addi x2, x0, -5       # Load -5
    add  x3, x1, x2       # Expect 5.
    sub  x4, x1, x2       # Expect 15.
    and  x5, x1, x2       # Logic AND
    or   x6, x1, x2       # Logic OR
    sll  x8, x1, x3       # Shift Left Logical (10 << 5 = 320)
    sra  x9, x2, x3       # Shift Right Arithmetic (-5 >> 5 = -1)
    # =================================================================
    # BLOCK 2: U-Type Instructions
    # =================================================================
    addi x31, x31, 1      # Progress Tracker = 2
    lui   x10, 0x12345    # Load 0x12345000
    auipc x11, 0x00001    # x11 = current PC + 0x1000
    # =================================================================
    # BLOCK 3: Memory Operations & Load-Use Hazards
    # FIX: Address changed from 0x400 to 0x100 to fit your 1024-word RAM
    # =================================================================
    addi x31, x31, 1      # Progress Tracker = 3
    addi x12, x0, 0x100   # Set base RAM address to 256 (0x100)
    lui  x13, 0xDEADB     
    ori  x13, x13, 0x7FF  
    sw   x13, 0(x12)      # Store Word in Index 256
    lw   x14, 0(x12)      # Load Word (Should Trigger STALL if used next)
    addi x15, x14, 0      # Stall and check if x15 == 0xDEADB7FF
    # Byte Ops Test (Note: will affect full word in your current RAM)
    addi x20, x0, 0x7F    
    sb   x20, 1(x12)      # Store Byte at Index 257 (0x101)
    lb   x16, 1(x12)      # Load Byte
    lbu  x17, 1(x12)      # Load Byte Unsigned
    # =================================================================
    # BLOCK 4: Control Flow & Pipeline Flushing
    # =================================================================
    addi x31, x31, 1      # Progress Tracker = 4
    addi x18, x0, 20
    addi x19, x0, 20
    # Test 1: Branching
    beq  x18, x19, branch_hit 
    addi x31, x0, 0x123   # FAIL: This should be FLUSHED
    
branch_hit:
    # Test 2: JAL (Jump and Link)
    jal  x1, jal_hit      # Jump and save PC+4 in x1
    addi x31, x0, 0x123   # FAIL: This should be FLUSHED
jal_hit:
    # Test 3: JALR (Jump and Link Register)
    auipc x21, 0          
    addi  x21, x21, 16    # Pointer to pass_label
    jalr  x1, 0(x21)      # Jump to pass_label
    
    addi x31, x0, 0x123   # FAIL: This should be FLUSHED

pass_label:
    addi x31, x31, 1      # FINAL Progress Tracker = 5

done:
    beq x0, x0, done      # Infinite Loop
