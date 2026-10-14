# hazard_demo.S - short program for waveform viewing: RAW chain, load-use stall,
# JAL, predicted/mispredicted branches and JALR.  Result: x31 = 0x600D.
        li   x1, 5
        addi x2, x1, 3          # EX->EX forwarding   (x1)
        add  x3, x2, x1         # EX->EX (x2) + MEM->EX (x1)
        sw   x3, 0(x0)
        lw   x4, 0(x0)
        add  x5, x4, x4         # load-use -> 1 stall cycle
        jal  x0, skip           # JAL: 1 bubble
        li   x5, 99             # skipped
skip:   li   x6, 3
cnt:    addi x6, x6, -1
        bnez x6, cnt            # loop branch: mispredicts initially, then learns
        auipc x7, 0
        jalr x0, 12(x7)         # JALR: 2 bubbles
        li   x5, 77             # skipped
        li   x8, 26
        li   x31, 0x600D
        bne  x5, x8, bad
        j    done
bad:    li   x31, 0xBAD
done:   ecall
