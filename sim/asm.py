#!/usr/bin/env python3
"""Minimal RV32I assembler (no dependencies).

Usage: asm.py prog.S [-o prog.hex] [--list]
Output: one 32-bit word per line (hex), suitable for $readmemh.
Supports all RV32I instructions (except FENCE/CSR), labels, '#' and '//' comments,
.word, and pseudo-ops: nop li mv not neg j jr ret beqz bnez bltz bgez blez bgtz
bgt ble bgtu bleu seqz snez
"""
import re, sys

ABI = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
       'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
       's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
       't3':28,'t4':29,'t5':30,'t6':31}
def reg(s):
    s = s.strip()
    if s in ABI: return ABI[s]
    m = re.fullmatch(r'x(\d+)', s)
    if m and int(m.group(1)) < 32: return int(m.group(1))
    raise ValueError(f"bad register '{s}'")

def num(s):
    return int(s.strip(), 0)

R  = {'add':(0,0),'sub':(0,0x20),'sll':(1,0),'slt':(2,0),'sltu':(3,0),'xor':(4,0),
      'srl':(5,0),'sra':(5,0x20),'or':(6,0),'and':(7,0)}
I  = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
SH = {'slli':(1,0),'srli':(5,0),'srai':(5,0x20)}
LD = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
ST = {'sb':0,'sh':1,'sw':2}
BR = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def enc_r(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm,rs1,f3,rd,op):
    if not -2048 <= imm <= 2047: raise ValueError(f"imm {imm} out of 12-bit range")
    return ((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm,rs2,rs1,f3,op):
    if not -2048 <= imm <= 2047: raise ValueError(f"imm {imm} out of 12-bit range")
    imm &= 0xFFF
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op
def enc_b(off,rs2,rs1,f3):
    if off & 1 or not -4096 <= off <= 4094: raise ValueError(f"branch offset {off} out of range")
    o = off & 0x1FFF
    return (((o>>12)&1)<<31)|(((o>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((o>>1)&0xF)<<8)|(((o>>11)&1)<<7)|0x63
def enc_u(imm20,rd,op): return ((imm20&0xFFFFF)<<12)|(rd<<7)|op
def enc_j(off,rd):
    if off & 1 or not -(1<<20) <= off < (1<<20): raise ValueError(f"jal offset {off} out of range")
    o = off & 0x1FFFFF
    return (((o>>20)&1)<<31)|(((o>>1)&0x3FF)<<21)|(((o>>11)&1)<<20)|(((o>>12)&0xFF)<<12)|(rd<<7)|0x6F

def split_ops(s):
    return [t.strip() for t in s.split(',')] if s.strip() else []

def li_words(rd, val):
    val &= 0xFFFFFFFF
    sval = val - (1<<32) if val & 0x80000000 else val
    if -2048 <= sval <= 2047: return [('addi', rd, 0, sval)]
    lo = sval & 0xFFF
    if lo >= 0x800: lo -= 0x1000
    hi = ((val - lo) >> 12) & 0xFFFFF
    if lo == 0: return [('lui', rd, hi)]
    return [('lui', rd, hi), ('addi', rd, rd, lo)]

def expand(mn, ops):
    """Expand pseudo-ops into lists of (mnemonic, operand strings)."""
    o = ops
    if mn == 'nop':  return [('addi', ['x0','x0','0'])]
    if mn == 'mv':   return [('addi', [o[0],o[1],'0'])]
    if mn == 'not':  return [('xori', [o[0],o[1],'-1'])]
    if mn == 'neg':  return [('sub',  [o[0],'x0',o[1]])]
    if mn == 'seqz': return [('sltiu',[o[0],o[1],'1'])]
    if mn == 'snez': return [('sltu', [o[0],'x0',o[1]])]
    if mn == 'j':    return [('jal',  ['x0',o[0]])]
    if mn == 'jr':   return [('jalr', ['x0',o[0],'0'])]
    if mn == 'ret':  return [('jalr', ['x0','ra','0'])]
    if mn == 'beqz': return [('beq',  [o[0],'x0',o[1]])]
    if mn == 'bnez': return [('bne',  [o[0],'x0',o[1]])]
    if mn == 'bltz': return [('blt',  [o[0],'x0',o[1]])]
    if mn == 'bgez': return [('bge',  [o[0],'x0',o[1]])]
    if mn == 'blez': return [('bge',  ['x0',o[0],o[1]])]
    if mn == 'bgtz': return [('blt',  ['x0',o[0],o[1]])]
    if mn == 'bgt':  return [('blt',  [o[1],o[0],o[2]])]
    if mn == 'ble':  return [('bge',  [o[1],o[0],o[2]])]
    if mn == 'bgtu': return [('bltu', [o[1],o[0],o[2]])]
    if mn == 'bleu': return [('bgeu', [o[1],o[0],o[2]])]
    if mn == 'li':
        rd = reg(o[0]); v = num(o[1])
        out = []
        for w in li_words(rd, v):
            if w[0] == 'addi': out.append(('addi', [f'x{w[1]}', f'x{w[2]}', str(w[3])]))
            else:              out.append(('lui',  [f'x{w[1]}', str(w[2])]))
        return out
    return [(mn, o)]

def assemble(text):
    items = []           # (addr, mn, ops, srcline)
    labels = {}
    addr = 0
    for ln, raw in enumerate(text.splitlines(), 1):
        line = re.split(r'#|//', raw)[0].strip()
        while True:
            m = re.match(r'^([A-Za-z_.][\w.]*)\s*:\s*(.*)$', line)
            if not m: break
            labels[m.group(1)] = addr; line = m.group(2).strip()
        if not line: continue
        if line.startswith('.'):
            parts = line.split(None, 1)
            if parts[0] == '.word':
                for w in split_ops(parts[1]):
                    items.append((addr, '.word', [w], raw.strip(), ln)); addr += 4
            continue   # ignore other directives (.text, .globl ...)
        parts = line.split(None, 1)
        mn = parts[0].lower(); ops = split_ops(parts[1]) if len(parts) > 1 else []
        try:
            for emn, eops in expand(mn, ops):
                items.append((addr, emn, eops, raw.strip(), ln)); addr += 4
        except Exception as e:
            raise SystemExit(f"line {ln}: {e}: {raw.strip()}")

    def val(s, pc=None):
        s = s.strip()
        if s in labels: return labels[s] - pc if pc is not None else labels[s]
        return num(s)

    words = []
    for addr, mn, o, src, ln in items:
        try:
            if mn == '.word':     w = num(o[0]) & 0xFFFFFFFF
            elif mn in R:         f3,f7 = R[mn]; w = enc_r(f7,reg(o[2]),reg(o[1]),f3,reg(o[0]),0x33)
            elif mn in I:         w = enc_i(num(o[2]),reg(o[1]),I[mn],reg(o[0]),0x13)
            elif mn in SH:
                f3,f7 = SH[mn]; sh = num(o[2])
                if not 0 <= sh < 32: raise ValueError("shift amount")
                w = enc_r(f7,sh,reg(o[1]),f3,reg(o[0]),0x13)
            elif mn in LD or mn in ST or mn == 'jalr' and '(' in o[-1]:
                m = re.fullmatch(r'(.*)\((\w+)\)', o[-1].strip())
                imm = num(m.group(1)) if m.group(1).strip() else 0
                if mn in LD:   w = enc_i(imm,reg(m.group(2)),LD[mn],reg(o[0]),0x03)
                elif mn in ST: w = enc_s(imm,reg(o[0]),reg(m.group(2)),ST[mn],0x23)
                else:          w = enc_i(imm,reg(m.group(2)),0,reg(o[0]),0x67)
            elif mn == 'jalr':    w = enc_i(num(o[2]),reg(o[1]),0,reg(o[0]),0x67)
            elif mn in BR:        w = enc_b(val(o[2],addr),reg(o[1]),reg(o[0]),BR[mn])
            elif mn == 'jal':
                if len(o) == 1: o = ['ra', o[0]]
                w = enc_j(val(o[1],addr),reg(o[0]))
            elif mn == 'lui':     w = enc_u(num(o[1]),reg(o[0]),0x37)
            elif mn == 'auipc':   w = enc_u(num(o[1]),reg(o[0]),0x17)
            elif mn == 'ecall':   w = 0x00000073
            elif mn == 'ebreak':  w = 0x00100073
            else: raise ValueError(f"unknown instruction '{mn}'")
        except SystemExit: raise
        except Exception as e:
            raise SystemExit(f"line {ln}: {e}: {src}")
        words.append((addr, w, src))
    return words

if __name__ == '__main__':
    args = sys.argv[1:]
    if not args: sys.exit(__doc__)
    out = None; lst = False; src = None
    i = 0
    while i < len(args):
        if args[i] == '-o': out = args[i+1]; i += 2
        elif args[i] == '--list': lst = True; i += 1
        else: src = args[i]; i += 1
    words = assemble(open(src).read())
    out = out or re.sub(r'\.\w+$', '', src) + '.hex'
    with open(out, 'w') as f:
        for a, w, s in words: f.write(f'{w:08x}\n')
    if lst:
        with open(re.sub(r'\.hex$', '', out) + '.lst', 'w') as f:
            for a, w, s in words: f.write(f'{a:04x}: {w:08x}  {s}\n')
