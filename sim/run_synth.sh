#!/bin/bash
# Yosys synthesis + timing estimation (Nangate 45nm open cell library).
#   * instruction_memory / data_memory are black-boxed: only the CORE is measured
#   * area  : Yosys 'stat -liberty'
#   * timing: ABC 'stime' (combinational critical path, no wire load) -> see README
# Outputs: sim/results/synth/*.log, sim/results/synth_summary.md
# Usage: sim/run_synth.sh
cd "$(dirname "$0")/.." || exit 1
OUT=sim/results/synth; mkdir -p $OUT sim/build
LIB=sim/build/NangateOpenCellLibrary_typical.lib
if [ ! -s $LIB ]; then
  echo "Downloading Nangate 45nm liberty file (6.7 MB, one-time) ..."
  curl -sSL -o $LIB https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
    || { echo "download failed - place a liberty file at $LIB"; exit 1; }
fi
SRC="rtl/program_counter.v rtl/instruction_memory.v rtl/register_file.v rtl/alu.v rtl/control_unit.v rtl/pipeline_registers.v rtl/hazard_unit.v rtl/riscv32_pipeline.v"

# ABC script = Yosys' default liberty script + buffering/sizing + critical-path report
cat > sim/build/abc_timing.script <<'ABC'
strash
&get -n
&fraig -x
&put
scorr
dc2
dretime
strash
&get -n
&dch -f
&nf {D}
&put
buffer
upsize {D}
dnsize {D}
stime -p
ABC

run() {   # name fwd bp flatten(1/0) D_ps
  local name=$1 f=$2 b=$3 flat=$4 D=$5
  local fl=""; [ "$flat" = 1 ] && fl="-flatten"
  cat > sim/build/$name.ys <<YS
read_verilog -DSYNTHESIS $SRC
chparam -set FORWARDING $f -set BRANCH_PRED $b riscv32_pipeline
hierarchy -check -top riscv32_pipeline
blackbox *instruction_memory* *data_memory*
synth -top riscv32_pipeline $fl
dfflibmap -liberty $LIB
abc -liberty $LIB -D $D -script sim/build/abc_timing.script
opt_clean
tee -o $OUT/$name.stat stat -liberty $LIB
YS
  yosys -q -l $OUT/$name.log sim/build/$name.ys >/dev/null 2>&1 || { echo "yosys failed for $name (see $OUT/$name.log)"; return 1; }
}

echo "== synthesising (3 flat runs + 1 hierarchical run) =="
run full_fast   1 1 1 800  &
run nofwd_fast  0 1 1 800  &
run nobp_fast   1 0 1 800  &
run hier        1 1 0 800  &
wait

python3 - <<'PY'
import re, os
O='sim/results/synth'
def parse(n):
    log=open(f'{O}/{n}.log').read()
    stat=open(f'{O}/{n}.stat').read()
    # last ABC stime summary in the log is the (combinational) design
    d=[(float(m.group(1)),float(m.group(2))) for m in re.finditer(r'Area =\s+([\d.]+).*?Delay =\s+([\d.]+) ps',log)]
    delay=max(x[1] for x in d)
    cells=int(re.findall(r'Number of cells:\s+(\d+)',stat)[-1])
    ff=sum(int(x) for x in re.findall(r'DFF\w*\s+(\d+)',stat))
    area=float(re.findall(r'Chip area for (?:top )?module .*?: ([\d.]+)',stat)[-1])
    return area,delay,cells,ff,log
OVH=150.0   # ps: DFF_X1 clk->Q (~100) + setup (~50), from the liberty tables
rows=[]; 
names=[('full_fast','Forwarding + BHT   (baseline)'),
       ('nofwd_fast','No forwarding + BHT '),
       ('nobp_fast','Forwarding, no BHT ')]
md=["| Configuration | Cell area (um^2) | Std cells (incl. FFs) | Flip-flops | Comb. critical path (ps) | Est. period (ps) | Est. Fmax (MHz) |","|---|---|---|---|---|---|---|"]
for n,t in names:
    a,d,c,ff,_=parse(n)
    md.append(f"| {t} | {a:,.0f} | {c:,} | {ff:,} | {d:,.0f} | {d+OVH:,.0f} | {1e6/(d+OVH):,.0f} |")
# critical path of the main run
log=open(f'{O}/full_fast.log').read()
sp=re.findall(r'Start-point = (.*?)\.  End-point = (.*)',log)[-1]
start=re.sub(r'^pi\d+ \((.*)\)$',r'\1',sp[0].strip()).replace('\\\\','')
md+=["",f"Critical path of the baseline: ABC start-point `{start}` (see {O}/full_fast.log for the full gate-by-gate path)"]
open('sim/results/synth_summary.md','w').write('\n'.join(md)+'\n')
print('\n'.join(md))
PY
echo; echo "--- per-module breakdown (hierarchical run) ---"
awk '/^=== /{m=$2} /Chip area for module/{print m, $NF}' $OUT/hier.stat \
  | sed -e 's/.*branch_predictor/branch_predictor/' -e 's/.*hazard_unit.*[ ]/hazard_unit /' -e 's/\\//g' \
  | awk '{printf "%-20s %10.0f um^2\n",$1,$2}' | tee sim/results/synth_area_by_module.txt
