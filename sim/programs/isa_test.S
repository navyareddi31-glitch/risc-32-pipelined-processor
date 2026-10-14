# isa_test.S - self-checking RV32I functional test (also exercises hazards)
# x30 = current check number, x31 = 0x600D pass / 0x0BAD fail
        li   x30, 1              # LUI
        lui  x1, 0x12345
        li   x2, 0x12345000
        bne  x1, x2, fail

        li   x30, 2              # AUIPC
        auipc x1, 0
        auipc x2, 0
        sub  x3, x2, x1
        li   x4, 4
        bne  x3, x4, fail

        li   x30, 3              # ADDI
        li   x1, 100
        addi x2, x1, -30
        li   x3, 70
        bne  x2, x3, fail

        li   x30, 4              # SLTI / SLTIU
        li   x1, -5
        slti x2, x1, 3
        slti x3, x1, -6
        sltiu x4, x1, 5
        sltiu x5, x0, 5
        li   x6, 1
        bne  x2, x6, fail
        bne  x3, x0, fail
        bne  x4, x0, fail
        bne  x5, x6, fail

        li   x30, 5              # XORI / ORI / ANDI
        li   x1, 0xF0F
        xori x2, x1, 0x0FF
        ori  x3, x1, 0x0F0
        andi x4, x1, 0x0FF
        li   x5, 0xFF0
        bne  x2, x5, fail
        li   x5, 0xFFF
        bne  x3, x5, fail
        li   x5, 0x00F
        bne  x4, x5, fail

        li   x30, 6              # SLLI / SRLI / SRAI
        li   x1, 0x80000001
        slli x2, x1, 4
        srli x3, x1, 4
        srai x4, x1, 4
        li   x5, 0x10
        bne  x2, x5, fail
        li   x5, 0x08000000
        bne  x3, x5, fail
        li   x5, 0xF8000000
        bne  x4, x5, fail

        li   x30, 7              # register-register ALU
        li   x1, 15
        li   x2, -4
        li   x6, 3
        add  x3, x1, x2
        sub  x4, x1, x2
        and  x5, x1, x2
        li   x7, 11
        bne  x3, x7, fail
        li   x7, 19
        bne  x4, x7, fail
        li   x7, 12
        bne  x5, x7, fail
        or   x3, x1, x2
        xor  x4, x1, x2
        li   x7, -1
        bne  x3, x7, fail
        li   x7, 0xFFFFFFF3
        bne  x4, x7, fail
        slt  x3, x1, x2
        sltu x4, x1, x2
        bne  x3, x0, fail
        li   x7, 1
        bne  x4, x7, fail
        sll  x3, x1, x6
        srl  x4, x2, x6
        sra  x5, x2, x6
        li   x7, 120
        bne  x3, x7, fail
        li   x7, 0x1FFFFFFF
        bne  x4, x7, fail
        li   x7, -1
        bne  x5, x7, fail

        li   x30, 8              # x0 is hard-wired to zero
        addi x0, x0, 7
        mv   x2, x0
        bnez x2, fail
        add  x0, x2, x2
        lui  x0, 0x1
        bnez x0, fail

        li   x30, 9              # loads / stores of every width
        li   x10, 16
        li   x1, 0x80FF7F01
        sw   x1, 0(x10)
        lw   x2, 0(x10)
        bne  x2, x1, fail
        lb   x3, 0(x10)
        li   x7, 1
        bne  x3, x7, fail
        lb   x4, 1(x10)
        li   x7, 0x7F
        bne  x4, x7, fail
        lb   x5, 2(x10)
        li   x7, -1
        bne  x5, x7, fail
        lb   x6, 3(x10)
        li   x7, 0xFFFFFF80
        bne  x6, x7, fail
        lbu  x8, 3(x10)
        li   x7, 0x80
        bne  x8, x7, fail
        lh   x8, 0(x10)
        li   x7, 0x7F01
        bne  x8, x7, fail
        lh   x9, 2(x10)
        li   x7, 0xFFFF80FF
        bne  x9, x7, fail
        lhu  x11, 2(x10)
        li   x7, 0x80FF
        bne  x11, x7, fail
        li   x12, 0xAB
        sb   x12, 5(x10)
        li   x13, 0xBEEF
        sh   x13, 10(x10)
        lw   x14, 4(x10)
        li   x7, 0xAB00
        bne  x14, x7, fail
        lw   x15, 8(x10)
        li   x7, 0xBEEF0000
        bne  x15, x7, fail

        li   x30, 10             # conditional branches (taken and not taken)
        li   x1, 5
        li   x2, 5
        li   x3, -1
        beq  x1, x2, b1
        j    fail
b1:     bne  x1, x2, fail
        blt  x3, x1, b2
        j    fail
b2:     bltu x3, x1, fail
        bge  x1, x3, b3
        j    fail
b3:     bgeu x3, x1, b4
        j    fail
b4:     bge  x3, x1, fail
        blt  x1, x3, fail
        bgeu x1, x3, fail
        bltu x1, x3, b5
        j    fail
b5:     bge  x1, x2, b6           # equal -> taken
        j    fail
b6:     blt  x1, x2, fail         # equal -> not taken

        li   x30, 11             # JAL / JALR and link values
        auipc x2, 0
        jal  x1, j1
        j    fail
j1:     addi x3, x2, 8
        bne  x1, x3, fail
        auipc x4, 0
        jalr x6, 13(x4)           # target = (x4+13)&~1 = x4+12
        j    fail
        addi x7, x4, 8
        bne  x6, x7, fail

        li   x30, 12             # EX->EX and MEM->EX forwarding
        li   x1, 1
        add  x2, x1, x1
        add  x3, x2, x2
        add  x4, x3, x3
        add  x5, x4, x1
        li   x7, 9
        bne  x5, x7, fail
        li   x7, 8
        bne  x4, x7, fail
        li   x1, 3
        addi x2, x1, 1
        addi x6, x0, 9
        add  x3, x2, x1
        li   x7, 7
        bne  x3, x7, fail

        li   x30, 13             # load-use hazard, store-data and branch forwarding
        li   x10, 64
        li   x1, 21
        sw   x1, 0(x10)
        lw   x2, 0(x10)
        add  x3, x2, x2
        li   x7, 42
        bne  x3, x7, fail
        lw   x4, 0(x10)
        sw   x4, 4(x10)           # store data comes from the load
        lw   x5, 4(x10)
        bne  x5, x1, fail
        lw   x6, 0(x10)
        beq  x6, x1, lu1          # branch operand comes from the load
        j    fail
lu1:    addi x8, x0, 7
        addi x9, x0, 7
        beq  x8, x9, lu2          # both branch operands forwarded
        j    fail
lu2:    lw   x11, 0(x10)
        lw   x12, 0(x10)
        add  x13, x11, x12        # one load in WB, one in MEM
        li   x7, 42
        bne  x13, x7, fail

        li   x30, 14             # loop: sum 1..10 (branch predictor warm-up)
        li   x1, 0
        li   x2, 10
loop1:  add  x1, x1, x2
        addi x2, x2, -1
        bnez x2, loop1
        li   x7, 55
        bne  x1, x7, fail

        li   x31, 0x600D
        ecall
fail:   li   x31, 0xBAD
        ecall
