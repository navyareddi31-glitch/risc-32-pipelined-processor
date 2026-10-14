# bubble_sort.S - sort 16 words in data memory, then verify ascending order
        li   x10, 0             # base address
        li   x11, 16            # n
        li   x1, 0
        li   x2, 37             # LCG-ish data: v = (v*5 + 17) & 0xFF
fill:   slli x3, x1, 2
        add  x3, x3, x10
        sw   x2, 0(x3)
        slli x4, x2, 2
        add  x2, x2, x4         # v*5
        addi x2, x2, 17
        andi x2, x2, 0xFF
        addi x1, x1, 1
        blt  x1, x11, fill

        addi x12, x11, -1       # outer = n-1
outer:  li   x1, 0              # j
        li   x13, 0             # swapped?
inner:  slli x3, x1, 2
        add  x3, x3, x10
        lw   x4, 0(x3)
        lw   x5, 4(x3)
        ble  x4, x5, noswap     # data-dependent branch
        sw   x5, 0(x3)
        sw   x4, 4(x3)
        li   x13, 1
noswap: addi x1, x1, 1
        blt  x1, x12, inner
        addi x12, x12, -1
        beqz x13, check
        bgtz x12, outer

check:  li   x1, 0
        addi x12, x11, -1
        li   x31, 0x600D
chk:    slli x3, x1, 2
        add  x3, x3, x10
        lw   x4, 0(x3)
        lw   x5, 4(x3)
        bgt  x4, x5, bad
        addi x1, x1, 1
        blt  x1, x12, chk
        j    done
bad:    li   x31, 0xBAD
done:   ecall
