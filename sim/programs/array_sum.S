# array_sum.S - fill a 48-word array with i*3+1, sum it back (load-use pattern)
# expected sum = 3*(0+...+47) + 48 = 3*1128 + 48 = 3432
        li   x10, 0             # base
        li   x11, 48            # count
        li   x1, 0              # i
        li   x2, 1              # value
fill:   slli x3, x1, 2
        add  x3, x3, x10
        sw   x2, 0(x3)
        addi x2, x2, 3
        addi x1, x1, 1
        blt  x1, x11, fill
        li   x1, 0
        li   x4, 0              # sum
sumlp:  slli x3, x1, 2
        add  x3, x3, x10
        lw   x5, 0(x3)
        add  x4, x4, x5         # load-use dependency
        addi x1, x1, 1
        blt  x1, x11, sumlp
        li   x6, 3432
        li   x31, 0x600D
        beq  x4, x6, done
        li   x31, 0xBAD
done:   ecall
