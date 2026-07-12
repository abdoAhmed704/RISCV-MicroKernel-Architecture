.section .text
.global _start
.option norvc

_start:
    # =================================================================
    # Balanced RISC-V Test Suite (Base + CSR + M + C + Cache + Predict)
    # Verifies 3 to 5 instructions per component.
    # =================================================================

    # -----------------------------------------------------------------
    # 1. Base ALU & Branching
    # -----------------------------------------------------------------
    li    x31, 10
    li    x1, 10
    li    x2, -5
    add   x3, x1, x2         # x3 = 5
    sub   x4, x1, x2         # x4 = 15
    and   x5, x1, x2         # x5 = 10 & -5 = 10
    or    x6, x1, x2         # x6 = 10 | -5 = -5
    
    # Verification
    li    x30, 5
    bne   x3, x30, fail
    li    x30, 15
    bne   x4, x30, fail
    li    x30, 10
    bne   x5, x30, fail
    li    x30, -5
    bne   x6, x30, fail

    # -----------------------------------------------------------------
    # 2. Caches & Memory Consistency (sw, sh, sb, lw, lh, lb)
    # -----------------------------------------------------------------
    li    x31, 20
    li    x15, 0x00002000    # RAM Base Address
    
    # Stores (3 instructions)
    sw    x1, 0(x15)         # Writes 10
    sh    x2, 4(x15)         # Writes -5
    sb    x3, 8(x15)         # Writes 5
    
    # Loads (3 instructions - verify cache hit/coherency)
    lw    x21, 0(x15)
    lh    x22, 4(x15)
    lb    x23, 8(x15)
    
    li    x30, 10
    bne   x21, x30, fail
    li    x30, -5
    bne   x22, x30, fail
    li    x30, 5
    bne   x23, x30, fail

    # -----------------------------------------------------------------
    # 3. CSR Instructions (csrw, csrr, csrrw, csrrs, csrrc)
    # -----------------------------------------------------------------
    li    x31, 30
    csrw  mscratch, x0       # 1. Clear mscratch (csrw)
    
    li    x12, 10
    csrrw x26, mscratch, x12 # 2. Write 10, read 0 (csrrw)
    bne   x26, x0, fail
    
    li    x13, 4
    csrrs x27, mscratch, x13 # 3. Set bits: 10 | 4 = 14, read 10 (csrrs)
    li    x30, 10
    bne   x27, x30, fail
    
    csrrc x28, mscratch, x12 # 4. Clear bits: 14 & ~10 = 4, read 14 (csrrc)
    li    x30, 14
    bne   x28, x30, fail
    
    csrr  x29, mscratch      # 5. Read back 4 (csrr)
    li    x30, 4
    bne   x29, x30, fail

    # -----------------------------------------------------------------
    # 4. M Extension Arithmetic (mul, mulh, div, rem)
    # -----------------------------------------------------------------
    li    x31, 40
    li    x1, 10
    li    x2, -5
    
    mul   x13, x1, x2        # 1. Multiplication: -50
    mulh  x14, x1, x2        # 2. High-half signed: -1
    div   x16, x1, x2        # 3. Division: -2
    rem   x17, x1, x2        # 4. Remainder: 0
    
    li    x30, -50
    bne   x13, x30, fail
    li    x30, -1
    bne   x14, x30, fail
    li    x30, -2
    bne   x16, x30, fail
    bne   x17, x0, fail

    # -----------------------------------------------------------------
    # 5. C Extension (RVC: c.li, c.mv, c.addi, c.add)
    # -----------------------------------------------------------------
    li    x31, 50
    li    x15, 10
    
    .option rvc
    c.li   x10, 15           # 1. Compressed load immediate
    c.mv   x11, x10          # 2. Compressed register move
    c.addi x11, -5           # 3. Compressed add immediate (15 - 5 = 10)
    c.add  x11, x15          # 4. Compressed register add (10 + 10 = 25)
    .option norvc
    
    li    x30, 15
    bne   x10, x30, fail
    li    x30, 20            # Wait: x11 = 15 - 5 + 10 = 20.
    bne   x11, x30, fail

    # -----------------------------------------------------------------
    # 6. Branch Prediction (Static Predictor & Alternating Dynamic)
    # -----------------------------------------------------------------
    li    x31, 60
    
    # Static branch training loop (highly predictable)
    li    x10, 5
predict_loop:
    addi  x10, x10, -1
    bnez  x10, predict_loop
    
    # Dynamic alternating branch training (T, NT, T, NT)
    li    x10, 0
alt_loop:
    andi  x11, x10, 1
    addi  x10, x10, 1
    li    x30, 4
    beq   x10, x30, alt_done
    
    bnez  x11, branch_taken  # Taken on odd loops, Not-Taken on evens
    j     alt_loop
branch_taken:
    j     alt_loop
alt_done:

    # -----------------------------------------------------------------
    # 7. Tiny Inference Chip (Linear Classifier Unit - Custom-0 Opcode 0x0B)
    # -----------------------------------------------------------------
    li    x31, 70

    # Load weights
    li    x11, 2             # Weight data
    li    x12, 0             # Row = 0, Col = 0 -> rs2 = 0
    .insn r 0x0b, 0, 0, x0, x11, x12

    li    x11, 1             # Weight data
    li    x12, 1             # Row = 0, Col = 1 -> rs2 = 1
    .insn r 0x0b, 0, 0, x0, x11, x12

    li    x11, 3             # Weight data
    li    x12, 4             # Row = 1, Col = 0 -> rs2 = 4
    .insn r 0x0b, 0, 0, x0, x11, x12

    li    x11, 5             # Weight data
    li    x12, 5             # Row = 1, Col = 1 -> rs2 = 5
    .insn r 0x0b, 0, 0, x0, x11, x12

    # Load input features
    li    x11, 10            # Input data
    li    x12, 0             # Addr = 0 -> rs2 = 0
    .insn r 0x0b, 1, 0, x0, x11, x12

    li    x11, 4             # Input data
    li    x12, 1             # Addr = 1 -> rs2 = 1
    .insn r 0x0b, 1, 0, x0, x11, x12

    # Trigger computation
    .insn r 0x0b, 2, 0, x0, x0, x0

    # Wait for systolic computation cycles
    li    x10, 20
wait_loop:
    addi  x10, x10, -1
    bnez  x10, wait_loop

    # Read back results
    # Read done flag
    li    x12, 0
    .insn r 0x0b, 3, 0, x24, x12, x0
    li    x30, 1
    bne   x24, x30, fail

    # Read predicted class (argmax)
    li    x12, 1
    .insn r 0x0b, 3, 0, x25, x12, x0
    li    x30, 0
    bne   x25, x30, fail

    # Read score[0] (Expected: 10*2 + 4*3 = 32)
    li    x12, 2
    .insn r 0x0b, 3, 0, x18, x12, x0
    li    x30, 32
    bne   x18, x30, fail

    # Read score[1] (Expected: 10*1 + 4*5 = 30)
    li    x12, 3
    .insn r 0x0b, 3, 0, x19, x12, x0
    li    x30, 30
    bne   x19, x30, fail

    # =================================================================
    # Success: Output 0xFEEDDEED in x31
    # =================================================================
    li    x31, 0xFEEDDEED
    j     done

fail:
    li    x30, 0xDEAD0000
    or    x31, x31, x30

done:
    j     done
