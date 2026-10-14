# branch_loop.S - nested loops + alternating / periodic branches (predictor test)
# counts: outer 12 x inner 10 iterations = 120 ; every 2nd inner iteration adds 1 (60)
# every 4th adds 2 (30*... see below) -> verified by self check using a second counter
        li   x1, 0              # i
        li   x2, 12
        li   x5, 0              # total iterations
        li   x6, 0              # odd-iteration count
        li   x7, 0              # multiple-of-4 count
outer:  li   x3, 0              # j
        li   x4, 10
inner:  addi x5, x5, 1
        andi x8, x3, 1
        beqz x8, even           # alternating pattern
        addi x6, x6, 1
even:   andi x8, x3, 3
        bnez x8, not4           # period-4 pattern
        addi x7, x7, 1
not4:   addi x3, x3, 1
        blt  x3, x4, inner
        addi x1, x1, 1
        blt  x1, x2, outer
        # totals: 120 iterations, odd j: 5 per outer -> 60, j%4==0: j=0,4,8 -> 3 per outer -> 36
        li   x31, 0x600D
        li   x9, 120
        bne  x5, x9, bad
        li   x9, 60
        bne  x6, x9, bad
        li   x9, 36
        bne  x7, x9, bad
        j    done
bad:    li   x31, 0xBAD
done:   ecall
