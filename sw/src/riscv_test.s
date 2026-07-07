.section .text
.global _start
.option norvc

_start:
    # =================================================================
    # Big integration test:
    # - RV32I ALU/forwarding
    # - load/store and load-use stall
    # - explicit RV32C compressed decode
    # - dynamic branch prediction taken/not-taken recovery
    # - JAL/JALR flushing
    # - tinyInferenceChip custom opcode path
    #
    # On success: x31 = 0xFEEDDEED and all registers have the published
    # final values listed at the bottom of this file.
    # On failure: x31 = 0xDEAD00NN where NN is the failing check number.
    # =================================================================

    # ---------------- ALU and forwarding ----------------
    li    x31, 1
    li    x1,  10
    li    x2,  -5
    add   x3,  x1, x2          # 5
    sub   x4,  x1, x2          # 15
    and   x5,  x1, x2          # 10
    or    x6,  x1, x2          # -5
    sll   x7,  x1, x3          # 320
    sra   x8,  x2, x3          # -1

    li    x31, 2
    li    x30, 5
    bne   x3, x30, fail
    li    x31, 3
    li    x30, 15
    bne   x4, x30, fail
    li    x31, 4
    li    x30, 10
    bne   x5, x30, fail
    li    x31, 5
    li    x30, -5
    bne   x6, x30, fail
    li    x31, 6
    li    x30, 320
    bne   x7, x30, fail
    li    x31, 7
    li    x30, -1
    bne   x8, x30, fail

    # ---------------- Memory and load-use hazard ----------------
    li    x31, 8
    li    x12, 0x100
    lui   x13, 0xDEADB
    ori   x13, x13, 0x7FF      # 0xDEADB7FF
    sw    x13, 0(x12)
    lw    x14, 0(x12)
    addi  x15, x14, 0          # immediate load-use check
    bne   x15, x13, fail

    li    x31, 9
    li    x20, 0x7F
    sb    x20, 1(x12)
    lb    x16, 1(x12)
    lbu   x17, 1(x12)
    bne   x16, x20, fail
    bne   x17, x20, fail

    li    x31, 10
    li    x18, 0x8765
    sh    x18, 6(x12)
    lhu   x19, 6(x12)
    bne   x19, x18, fail

    # ---------------- Explicit compressed decode ----------------
    li    x31, 11
    .option push
    .option rvc
    c.li   x21, 5
    c.addi x21, 7
    c.mv   x22, x21
    .option pop
    li    x30, 12
    bne   x22, x30, fail

    # ---------------- Dynamic branch prediction recovery ----------------
    # This warms the predictor with taken branches, then requires the final
    # not-taken exit to flush the predicted-taken wrong path correctly.
    li    x31, 12
    li    x23, 0
    li    x24, 6
branch_loop:
    addi  x23, x23, 1
    blt   x23, x24, branch_loop
    bne   x23, x24, fail

    # Not-taken branch should not flush or redirect.
    li    x31, 13
    beq   x23, x0, fail

    # ---------------- JAL and JALR flush paths ----------------
    li    x31, 14
    jal   x1, jal_hit
    li    x31, 0x123           # must be flushed

jal_hit:
    auipc x25, 0
    addi  x25, x25, 16
    jalr  x1, 0(x25)
    li    x31, 0x124           # must be flushed

jalr_hit:
    li    x30, 14
    bne   x31, x30, fail

    # ---------------- tinyInferenceChip custom opcode ----------------
    # W rows:
    #   [ 2,  3,  4,  5]
    #   [ 6,  7,  8,  9]
    #   [10, 11, 12, 13]
    #   [14, 15, 16, 17]
    # x = [1, 2, 3, 4]
    # Expected y = [100, 110, 120, 130], class = 3.
    li    x31, 15

    li x28, 2;      li x29, 0;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 3;      li x29, 1;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 4;      li x29, 2;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 5;      li x29, 3;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 6;      li x29, 4;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 7;      li x29, 5;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 8;      li x29, 6;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 9;      li x29, 7;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 10;     li x29, 8;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 11;     li x29, 9;      .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 12;     li x29, 10;     .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 13;     li x29, 11;     .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 14;     li x29, 12;     .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 15;     li x29, 13;     .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 16;     li x29, 14;     .insn r 0x0B, 0, 0, x0, x28, x29
    li x28, 17;     li x29, 15;     .insn r 0x0B, 0, 0, x0, x28, x29

    li x28, 1;      li x29, 0;      .insn r 0x0B, 1, 0, x0, x28, x29
    li x28, 2;      li x29, 1;      .insn r 0x0B, 1, 0, x0, x28, x29
    li x28, 3;      li x29, 2;      .insn r 0x0B, 1, 0, x0, x28, x29
    li x28, 4;      li x29, 3;      .insn r 0x0B, 1, 0, x0, x28, x29

    .insn r 0x0B, 2, 0, x0, x0, x0

    li    x29, 0
poll_done:
    .insn r 0x0B, 3, 0, x28, x29, x0
    beqz  x28, poll_done

    li x29, 1;      .insn r 0x0B, 3, 0, x10, x29, x0
    li x29, 2;      .insn r 0x0B, 3, 0, x11, x29, x0
    li x29, 3;      .insn r 0x0B, 3, 0, x12, x29, x0
    li x29, 4;      .insn r 0x0B, 3, 0, x13, x29, x0
    li x29, 5;      .insn r 0x0B, 3, 0, x14, x29, x0

    li    x31, 16
    li    x30, 3
    bne   x10, x30, fail
    li    x31, 17
    li    x30, 100
    bne   x11, x30, fail
    li    x31, 18
    li    x30, 110
    bne   x12, x30, fail
    li    x31, 19
    li    x30, 120
    bne   x13, x30, fail
    li    x31, 20
    li    x30, 130
    bne   x14, x30, fail

    # ---------------- RV32M multiply/divide/remainder ----------------
    li    x31, 21
    li    x1, -7
    li    x2, 6
    mul   x3, x1, x2            # low(-7 * 6) = -42
    li    x30, -42
    bne   x3, x30, fail

    li    x31, 22
    mulh  x4, x1, x2            # high signed(-7 * 6) = -1
    li    x30, -1
    bne   x4, x30, fail

    li    x31, 23
    mulhsu x5, x1, x2           # high signed(-7) * unsigned(6) = -1
    li    x30, -1
    bne   x5, x30, fail

    li    x31, 24
    mulhu x6, x1, x2            # high unsigned(0xfffffff9 * 6) = 5
    li    x30, 5
    bne   x6, x30, fail

    li    x31, 25
    li    x1, -42
    li    x2, 5
    div   x7, x1, x2            # -42 / 5 = -8
    li    x30, -8
    bne   x7, x30, fail

    li    x31, 26
    rem   x9, x1, x2            # -42 % 5 = -2
    li    x30, -2
    bne   x9, x30, fail

    li    x31, 27
    li    x1, 100
    li    x2, 7
    divu  x8, x1, x2            # 100 / 7 = 14
    li    x30, 14
    bne   x8, x30, fail

    li    x31, 28
    remu  x15, x1, x2           # 100 % 7 = 2
    li    x30, 2
    bne   x15, x30, fail

    li    x31, 29
    li    x1, 0x12345678
    li    x2, 0
    div   x16, x1, x2           # divide by zero quotient = -1
    li    x30, -1
    bne   x16, x30, fail

    li    x31, 30
    rem   x17, x1, x2           # remainder by zero = dividend
    li    x30, 0x12345678
    bne   x17, x30, fail

    # ---------------- Publish deterministic final register map ----------------
    li    x1,  0x11111111
    li    x2,  0x22222222
    li    x3,  -42
    li    x4,  -1
    li    x5,  -1
    li    x6,  5
    li    x7,  -8
    li    x8,  14
    li    x9,  -2
    # x10-x14 keep tinyInference result: class, score0..score3
    li    x15, 2
    li    x16, -1
    li    x17, 0x12345678
    li    x18, 0x8765
    li    x19, 0x8765
    li    x20, 0x7F
    li    x21, 12
    li    x22, 12
    li    x23, 6
    li    x24, 6
    la    x25, jalr_hit
    li    x26, 0x0BADCAFE
    li    x27, 0x13579BDF
    li    x28, 1
    li    x29, 5
    li    x30, 130
    li    x31, 0xFEEDDEED
    j     done

fail:
    li    x30, 0xDEAD0000
    or    x31, x31, x30

done:
    j     done

# Expected final register map on success:
# x00=00000000 x01=11111111 x02=22222222 x03=ffffffd6
# x04=ffffffff x05=ffffffff x06=00000005 x07=fffffff8
# x08=0000000e x09=fffffffe x10=00000003 x11=00000064
# x12=0000006e x13=00000078 x14=00000082 x15=00000002
# x16=ffffffff x17=12345678 x18=00008765 x19=00008765
# x20=0000007f x21=0000000c x22=0000000c x23=00000006
# x24=00000006 x25=0000010e x26=0badcafe x27=13579bdf
# x28=00000001 x29=00000005 x30=00000082 x31=feeddeed
