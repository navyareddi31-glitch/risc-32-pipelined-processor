#!/usr/bin/env python3
"""RV32I instruction-set simulator used as the golden reference model.
Usage: iss.py prog.hex [--dmem-words N]   -> prints REG/MEM dump in the same
format as the testbench's +DUMPREGS, plus 'ISS retired=<n>'."""
import sys
M = 0xFFFFFFFF
def s32(x): x &= M; return x - (1<<32) if x & 0x80000000 else x
def sext(x, b): x &= (1<<b)-1; return x - (1<<b) if x >> (b-1) else x

def run(words, imem_words=256, dmem_words=256, max_steps=2_000_000):
    imem = list(words) + [0x13]*(imem_words-len(words))
    dmem = bytearray(4*dmem_words)
    x = [0]*32; pc = 0; n = 0
    while n < max_steps:
        ins = imem[(pc >> 2) % imem_words]; n += 1
        op = ins & 0x7F; rd = (ins>>7)&31; f3 = (ins>>12)&7; rs1 = (ins>>15)&31
        rs2 = (ins>>20)&31; f7 = ins>>25
        a = x[rs1]; b = x[rs2]; npc = (pc+4) & M; wr = None
        immi = sext(ins>>20, 12)
        if   op == 0x37: wr = ins & 0xFFFFF000
        elif op == 0x17: wr = (pc + (ins & 0xFFFFF000)) & M
        elif op == 0x6F:
            o = ((ins>>31)<<20)|(((ins>>12)&0xFF)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&0x3FF)<<1)
            wr = (pc+4) & M; npc = (pc + sext(o,21)) & M
        elif op == 0x67: wr = (pc+4) & M; npc = ((a + immi) & M) & ~1
        elif op == 0x63:
            o = ((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&0x3F)<<5)|(((ins>>8)&0xF)<<1)
            c = {0:a==b,1:a!=b,4:s32(a)<s32(b),5:s32(a)>=s32(b),6:a<b,7:a>=b}[f3]
            if c: npc = (pc + sext(o,13)) & M
        elif op == 0x03:
            ad = (a + immi) & M & (4*dmem_words-1)
            sz = {0:1,1:2,2:4,4:1,5:2}[f3]
            v = int.from_bytes(dmem[ad:ad+sz], 'little')
            wr = (sext(v, 8*sz) & M) if f3 in (0,1) else v
        elif op == 0x23:
            ad = (a + sext(((ins>>25)<<5)|((ins>>7)&31), 12)) & M & (4*dmem_words-1)
            sz = {0:1,1:2,2:4}[f3]
            dmem[ad:ad+sz] = (b & ((1<<(8*sz))-1)).to_bytes(sz, 'little')
        elif op in (0x13, 0x33):
            y = immi if op == 0x13 else b
            sh = y & 31
            if f3 == 0:   wr = (a - b) if (op == 0x33 and f7 == 0x20) else (a + y)
            elif f3 == 1: wr = a << sh
            elif f3 == 2: wr = int(s32(a) < s32(y))
            elif f3 == 3: wr = int(a < (y & M))
            elif f3 == 4: wr = a ^ y
            elif f3 == 5: wr = (s32(a) >> sh) if (ins>>30)&1 else (a >> sh)
            elif f3 == 6: wr = a | y
            else:         wr = a & y
        elif op == 0x73 and f3 == 0:
            break
        if wr is not None and rd: x[rd] = wr & M
        pc = npc
    return x, dmem, n

if __name__ == '__main__':
    words = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
    dw = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[2] == '--dmem-words' else 256
    x, dmem, n = run(words, dmem_words=dw)
    for i in range(32): print(f"REG x{i}={x[i]:08x}")
    for i in range(64): print(f"MEM {i}={int.from_bytes(dmem[4*i:4*i+4],'little'):08x}")
    print(f"ISS retired={n}")
