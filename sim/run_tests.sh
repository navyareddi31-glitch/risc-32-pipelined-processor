#!/bin/bash
# Functional regression + CPI / utilisation analysis.
#   for every program in sim/programs/*.S and for FORWARDING x BRANCH_PRED in {0,1}^2:
#   assemble -> simulate -> check PASS -> collect cycle / stall / flush statistics.
# Outputs: sim/results/cpi_results.csv, sim/results/cpi_table.md, sim/results/logs/*.log
# Optional: sim/run_tests.sh waves   -> also dumps waveforms/hazard_demo.vcd
cd "$(dirname "$0")/.." || exit 1
B=sim/build; R=sim/results; mkdir -p $B $R/logs waveforms
PROGS=${PROGS:-"isa_test hazard_demo fibonacci array_sum bubble_sort branch_loop"}
rc=0
for p in $PROGS; do python3 sim/asm.py sim/programs/$p.S -o sim/programs/$p.hex --list || exit 1; done
for f in 0 1; do for b in 0 1; do
  iverilog -g2012 -P tb_riscv32_pipeline.FORWARDING=$f -P tb_riscv32_pipeline.BRANCH_PRED=$b \
           -o $B/tb_f${f}_b${b}.vvp rtl/*.v tb/tb_riscv32_pipeline.v || exit 1
done; done

echo "program,forwarding,branch_pred,result,cycles,instrs,cpi,ipc,stalls,ex_flush,id_flush,ctrl_bubbles,branches,taken,mispred,loads,stores" > $R/cpi_results.csv
printf "%-13s %-4s %-4s %-6s %7s %7s %6s %6s %7s %7s %8s\n" program fwd bp result cycles instrs CPI IPC stalls ctrlbub mispred
for p in $PROGS; do for f in 1 0; do for b in 1 0; do
  log=$R/logs/${p}_f${f}_b${b}.log
  vvp -n $B/tb_f${f}_b${b}.vvp +PROGRAM=sim/programs/$p.hex > $log
  res=$(grep -o "RESULT: [A-Z]*" $log | cut -d' ' -f2)
  st=$(grep '^STATS' $log)
  g() { echo "$st" | grep -o "$1=[0-9.]*" | cut -d= -f2; }
  grep -q "ACCOUNTING: OK" $log || { echo "!! cycle accounting mismatch: $p f=$f b=$b"; rc=1; }
  [ "$res" = "PASS" ] || { echo "!! $p f=$f b=$b : $res"; rc=1; }
  echo "$p,$f,$b,$res,$(g cycles),$(g instrs),$(g cpi),$(g ipc),$(g stalls),$(g ex_flush),$(g id_flush),$(g ctrl_bubbles),$(g branches),$(g taken),$(g mispred),$(g loads),$(g stores)" >> $R/cpi_results.csv
  printf "%-13s %-4s %-4s %-6s %7s %7s %6s %6s %7s %7s %8s\n" $p $f $b $res $(g cycles) $(g instrs) $(g cpi) $(g ipc) $(g stalls) $(g ctrl_bubbles) $(g mispred)
done; done; done

# markdown summary
python3 - <<'PY'
import csv
rows = list(csv.DictReader(open('sim/results/cpi_results.csv')))
progs = []; [progs.append(r['program']) for r in rows if r['program'] not in progs]
def get(p,f,b,k): return [r for r in rows if r['program']==p and r['forwarding']==f and r['branch_pred']==b][0][k]
out = ["| Program | Instrs | CPI fwd+BP | CPI fwd, no BP | CPI no fwd, BP | CPI no fwd, no BP | Fwd speed-up (BP on) |",
       "|---|---|---|---|---|---|---|"]
for p in progs:
    c = {(f,b): float(get(p,f,b,'cpi')) for f in '01' for b in '01'}
    out.append(f"| {p} | {get(p,'1','1','instrs')} | {c['1','1']:.3f} | {c['1','0']:.3f} | {c['0','1']:.3f} | {c['0','0']:.3f} | {c['0','1']/c['1','1']:.2f}x |")
open('sim/results/cpi_table.md','w').write('\n'.join(out)+'\n')
print(); print('\n'.join(out))
PY

if [ "$1" = "waves" ]; then
  vvp -n $B/tb_f1_b1.vvp +PROGRAM=sim/programs/hazard_demo.hex +VCD=waveforms/hazard_demo.vcd | grep RESULT
  vvp -n $B/tb_f1_b1.vvp +PROGRAM=sim/programs/isa_test.hex +VCD=waveforms/isa_test.vcd | grep RESULT
fi
[ $rc -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $rc
