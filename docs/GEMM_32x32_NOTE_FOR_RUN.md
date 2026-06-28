# README - GEMM 32x32 KV260 Debug and Run Notes

## 1. Purpose

This README records the current debug status of the **GEMM 32x32 INT8 accelerator on KV260**, the issues that were found, the working run flow, and important notes for future developers.

This file is written to prevent future developers from repeating the same mistakes, such as:

- Running the application from the Vitis GUI without properly programming the FPGA or initializing PS-PL access.
- Hanging at an AXI-Lite register read such as `READ DMA0 status...`.
- Using stale bitstreams, stale XSA files, or stale Vitis platforms.
- Confusing the old address map with the current address map.
- Confusing 24x24 settings with the current 32x32 design.
- Starting DMA channels in the wrong order.
- Forgetting cache maintenance before and after DMA transfers.
- Reusing old software workarounds that are no longer required.

---

## 2. Current system status

The current project has successfully run a **32x32 INT8 GEMM hardware test on KV260** using AXI DMA.

Tested configuration:

```text
Board / SoC      : Xilinx Kria KV260 / K26
Tools            : Vivado 2022.2 + Vitis 2022.2
Processor        : Cortex-A53 #0, bare-metal
Matrix size      : 32 x 32
Data type        : signed INT8
Input A size     : 32 * 32 = 1024 bytes
Input B size     : 32 * 32 = 1024 bytes
Output C size    : 32 * 32 = 1024 bytes
AXIS data width  : 256-bit = 32 bytes/beat
AXI-Lite width   : 32-bit control register
```

Successful hardware log:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
```

Meaning:

```text
PS AXI-Lite -> DMA/GEMM control     : OK
DMA0 MM2S -> feature_axis           : OK
DMA1 MM2S -> weight_axis            : OK
GEMM_DSP_IP_0 32x32 compute         : OK for this test
GEMM result -> DMA2 S2MM -> DDR     : OK
Software result == Hardware result  : PASS
```

---

## 3. Current hardware architecture

The system uses three AXI DMA IPs:

```text
DMA0: MM2S only
  DDR -> DMA0 -> GEMM_DSP_IP_0/feature_axis

DMA1: MM2S only
  DDR -> DMA1 -> GEMM_DSP_IP_0/weight_axis

DMA2: S2MM only
  GEMM_DSP_IP_0/result_axis -> DMA2 -> DDR
```

AXI-Lite control path:

```text
ZynqMP PS M_AXI_HPM -> AXI interconnect -> DMA0 S_AXI_LITE
                                        -> DMA1 S_AXI_LITE
                                        -> DMA2 S_AXI_LITE
                                        -> GEMM_DSP_IP_0 S_AXI
```

DDR data path:

```text
DMA M_AXI ports -> SmartConnect / Interconnect -> PS DDR port -> DDR
```

Clock and reset:

```text
All PL clocks should use the same PL clock, typically pl_clk0 around 100 MHz.
All active-low PL resets should come from the processor system reset block:
rst_ps8_0_96M/peripheral_aresetn
```

Important reset note:

```text
If the reset block has a dcm_locked input, it must be driven correctly.
If dcm_locked is left floating or held low, PL reset may remain asserted and AXI-Lite may hang.
```

---

## 4. Current address map

The current `xparameters.h` uses this address map:

```c
#define MM_ADDR             XPAR_GEMM_DSP_IP_0_BASEADDR  // 0xA0000000
#define FEATURE_DMA_ADDR    XPAR_AXI_DMA_0_BASEADDR      // 0xA0010000
#define WEIGHT_DMA_ADDR     XPAR_AXI_DMA_1_BASEADDR      // 0xA0020000
#define RESULT_DMA_ADDR     XPAR_AXI_DMA_2_BASEADDR      // 0xA0030000
```

Current base addresses:

```text
GEMM_DSP_IP_0      : 0xA0000000
AXI DMA0 feature   : 0xA0010000
AXI DMA1 weight    : 0xA0020000
AXI DMA2 result    : 0xA0030000
```

Do not manually edit `xparameters.h`.

If the Vivado block design is changed or a new XSA is exported, always check the regenerated `xparameters.h` and update the software macros accordingly.

---

## 5. GEMM register map

The GEMM AXI-Lite base address is:

```c
#define MM_ADDR 0xA0000000
```

Register offsets:

```c
#define SHIFT_ADDR          (MM_ADDR + 0x00)
#define FL_ADDR             (MM_ADDR + 0x04)
#define FWBN_ADDR           (MM_ADDR + 0x08)
#define WWBN_ADDR           (MM_ADDR + 0x0C)
```

Meaning:

| Offset | Register | Meaning |
|---:|---|---|
| `0x00` | Shift/status | Write shift, read shift/status |
| `0x04` | `F_length` / row count | Number of output rows |
| `0x08` | `F_width_block_num` / K block count | Number of K blocks |
| `0x0C` | `W_width_block_num` / N block count | Number of N blocks |

For 32x32:

```c
shift             = 0
F_length          = 32
F_width_block_num = 1
W_width_block_num = 1
```

Status bits in the shift/status register:

```text
bit [9:0]   shift
bit [16]    clear done request when writing
bit [24]    busy
bit [25]    done
bit [26]    idle
```

Example readback from a successful run:

```text
Readback SHIFT raw = 0x04000000, shift=0
Readback FL        = 0x00000020
Readback FWBN      = 0x00000001
Readback WWBN      = 0x00000001
```

`0x04000000` means the shift value is 0 and the idle status bit is set.

---

## 6. Issue 1: Vitis GUI run can hang at AXI-Lite read

### Symptom

The UART log stops here:

```text
===== GEMM 32x32 DMA TEST START =====
...
stage 0: bus smoke test
READ DMA0 status...
```

The application does not print:

```text
DMA0 MM2S status = ...
```

### What is happening

The CPU is stuck at this type of access:

```c
u32 dma0 = Xil_In32(FEATURE_MM2S_DMASR);
```

This is equivalent to reading address:

```text
0xA0010004
```

If the FPGA fabric is not programmed or PS-PL access is not initialized correctly, the AXI-Lite slave does not respond, so the Cortex-A53 waits forever.

### Important conclusion

This is not a GEMM compute bug and not a random C software bug.

It means:

```text
The software is touching a PL AXI-Lite address before the PL/PS-PL path is ready.
```

The design has already been proven to run correctly when launched with the correct XSCT sequence.

---

## 7. Issue 2: XSCT `mrd` may report a blocked PL address

During debug, this error may appear:

```text
Memory read error at 0xA0000000.
Blocked address 0xA0000000.
PL AXI slave ports access is not allowed.
This address has not been added to the memory map.
```

This is a debugger memory-map restriction from XSCT, not necessarily a hardware failure.

The real proof is the running A53 application. In the successful run, the application itself could read the registers:

```text
DMA0 MM2S status = 0x00000001
DMA1 MM2S status = 0x00000001
DMA2 S2MM status = 0x00000001
GEMM status = 0x04000000
```

Then DMA completed and the compare passed.

If needed, add the PL memory range to the debugger memory map:

```tcl
targets -set -filter {name =~ "Cortex-A53 #0"}
memmap -addr 0xA0000000 -size 0x00040000 -flags rw
mrd 0xA0000000
mrd 0xA0010004
mrd 0xA0020004
mrd 0xA0030034
```

This is only for debugger convenience. It is not required for the application to run.

---

## 8. Correct XSCT run script

The Vitis GUI launch flow may not reliably run all required initialization steps for this custom KV260 design.

Use the following XSCT script as the **known-good run flow**.

Save it as:

```text
E:/VITIS_2022/run_gemm_dsp.tcl
```

or paste it directly into the XSCT Console.

```tcl
# ============================================================
# Known-good KV260 GEMM_DSP run script
# Vivado/Vitis 2022.2
# ============================================================

set BIT_FILE "E:/Everything_with_VIVADO/GEMM_final_DSP/GEMM_final_DSP.runs/impl_1/GEMM_DSP_BD_wrapper.bit"
set PSU_INIT "E:/VITIS_2022/GEMM_final_DSP/hw/psu_init.tcl"
set ELF_FILE "E:/VITIS_2022/GEMM_DSP/Debug/GEMM_DSP.elf"

catch {disconnect}
connect
targets

puts "===== RESET SYSTEM ====="
targets -set -filter {name =~ "PSU"}
rst -system
after 8000

puts "===== PROGRAM FPGA ====="
fpga -file $BIT_FILE
after 3000

puts "===== PSU INIT ====="
source $PSU_INIT
psu_init
after 2000

puts "===== REMOVE PS-PL ISOLATION ====="
catch {psu_ps_pl_isolation_removal}
catch {psu_ps_pl_reset_config}
catch {psu_post_config}
after 2000

puts "===== RESET A53 #0 ====="
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor
after 1000

puts "===== DOWNLOAD ELF ====="
dow $ELF_FILE
after 1000

puts "===== RUN APP ====="
con
```

To run it from XSCT:

```tcl
source E:/VITIS_2022/run_gemm_dsp.tcl
```

Before running after a board power cycle, it is recommended to:

```text
1. Open the UART serial terminal at 115200 baud.
2. Power-cycle the KV260.
3. Open XSCT Console.
4. Run the script above.
```

Expected UART output:

```text
===== GEMM 32x32 DMA TEST START =====
...
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
===== GEMM 32x32 DMA TEST END =====
```

---

## 9. Why the GUI launch may fail

The Vitis GUI may look correct but still fail because it may:

```text
- Not program the latest bitstream.
- Use a stale launch configuration.
- Use a stale XSA/platform.
- Skip or incompletely run PS-PL isolation removal.
- Skip or incompletely run psu_post_config.
- Download the ELF while the PL is not ready.
```

For this project, the XSCT script is preferred because the sequence is explicit:

```text
reset system
program FPGA
source psu_init.tcl
psu_init
psu_ps_pl_isolation_removal
psu_ps_pl_reset_config
psu_post_config
reset A53
download ELF
run
```

This is the flow that produced the successful `COMPARE PASS` hardware run.

---

## 10. Issue 3: DMA completes but C_hw is all zero

### Symptom

DMA completes:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
```

But the output is all zero or incorrect.

### Current project status

This issue was associated with older RTL/config-latch behavior and older software workarounds.

In the current project, the software no longer uses the old fake-config workaround. The current flow writes the real config once while the accelerator is idle:

```c
Xil_Out32(SHIFT_ADDR, R_SHIFT & 0x3FFU);
Xil_Out32(FL_ADDR, row_count);
Xil_Out32(FWBN_ADDR, k_block_count);
Xil_Out32(WWBN_ADDR, n_block_count);
```

The current hardware test passes without the old force-write sequence.

### Long-term RTL recommendation

The RTL should latch config deterministically on reset and at job start/config-freeze time.

Avoid unsafe patterns such as:

```verilog
always @(posedge clk) begin
    if (shift_in_delay1 != shift_in)
        shift <= shift_in;
end
```

A safer product-level design is:

```text
CPU writes SHIFT/FL/FWBN/WWBN
CPU writes START = 1
GEMM core latches config at START
GEMM core runs
GEMM core sets DONE = 1
CPU reads DONE/STATUS
```

---

## 11. Correct DMA order

Software must keep this order:

```text
1. Write GEMM config registers:
   SHIFT, F_length, F_width_block_num, W_width_block_num

2. Flush cache for A_buf and B_buf.
   Flush or clean C_hw if the CPU wrote it before DMA.

3. Reset DMA channels if needed.

4. Start DMA2 S2MM first so it is ready to receive results.

5. Start DMA0 MM2S to send feature/A.

6. Start DMA1 MM2S to send weight/B.

7. Wait for DMA0 done.

8. Wait for DMA1 done.

9. Wait for DMA2 done.

10. Wait/check GEMM done status.

11. Invalidate cache for C_hw.

12. Compare C_hw with C_sw.
```

Starting input DMA before result DMA can cause backpressure or stalls if the output stream is not ready.

---

## 12. DMA and cache notes

The AXI DMA stream width is 256 bits, which equals 32 bytes per beat.

Use at least 32-byte alignment. The current software uses 64-byte alignment:

```cpp
alignas(64) static data_t A_buf[MATRIX_A_BYTES];
alignas(64) static data_t B_buf[MATRIX_B_BYTES];
alignas(64) static data_t C_sw[MATRIX_C_BYTES];
alignas(64) static data_t C_hw[MATRIX_C_BYTES];
```

If DCache is enabled:

```c
Xil_DCacheFlushRange((INTPTR)A_buf, MATRIX_A_BYTES);
Xil_DCacheFlushRange((INTPTR)B_buf, MATRIX_B_BYTES);
Xil_DCacheFlushRange((INTPTR)C_hw, MATRIX_C_BYTES);

// After DMA2 is done:
Xil_DCacheInvalidateRange((INTPTR)C_hw, MATRIX_C_BYTES);
```

Disabling cache can be useful only for quick correctness debugging, but performance will drop.

---

## 13. AXI DMA registers used by the software

MM2S channel:

```c
#define MM2S_DMACR       0x00U
#define MM2S_DMASR       0x04U
#define MM2S_SA          0x18U
#define MM2S_SA_MSB      0x1CU
#define MM2S_LENGTH      0x28U
```

S2MM channel:

```c
#define S2MM_DMACR       0x30U
#define S2MM_DMASR       0x34U
#define S2MM_DA          0x48U
#define S2MM_DA_MSB      0x4CU
#define S2MM_LENGTH      0x58U
```

Common status values:

```text
0x00000001 : halted
0x00001002 : IOC interrupt + idle, transfer done
```

When starting a DMA transfer, write address first, then write length. Writing the length register starts the simple-mode transfer.

---

## 14. Tests that should be kept

### Test 1: AXI-Lite bus smoke test

Purpose:

```text
Confirm that the CPU can read and write PL AXI-Lite registers.
```

Expected output:

```text
READ DMA0 status...
DMA0 MM2S status = 0x00000001
READ DMA1 status...
DMA1 MM2S status = 0x00000001
READ DMA2 status...
DMA2 S2MM status = 0x00000001
READ GEMM status...
GEMM status = 0x04000000
```

If this test hangs, the PL is not ready or the run/init flow is wrong.

### Test 2: GEMM 32x32 DMA test

Purpose:

```text
Confirm the full pipeline:
PS -> AXI-Lite config
DDR -> DMA0/DMA1 -> GEMM
GEMM -> DMA2 -> DDR
C_hw == C_sw
```

Expected output:

```text
===== GEMM 32x32 DMA TEST START =====
...
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
Hardware GEMM done
COMPARE PASS
===== GEMM 32x32 DMA TEST END =====
```

### Test 3: Identity matrix test

Recommended future test:

```text
A = any test matrix
B = identity matrix
Expected C = A
```

This is useful for demonstrations because the expected result is easy to understand.

### Test 4: 64x64 test

Recommended future test:

```text
M = 64
K = 64
N = 64
row_count = 64
k_block_count = 2
n_block_count = 2
```

This confirms multi-block operation on the 32x32 array.

---

## 15. If C_hw becomes all zero again

Check in this order:

1. AXI-Lite readback:

```text
Readback SHIFT raw should contain shift=0 and idle status.
Readback FL should be 32.
Readback FWBN should be 1.
Readback WWBN should be 1.
```

2. DMA status:

```text
DMA0 status should contain IOC done, usually 0x00001002.
DMA1 status should contain IOC done, usually 0x00001002.
DMA2 status should contain IOC done, usually 0x00001002.
```

3. Buffer alignment:

```text
Buffers should be 32-byte or 64-byte aligned.
```

4. Cache maintenance:

```text
Flush input buffers before DMA.
Invalidate output buffer after DMA.
```

5. Matrix parameters:

```text
A_SIZE must be 32.
MATRIX_A_BYTES must be 1024 for 32x32.
MATRIX_B_BYTES must be 1024 for 32x32.
MATRIX_C_BYTES must be 1024 for 32x32.
```

6. Bitstream/platform freshness:

```text
Make sure the bitstream is rebuilt after RTL or BD changes.
Make sure the XSA/platform/app are rebuilt if hardware changes.
```

7. If the issue remains, use ILA or simulation on:

```text
feature_axis_tvalid/tready/tdata/tlast
weight_axis_tvalid/tready/tdata/tlast
result_axis_tvalid/tready/tdata/tlast
internal shift
internal F_length
internal F_width_block_num
internal W_width_block_num
GEMM FSM state
Out_buffer valid/last
```

---

## 16. Rebuild checklist after hardware changes

If RTL, IP packaging, block design, DMA settings, address map, clock, or reset changes:

```text
1. Regenerate output products if needed.
2. Reset synthesis and implementation runs if the design changed significantly.
3. Run synthesis.
4. Run implementation.
5. Generate bitstream.
6. Export hardware with bitstream included.
7. Rebuild the Vitis platform.
8. Rebuild the application.
9. Power-cycle the KV260.
10. Run using the known-good XSCT script.
11. Confirm COMPARE PASS.
```

Do not only export XSA without regenerating the bitstream after RTL changes.

---

## 17. Handoff conclusion

The current GEMM 32x32 INT8 accelerator has successfully passed a real hardware run on KV260:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
```

The accelerator itself is working for the current 32x32 test.

The most important operational note is:

```text
Do not rely on the Vitis GUI launch flow unless it is fully verified.
Use the known-good XSCT script when a stable run is required.
```

Recommended workflow for future developers:

```text
1. Keep the current passing app as a baseline.
2. Do not modify many things at once.
3. If RTL changes, rebuild bitstream/XSA/platform/app completely.
4. Run the AXI-Lite smoke test first.
5. Run the GEMM 32x32 compare test.
6. Only then move to larger tests or Qwen integration.
```
