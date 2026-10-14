# fibonacci.S - iterative fib(20) = 6765; long back-to-back dependency chain
        li   x1, 0              # a
        li   x2, 1              # b
        li   x3, 20             # n
fib:    add  x4, x1, x2         # t = a + b   (needs b from previous iteration)
        mv   x1, x2
        mv   x2, x4
        addi x3, x3, -1
        bnez x3, fib
        li   x5, 6765
        li   x31, 0x600D
        beq  x1, x5, done
        li   x31, 0xBAD
done:   ecall
