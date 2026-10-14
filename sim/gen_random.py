#!/usr/bin/env python3
"""Random RV32I program generator for differential testing (RTL vs iss.py).
Uses a small register pool (x1..x8) to maximise RAW hazards, loads/stores through a
fixed base register, forward branches, small loops, JAL and JALR.
Usage: gen_random.py <seed> > prog.S"""
import random, sys
seed = int(sys.argv[1]); r = random.Random(seed)
POOL = [f'x{i}' for i in range(1, 9)]
SRC  = ['x0'] + POOL
lines = []; lab = [0]
def L(s): lines.append('        ' + s)
def newlab(): lab[0] += 1; return f'L{lab[0]}'
ALU_R = ['add','sub','sll','slt','sltu','xor','srl','sra','or','and']
ALU_I = ['addi','slti','sltiu','xori','ori','andi']
def body_instr():
    k = r.random(); rd = r.choice(POOL + ['x0']); a = r.choice(SRC); b = r.choice(SRC)
    if k < 0.30:   L(f'{r.choice(ALU_R)} {rd}, {a}, {b}')
    elif k < 0.48: L(f'{r.choice(ALU_I)} {rd}, {a}, {r.randint(-2048,2047)}')
    elif k < 0.55: L(f'{r.choice(["slli","srli","srai"])} {rd}, {a}, {r.randint(0,31)}')
    elif k < 0.60: L(f'lui {rd}, {r.randint(0,0xFFFFF)}')
    elif k < 0.64: L(f'auipc {rd}, {r.randint(0,0xFFFFF)}')
    elif k < 0.78:
        op = r.choice(['lw','lh','lhu','lb','lbu']); al = {'lw':4,'lh':2,'lhu':2,'lb':1,'lbu':1}[op]
        L(f'{op} {rd}, {r.randrange(0,64,al)}(x9)')
    elif k < 0.88:
        op = r.choice(['sw','sh','sb']); al = {'sw':4,'sh':2,'sb':1}[op]
        L(f'{op} {b}, {r.randrange(0,64,al)}(x9)')
    elif k < 0.96:   # forward branch skipping 1-3 instructions
        t = newlab(); L(f'{r.choice(["beq","bne","blt","bge","bltu","bgeu"])} {a}, {b}, {t}')
        for _ in range(r.randint(1,3)):
            rd2 = r.choice(POOL); L(f'{r.choice(ALU_R)} {rd2}, {r.choice(SRC)}, {r.choice(SRC)}')
        lines.append(f'{t}:')
    elif k < 0.98:   # forward JAL
        t = newlab(); L(f'jal {r.choice(["x0","x10"])}, {t}')
        L(f'addi x1, x1, 99'); lines.append(f'{t}:')
    else:            # JALR over one instruction (auipc/jalr back to back)
        L('auipc x11, 0'); L(f'jalr {r.choice(["x0","x12"])}, 12(x11)'); L('addi x2, x2, 77')

L('li x9, 64')               # data base address (fixed)
for p in POOL: L(f'li {p}, {r.randint(-2**31, 2**31-1)}')
for _ in range(r.randint(30, 60)): body_instr()
for n in range(r.randint(1, 3)):       # a few counted loops with random bodies
    L(f'li x20, {r.randint(2, 12)}'); t = newlab(); lines.append(f'{t}:')
    for _ in range(r.randint(3, 10)): body_instr()
    L('addi x20, x20, -1'); L(f'bnez x20, {t}')
for _ in range(r.randint(5, 15)): body_instr()
L('ecall')
print('\n'.join(lines))
