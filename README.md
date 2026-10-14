# RISC-V RV32I 5-Stage Pipelined Processor

A synthesizable 5-stage (IF / ID / EX / MEM / WB) pipelined implementation of the
**RV32I** base integer ISA in plain Verilog-2001, with data-hazard detection and
forwarding, a 2-bit branch predictor, a self-checking testbench, a golden-model ISS,
and a Yosys synthesis flow.

**Tools:** Icarus Verilog 12, GTKWave (viewing only), Yosys 0.33, Python 3 (assembler / ISS / scripts).

```
IF ──► ID ──► EX ──► MEM ──► WB
 │     │  ▲    │  ▲    │       │
 │     │  │    └──┼────┴───────┘   forwarding (EX/MEM, MEM/WB → EX)
 │     │  └───────┴─── register file write-through (WB → ID)
 │     └── branch predict + JAL target (1 bubble if taken)
 └── PC mux:  EX redirect (mispredict/JALR) > ID redirect (JAL/predicted-taken) > PC+4
```

## Repository layout

```
rtl/        program_counter.v  instruction_memory.v  register_file.v  alu.v
            control_unit.v     pipeline_registers.v  hazard_unit.v     riscv32_pipeline.v
tb/         tb_riscv32_pipeline.v          self-checking testbench + performance monitor
sim/        run_tests.sh  run_random.sh  run_synth.sh        <- one-command flows
            asm.py (assembler)  iss.py (golden model)  gen_random.py
            programs/   *.S sources + assembled *.hex
            results/    CPI / utilisation / synthesis reports (generated, committed as evidence)
waveforms/  hazard_demo.vcd  isa_test.vcd      <- open with GTKWave
```
`sim/` also holds the tooling and the synthesis script, since the requested layout had no separate folder for them.
Module placement notes: `branch_predictor` lives in `hazard_unit.v` (control-hazard support) and
`data_memory` lives in `riscv32_pipeline.v`.

## Quick start

```bash
sudo apt install iverilog gtkwave yosys python3          # Ubuntu/Debian
bash sim/run_tests.sh waves      # all programs x {fwd on/off} x {BHT on/off}, CPI table, VCDs
bash sim/run_random.sh 300       # 300 random programs, RTL (4 configs) vs Python ISS
bash sim/run_synth.sh            # Yosys + Nangate45: area, timing, per-module breakdown
gtkwave waveforms/hazard_demo.vcd
```
Run one program by hand:
```bash
python3 sim/asm.py sim/programs/fibonacci.S -o sim/programs/fibonacci.hex
iverilog -g2012 -o sim/build/tb.vvp rtl/*.v tb/tb_riscv32_pipeline.v
vvp sim/build/tb.vvp +PROGRAM=sim/programs/fibonacci.hex +TRACE +VCD=waveforms/fib.vcd
# configuration:  iverilog ... -P tb_riscv32_pipeline.FORWARDING=0 -P tb_riscv32_pipeline.BRANCH_PRED=0
```
Testbench plusargs: `+PROGRAM=` `+VCD=` `+TRACE` (retire log) `+DUMPREGS`.
A program passes by ending with `x31 = 0x600D` then `ecall` (fail = `0x0BAD`, `x30` = failing check #).

## Microarchitecture

| Feature | Implementation |
|---|---|
| ISA | RV32I: all computational, load/store and control-flow instructions; `FENCE` = NOP; `ECALL`/`EBREAK` = halt (retires, stops the testbench) |
| Register file | 32 x 32-bit, x0 hard-wired 0, 2 read / 1 write port, **write-through** (WB→ID needs no stall) |
| Data hazards | EX-stage forwarding from EX/MEM and MEM/WB (MEM has priority); **1-cycle load-use stall**; `FORWARDING=0` removes bypasses and stalls in ID until the producer reaches WB |
| Control hazards | `JAL`: target in ID, 1 bubble. Conditional branch: 2-bit BHT (64 entries, indexed by PC[7:2], reset weakly-not-taken) predicted **in ID** (taken → 1 bubble), resolved in EX, mispredict → flush IF+ID (2 bubbles). `JALR`: resolved in EX (2 bubbles). `BRANCH_PRED=0` = static predict-not-taken |
| Memory | Harvard; async-read instruction ROM, sync-write data RAM (default 256 words each) with LB/LH/LW/LBU/LHU/SB/SH/SW |
| Parameters | `FORWARDING`, `BRANCH_PRED`, `IMEM_WORDS`, `DMEM_WORDS`, `BHT_ENTRIES` |

Stall/flush control: `PC.en = ~stall | ex_redirect`, `IF/ID.en = ~stall`, `IF/ID.flush = ex_redirect | id_redirect`,
`ID/EX.bubble = stall | ex_redirect` (EX redirect always wins over a stall).

## Verification

| Check | Result |
|---|---|
| `isa_test.S`: every RV32I instruction, taken/not-taken branches, JAL/JALR link values, sign/zero extension, EX→EX / MEM→EX / load-use / store-data / branch-operand forwarding, x0 writes | PASS in all 4 configurations |
| 5 further programs (fibonacci, array_sum, bubble_sort, branch_loop, hazard_demo) | PASS in all 4 configurations |
| **Differential test**: 300 random hazard-dense programs, final registers + data memory of the RTL vs `iss.py`, in all 4 configurations (1,200 runs) | all match |
| **Assembler check**: `asm.py` output compared word-for-word with GNU `riscv64-unknown-elf-as -march=rv32i` for all 6 programs | identical |
| **Cycle accounting** (built into the testbench, every run): `cycles = retired + 4 + stalls + control bubbles` | exact in every run |
| Sanity check of the checker: deliberately removing MEM/WB forwarding, and separately the load-use stall, | both detected by the random test within 20 seeds |

Limitations of the verification: no formal proof, no riscv-compliance suite, and no gate-level (post-synthesis) simulation.

## Results

All numbers below are measured from simulation (`sim/results/`). Programs are small (22–1,204 instructions), so
treat the figures as indicative of *these* workloads, not of general code.

### CPI with and without forwarding / branch prediction

| Program | Instrs | CPI fwd + BHT | CPI fwd, no BHT | CPI no fwd, BHT | CPI no fwd, no BHT | Fwd speed-up (cycles) |
|---|---|---|---|---|---|---|
| isa_test | 240 | 1.175 | 1.196 | 1.858 | 1.879 | 1.58x |
| hazard_demo | 22 | 1.636 | 1.591 | 2.500 | 2.455 | 1.53x |
| fibonacci | 109 | 1.257 | 1.404 | 1.853 | 2.000 | 1.47x |
| array_sum | 588 | 1.262 | 1.412 | 2.333 | 2.483 | 1.85x |
| bubble_sort | 1204 | 1.334 | 1.455 | 2.240 | 2.361 | 1.68x |
| branch_loop | 999 | 1.549 | 1.532 | 2.301 | 2.284 | 1.49x |

### Pipeline utilisation and stall cycles

Every cycle is either a retirement or a bubble: `cycles = retired + 4 (fill) + data stalls + control bubbles`.

| Program | Config | Cycles | Retire (useful) | Fill | Data stalls | Control bubbles |
|---|---|---|---|---|---|---|
| bubble_sort | fwd + BHT | 1606 | 1204 (75.0%) | 4 (0.2%) | 125 (7.8%) | 273 (17.0%) |
| bubble_sort | no fwd + BHT | 2697 | 1204 (44.6%) | 4 (0.1%) | 1216 (45.1%) | 273 (10.1%) |
| bubble_sort | fwd, no BHT | 1752 | 1204 (68.7%) | 4 (0.2%) | 125 (7.1%) | 419 (23.9%) |
| array_sum | fwd + BHT | 742 | 588 (79.2%) | 4 (0.5%) | 48 (6.5%) | 102 (13.7%) |
| array_sum | no fwd + BHT | 1372 | 588 (42.9%) | 4 (0.3%) | 678 (49.4%) | 102 (7.4%) |
| array_sum | fwd, no BHT | 830 | 588 (70.8%) | 4 (0.5%) | 48 (5.8%) | 190 (22.9%) |
| branch_loop | fwd + BHT | 1547 | 999 (64.6%) | 4 (0.3%) | 0 (0.0%) | 544 (35.2%) |
| branch_loop | no fwd + BHT | 2299 | 999 (43.5%) | 4 (0.2%) | 752 (32.7%) | 544 (23.7%) |
| branch_loop | fwd, no BHT | 1530 | 999 (65.3%) | 4 (0.3%) | 0 (0.0%) | 527 (34.4%) |

Observations
* **Forwarding** removes almost all data-hazard stalls (bubble_sort: 1216 → 125; the remainder are load-use stalls, which no forwarding network can hide).
* **The BHT helps on regular loops** (bubble_sort: mispredictions 209 → 39, 1.46 → 1.33 CPI) **but not on `branch_loop`**, which deliberately contains
  alternating and period-4 branches that a 2-bit counter predicts poorly, and tiny loops where a taken-predicted branch still pays a bubble.
* Because prediction happens in ID (there is no BTB), **even a correctly-predicted taken branch costs 1 bubble**. A BTB in IF would remove this
  but costs area. This is why the BHT gain is modest (1.0–1.16x).

### Area and timing after synthesis (Yosys 0.33 + ABC, Nangate 45 nm typical)

Core only (instruction/data memories black-boxed; the register file, pipeline registers, BHT, ALU and control are included).

| Configuration | Cell area (µm²) | Std cells | Flip-flops | Comb. critical path | Est. period | Est. Fmax |
|---|---|---|---|---|---|---|
| Forwarding + BHT (baseline) | 17,044 | 9,636 | 1,567 | 1,422 ps | 1,572 ps | ~636 MHz |
| No forwarding + BHT | 16,822 | 9,468 | 1,557 | 1,280 ps | 1,430 ps | ~700 MHz |
| Forwarding, no BHT | 15,452 | 8,631 | 1,438 | 1,478 ps | 1,628 ps | ~614 MHz |

Per-module area (hierarchical run, µm²): register_file 10,309 · branch_predictor 1,619 · top-level glue/muxes 1,442 · alu 1,284 ·
ex_mem_reg 1,079 · mem_wb_reg 1,029 · id_ex_reg 941 · if_id_reg 493 · program_counter 242 · control_unit 128 · hazard_unit 81.
(The per-module sum exceeds the flat figure because flattening allows cross-boundary optimisation.) The register file is ~60 % of the core, as expected for 1,024 flip-flops with two read muxes.

**Net effect on execution time** (cycles x estimated period): forwarding costs ~10 % in clock period (extra muxes in front of the ALU) and ~1.3 % area, but cuts
cycles by 1.5–1.85x, a net speed-up of **1.34–1.68x** per program (`sim/results/exec_time_table.md`). The BHT costs ~10 % area and gives 1.0–1.16x.

How to read the timing numbers (important caveats)
* ABC's `stime` gives the **combinational** delay with **no wire load or placement**. The "est. period" adds ~150 ps for DFF clk→Q (~100 ps) and setup (~50 ps), read from the
  Nangate liberty tables. This is a **pre-layout estimate, not signoff STA** (no OpenSTA run, no SDC, no hold analysis); real post-route timing would be slower.
* The critical path starts at the `MEM/WB.rd` register and is 36 gates deep (see `sim/results/synth/full_fast.log`). The pattern of its middle section is consistent with the
  forwarding comparators → forwarding mux → ALU adder carry chain → PC/redirect logic, i.e. the EX stage, but ABC does not name the end point.
* The "no BHT" row is slightly *slower* than the baseline. That is mapping noise (ABC's heuristic finds a different critical path); differences of ~5 % between rows should not be over-interpreted.
* Absolute area/frequency depend on the library; the relative comparisons are the useful part.

## Design notes / known limitations
* Misaligned loads/stores are not supported (aligned access assumed); no CSRs, interrupts, or privileged mode. `FENCE` is a NOP; CSR instructions decode as illegal NOPs.
* Instruction and data memories are separate (Harvard) and the data memory starts at address 0; programs therefore build their own data with stores.
* The BHT has no tags (aliasing between branches at the same PC[7:2] index is possible).
* Performance counters and the memory models are simulation-only (`ifdef SYNTHESIS`).
* Memories are behavioural; for an FPGA/ASIC flow replace them with block RAM / SRAM macros.

## Next steps
BTB in IF for zero-bubble taken branches · gshare predictor · M extension (MUL/DIV) · Zicsr + traps · riscv-arch-test compliance run · OpenSTA with a real SDC · gate-level simulation.
