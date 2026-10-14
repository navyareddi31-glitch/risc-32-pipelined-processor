#!/bin/bash
# Differential test: N random programs, RTL (all 4 configs) vs Python ISS.
# Usage: sim/run_random.sh [N] [first_seed]
cd "$(dirname "$0")/.." || exit 1
N=${1:-200}; S0=${2:-1}; B=sim/build
mkdir -p $B
for f in 0 1; do for b in 0 1; do
  iverilog -g2012 -P tb_riscv32_pipeline.FORWARDING=$f -P tb_riscv32_pipeline.BRANCH_PRED=$b \
           -o $B/rnd_f${f}_b${b}.vvp rtl/*.v tb/tb_riscv32_pipeline.v || exit 1
done; done
fail=0
for ((s=S0; s<S0+N; s++)); do
  python3 sim/gen_random.py $s > $B/rnd.S
  python3 sim/asm.py $B/rnd.S -o $B/rnd.hex || { echo "seed $s: asm error"; fail=1; continue; }
  python3 sim/iss.py $B/rnd.hex | grep -E '^(REG|MEM)' > $B/rnd_iss.txt
  for f in 0 1; do for b in 0 1; do
    vvp -n $B/rnd_f${f}_b${b}.vvp +PROGRAM=$B/rnd.hex +DUMPREGS > $B/rnd_rtl.log
    grep -E '^(REG|MEM)' $B/rnd_rtl.log > $B/rnd_rtl.txt
    if ! diff -q $B/rnd_iss.txt $B/rnd_rtl.txt >/dev/null || ! grep -q "ACCOUNTING: OK" $B/rnd_rtl.log; then
      echo "MISMATCH seed=$s fwd=$f bp=$b"; fail=1
    fi
  done; done
done
[ $fail -eq 0 ] && echo "RANDOM TEST: all $N programs x 4 configs match the ISS" || echo "RANDOM TEST: FAILURES"
exit $fail
