# Address Map - GEMM 32x32 KV260

This document records the **current hardware memory map**, software register usage, DMA usage, and known-good run flow for the **GEMM 32x32 INT8 accelerator project on KV260/K26**.

This version matches the current working project:

```text
Vivado project : E:/Everything_with_VIVADO/GEMM_final_DSP
Vitis workspace: E:/VITIS_2022
Platform       : GEMM_final_DSP
Application    : GEMM_DSP
Bitstream      : E:/Everything_with_VIVADO/GEMM_final_DSP/GEMM_final_DSP.runs/impl_1/GEMM_DSP_BD_wrapper.bit
ELF            : E:/VITIS_2022/GEMM_DSP/Debug/GEMM_DSP.elf
```

The current 32x32 hardware test has been verified with:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
```

---

## 1. Target Platform

| Item | Value |
|---|---|
| Board | Xilinx KV260 Vision AI Starter Kit |
| SOM / Device | K26, `xck26-sfvc784-2LV-c` |
| Board part | `xilinx.com:kv260_som:part0:1.4` |
| Tool version used | Vivado / Vitis 2022.2 |
| Processing system | Zynq UltraScale+ MPSoC |
| CPU used by bare-metal app | Cortex-A53 #0 |
| Application project | `GEMM_DSP` |
| Hardware platform project | `GEMM_final_DSP` |
| UART | Serial terminal, 115200 baud |

---

## 2. High-Level Data Path

The design uses three AXI DMA IP blocks and one custom GEMM IP.

```text
DDR memory
   |
   | AXI MM2S
   v
axi_dma_0  -------------------->  GEMM_DSP_IP_0/feature_axis
                                  |
DDR memory                        |
   |                              |
   | AXI MM2S                     |
   v                              v
axi_dma_1  -------------------->  GEMM_DSP_IP_0/weight_axis

GEMM_DSP_IP_0/result_axis ----->  axi_dma_2
                                      |
                                      | AXI S2MM
                                      v
                                  DDR memory
```

Control is done through AXI-Lite:

```text
Cortex-A53
   |
   | AXI-Lite
   v
AXI Interconnect
   |
   +--> GEMM_DSP_IP_0/S_AXI
   +--> axi_dma_0/S_AXI_LITE
   +--> axi_dma_1/S_AXI_LITE
   +--> axi_dma_2/S_AXI_LITE
```

---

## 3. Current Main Address Map

These addresses are generated in `xparameters.h` after exporting the hardware platform and building the Vitis platform.

The current working project uses this address map:

| Block | Purpose | Base Address | Macro |
|---|---|---:|---|
| `GEMM_DSP_IP_0` | Custom GEMM control registers | `0xA0000000` | `XPAR_GEMM_DSP_IP_0_BASEADDR` |
| `axi_dma_0` | Feature input DMA, MM2S only | `0xA0010000` | `XPAR_AXI_DMA_0_BASEADDR` |
| `axi_dma_1` | Weight input DMA, MM2S only | `0xA0020000` | `XPAR_AXI_DMA_1_BASEADDR` |
| `axi_dma_2` | Result output DMA, S2MM only | `0xA0030000` | `XPAR_AXI_DMA_2_BASEADDR` |

Recommended aliases in `Defines.h`:

```c
#define MM_ADDR             XPAR_GEMM_DSP_IP_0_BASEADDR

#define FEATURE_DMA_ADDR    XPAR_AXI_DMA_0_BASEADDR
#define WEIGHT_DMA_ADDR     XPAR_AXI_DMA_1_BASEADDR
#define RESULT_DMA_ADDR     XPAR_AXI_DMA_2_BASEADDR

#define A_SIZE              32U
```

Important note:

```text
Do not manually edit xparameters.h.
If the Vivado block design changes, export the hardware again, rebuild the Vitis platform, rebuild the application, and re-check xparameters.h.
```

---

## 4. GEMM Control Register Map

`GEMM_DSP_IP_0` is controlled through AXI-Lite. The current software uses the following offsets:

| Register | Offset | Address expression | Meaning |
|---|---:|---|---|
| `SHIFT` / status | `0x00` | `MM_ADDR + 0x00` | Write right shift amount; read shift/status |
| `F_length` | `0x04` | `MM_ADDR + 0x04` | Number of output rows |
| `F_width_block_num` | `0x08` | `MM_ADDR + 0x08` | Number of K blocks |
| `W_width_block_num` | `0x0C` | `MM_ADDR + 0x0C` | Number of output-width/N blocks |

Status bits from the `SHIFT` / status register:

| Bit range | Meaning |
|---:|---|
| `[9:0]` | Current shift value |
| `[16]` | Clear done request when writing |
| `[24]` | Busy |
| `[25]` | Done |
| `[26]` | Idle |

For the current 32x32 test:

| Parameter | Value |
|---|---:|
| `A_SIZE` | `32` |
| `F_length` / row count | `32` |
| `F_width_block_num` / K block count | `1` |
| `W_width_block_num` / N block count | `1` |
| `SHIFT` | `0` |

Expected readback from a correct idle configuration:

```text
Readback SHIFT raw = 0x04000000, shift=0
Readback FL        = 0x00000020
Readback FWBN      = 0x00000001
Readback WWBN      = 0x00000001
```

`0x04000000` means the idle bit is set and the shift value is 0.

---

## 5. AXI DMA Register Offsets

The software uses the standard Xilinx AXI DMA simple-mode register layout.

### 5.1 MM2S channel

Used by:

```text
axi_dma_0: feature matrix A
axi_dma_1: weight matrix B
```

| Register | Offset | Meaning |
|---|---:|---|
| `MM2S_DMACR` | `0x00` | MM2S control |
| `MM2S_DMASR` | `0x04` | MM2S status |
| `MM2S_SA` | `0x18` | Source address low 32 bits |
| `MM2S_SA_MSB` | `0x1C` | Source address high 32 bits |
| `MM2S_LENGTH` | `0x28` | Transfer length in bytes |

### 5.2 S2MM channel

Used by:

```text
axi_dma_2: result matrix C
```

| Register | Offset | Meaning |
|---|---:|---|
| `S2MM_DMACR` | `0x30` | S2MM control |
| `S2MM_DMASR` | `0x34` | S2MM status |
| `S2MM_DA` | `0x48` | Destination address low 32 bits |
| `S2MM_DA_MSB` | `0x4C` | Destination address high 32 bits |
| `S2MM_LENGTH` | `0x58` | Transfer length in bytes |

Common DMA status values seen during testing:

| Value | Meaning |
|---:|---|
| `0x00000001` | DMA halted before transfer |
| `0x00001002` | Transfer done; IOC interrupt bit set and channel idle |

When starting a DMA transfer:

```text
1. Write the DMA address register first.
2. Write the length register last.
3. Writing LENGTH starts the simple-mode transfer.
```

---

## 6. Matrix Transfer Sizes

For 32x32 INT8 GEMM:

| Buffer | Matrix | Size calculation | Bytes |
|---|---|---:|---:|
| Feature input | A, 32x32 INT8 | `32 * 32 * 1` | `1024` |
| Weight input | B, 32x32 INT8 | `32 * 32 * 1` | `1024` |
| Result output | C, 32x32 INT8 | `32 * 32 * 1` | `1024` |

The AXI-Stream data width is 256 bits:

```text
256 bits = 32 bytes per AXIS beat
```

Therefore, each 1024-byte matrix corresponds to:

```text
1024 / 32 = 32 AXI-Stream beats
```

---

## 7. DMA Start Order

The recommended and verified order is:

```text
1. Write GEMM control registers:
   SHIFT, F_length, F_width_block_num, W_width_block_num

2. Reset DMA channels if needed.

3. Flush CPU cache for feature, weight, and result buffers.

4. Start DMA2 S2MM first, so the result channel is ready to receive data.

5. Start DMA0 MM2S for feature matrix A.

6. Start DMA1 MM2S for weight matrix B.

7. Wait for DMA0 feature done.

8. Wait for DMA1 weight done.

9. Wait for DMA2 result done.

10. Wait/check GEMM done status.

11. Invalidate result buffer cache.

12. Compare hardware result with software result.
```

This order prevents the GEMM result stream from being blocked because the S2MM channel is not ready.

---

## 8. Cache and Buffer Alignment Notes

The AXI DMA stream width is 256 bits, so one beat is 32 bytes.

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

Important notes:

```text
- Flush A and B before MM2S DMA reads them.
- Flush or clean C_hw before S2MM if the CPU wrote to it earlier.
- Invalidate C_hw after S2MM DMA finishes before the CPU reads the result.
```

---

## 9. Current Software Configuration

For the verified 32x32 test:

```c
#define A_SIZE 32U

IN_ROWS_NUM = 32
IN_COLS_NUM = 32
OUT_COLS_NUM = 32

MATRIX_A_BYTES = 1024
MATRIX_B_BYTES = 1024
MATRIX_C_BYTES = 1024

R_SHIFT = 0
```

The current run does not require the old fake-config workaround. The software writes the real configuration once while the core is idle:

```c
Xil_Out32(SHIFT_ADDR, R_SHIFT & 0x3FFU);
Xil_Out32(FL_ADDR, row_count);
Xil_Out32(FWBN_ADDR, k_block_count);
Xil_Out32(WWBN_ADDR, n_block_count);
```

The old workaround that forced config registers to change once before writing the real values should not be treated as the current official flow.

---

## 10. Known Vitis GUI Run Issue

The Vitis GUI launch configuration may still fail or hang even when the project itself is correct.

A common failure point is:

```text
stage 0: bus smoke test
READ DMA0 status...
```

This means the CPU is attempting to read:

```text
0xA0010004
```

but the DMA0 AXI-Lite slave is not responding.

This usually means:

```text
- The FPGA bitstream was not programmed correctly.
- The GUI used a stale bitstream or stale platform.
- PS-PL isolation was not removed.
- psu_post_config was not run correctly.
- The application was downloaded before the PL path was ready.
```

The current project should be run with the known-good XSCT script in the next section.

---

## 11. Known-Good XSCT Run Script

This is the verified run script for the current project.

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

Run from XSCT:

```tcl
source E:/VITIS_2022/run_gemm_dsp.tcl
```

Recommended procedure after powering on the board:

```text
1. Open the UART serial terminal at 115200 baud.
2. Power-cycle the KV260 if the board was in a stale state.
3. Open XSCT Console.
4. Run the script above.
5. Wait for COMPARE PASS.
```

Expected UART output:

```text
===== GEMM 32x32 DMA TEST START =====
MM_ADDR          = 0xA0000000
FEATURE_DMA_ADDR = 0xA0010000
WEIGHT_DMA_ADDR  = 0xA0020000
RESULT_DMA_ADDR  = 0xA0030000
A_SIZE=32, MATRIX_A_BYTES=1024, MATRIX_B_BYTES=1024, MATRIX_C_BYTES=1024
Software GEMM start
Software GEMM done
stage 0: bus smoke test
READ DMA0 status...
DMA0 MM2S status = 0x00000001
READ DMA1 status...
DMA1 MM2S status = 0x00000001
READ DMA2 status...
DMA2 S2MM status = 0x00000001
READ GEMM status...
GEMM status = 0x04000000
...
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
Hardware GEMM done
COMPARE PASS
===== GEMM 32x32 DMA TEST END =====
```

---

## 12. Reset / Clock Notes

The design should use a consistent PL clock and reset.

Recommended:

```text
Clock:
  zynq_ultra_ps_e_0/pl_clk0 -> all PL AXI and accelerator clocks

Reset:
  rst_ps8_0_96M/peripheral_aresetn -> all active-low PL resets
```

Important:

```text
If the proc_sys_reset block has a dcm_locked input, it must be driven high or connected to a valid locked signal.
If dcm_locked is left low, PL reset may remain active and AXI-Lite reads may hang.
```

---

## 13. Final Verified Output

The current project was verified with the following result:

```text
DMA0 feature done, status=0x00001002
DMA1 weight done, status=0x00001002
DMA2 result done, status=0x00001002
GEMM done, status=0x06000000
COMPARE PASS
```

This confirms that the 32x32 INT8 GEMM hardware result matched the software reference result.

---

## 14. Notes for Future Linux / Qwen Integration

When this accelerator is later used from Linux for Qwen inference, do not directly reuse the bare-metal `Xil_In32`, `Xil_Out32`, or `Xil_DCacheFlushRange` flow.

Linux software should use one of these methods:

```text
- /dev/mem + mmap only for AXI-Lite smoke tests
- UIO for AXI-Lite control
- udmabuf / dma-proxy / CMA / custom driver for DMA-safe buffers
```

Important Linux/Qwen rules:

```text
1. Load the bitstream before the Qwen application touches the accelerator.
2. Run an AXI-Lite smoke test before running Qwen.
3. Run a small GEMM 32x32 hardware test before running the full model.
4. Do not pass normal malloc pointers directly to DMA.
5. Use valid physical addresses for DMA.
6. Handle cache coherency through the driver or coherent buffers.
7. Pack feature and weight data according to the accelerator layout.
8. Compare each bring-up step against a CPU reference.
```

Recommended Linux bring-up order:

```text
1. AXI-Lite smoke test
2. GEMM 32x32 test
3. GEMM 64x64 test
4. One Qwen Linear layer
5. Q/K/V projection
6. MLP projection
7. One decoder layer
8. Full Qwen token generation
```

---

## 15. Handoff Conclusion

The current hardware and software baseline is working for 32x32 INT8 GEMM on KV260.

The most important points are:

```text
- Use the current address map, not the old one.
- Use the known-good XSCT script for stable bare-metal runs.
- Keep DMA2 S2MM started before input DMA channels.
- Keep cache flush/invalidate operations correct.
- Keep the passing 32x32 app as the baseline before modifying RTL or software.
```
