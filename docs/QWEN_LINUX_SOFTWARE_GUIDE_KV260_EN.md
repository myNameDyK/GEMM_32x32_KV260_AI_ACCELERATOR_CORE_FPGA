# Qwen Software Integration Guide for the GEMM FPGA Accelerator on KV260 Linux

## 1. Purpose of this guide

This guide is for developers who want to integrate a Qwen inference runtime with the custom GEMM accelerator on the KV260 platform.

The current hardware has already passed a bare-metal 32x32 hardware test:

```text
AXI-Lite: PASS
DMA0 Feature MM2S: PASS
DMA1 Weight MM2S: PASS
DMA2 Result S2MM: PASS
GEMM compute: PASS
COMPARE PASS
```

The earlier “sometimes works, sometimes hangs” issue was not caused by random GEMM behavior. It came from an unstable launch/init flow in the Vitis GUI. When the FPGA bitstream, PS initialization, PS-PL isolation removal, A53 reset, and ELF download were done in the correct order using XSCT, the design ran correctly.

When moving to Linux, the software flow must be designed carefully so the Qwen application never touches the accelerator before the FPGA fabric, device tree, and driver layer are ready.

---

## 2. Hardware architecture summary

### 2.1 Current address map

```c
GEMM_DSP_IP_0      = 0xA0000000
AXI_DMA_0 feature  = 0xA0010000
AXI_DMA_1 weight   = 0xA0020000
AXI_DMA_2 result   = 0xA0030000
```

### 2.2 DMA roles

```text
DMA0: MM2S, DDR -> GEMM feature_axis
DMA1: MM2S, DDR -> GEMM weight_axis
DMA2: S2MM, GEMM result_axis -> DDR
```

### 2.3 GEMM AXI-Lite register map

```c
SHIFT_ADDR = 0xA0000000 + 0x00
FL_ADDR    = 0xA0000000 + 0x04
FWBN_ADDR  = 0xA0000000 + 0x08
WWBN_ADDR  = 0xA0000000 + 0x0C
```

| Offset | Name | Meaning |
|---:|---|---|
| `0x00` | shift/status | Write shift, read status |
| `0x04` | F_length / row_count | Number of output rows |
| `0x08` | F_width_block_num / k_block_count | Number of K blocks, each block has 32 elements |
| `0x0C` | W_width_block_num / n_block_count | Number of N blocks, each block has 32 columns |

Status register at offset `0x00`:

```c
bit [9:0]   shift
bit [16]    clear done request when writing
bit [24]    busy
bit [25]    done
bit [26]    idle
```

---

## 3. Key difference between bare-metal and Linux

### 3.1 Do not directly reuse `Xil_In32()` and `Xil_Out32()` in Linux user-space

Bare-metal code may use:

```c
Xil_In32(0xA0010004);
Xil_Out32(0xA0000004, 32);
```

Linux user-space code should not directly depend on `xil_io.h`, `xil_cache.h`, or `xaxidma_hw.h` like a Vitis bare-metal application.

For Linux, use one of these approaches:

```text
1. /dev/mem + mmap             useful only for AXI-Lite debug
2. UIO driver                  good for AXI-Lite control
3. custom kernel driver        cleanest and safest long-term approach
4. dma-proxy / udmabuf / CMA   needed for DMA buffers
```

### 3.2 Do not pass a normal `malloc()` buffer directly to DMA

This is unsafe:

```cpp
int8_t *buf = (int8_t*)malloc(size);
```

Reason:

```text
The CPU uses virtual addresses.
The DMA engine needs physical addresses.
The CPU cache may not be coherent with DDR from the DMA point of view.
```

If this is handled incorrectly, the symptoms can be very confusing:

```text
DMA reports done but the data is wrong.
The same program sometimes passes and sometimes fails.
The Qwen output becomes corrupted.
The model repeats wrong tokens.
The result buffer contains stale data.
```

Use one of these instead:

```text
- dma-proxy driver
- udmabuf
- reserved memory + mmap
- custom kernel driver with dma_alloc_coherent()
- XRT/xclbin flow if the project is moved to Vitis acceleration
```

---

## 4. Correct Linux flow before running Qwen

Do not run Qwen immediately after boot unless the PL and drivers are already initialized.

Recommended flow:

```text
1. Boot Linux.
2. Load the FPGA bitstream or overlay.
3. Load the device-tree overlay if required.
4. Check device nodes: /dev/uioX, /dev/dma_proxy*, /dev/udmabuf*.
5. Run an AXI-Lite smoke test.
6. Run a 32x32 GEMM hardware test.
7. Only run Qwen after the GEMM test passes.
```

Example launcher script:

```bash
#!/bin/bash
set -e

echo "Load bitstream..."
sudo fpgautil -b GEMM_DSP_BD_wrapper.bit.bin

echo "Check Linux devices..."
ls /dev/uio* || true
ls /dev/dma_proxy* || true
ls /dev/udmabuf* || true

echo "Run AXI-Lite smoke test..."
sudo ./axi_smoke_test

echo "Run GEMM 32x32 test..."
sudo ./gemm_test_32x32

echo "Run Qwen..."
sudo ./qwen_gemm_accel
```

---

## 5. Always run a smoke test before Qwen

Before launching Qwen, the software must verify that the hardware is reachable.

### 5.1 AXI-Lite smoke test

The test should read at least these addresses:

```c
GEMM status       = *(0xA0000000)
DMA0 MM2S status  = *(0xA0010004)
DMA1 MM2S status  = *(0xA0020004)
DMA2 S2MM status  = *(0xA0030034)
```

Expected behavior:

```text
No hang.
No bus error.
A status value is returned.
GEMM idle is usually bit 26.
DMA status depends on reset/run state.
```

If this test fails, stop immediately. Do not run Qwen.

### 5.2 GEMM 32x32 test

After the AXI-Lite smoke test, run a small GEMM test:

```text
A: 32x32 int8
B: 32x32 int8
C: 32x32 int8
```

Flow:

```text
1. Write GEMM config:
   shift = 0
   row_count = 32
   k_block_count = 1
   n_block_count = 1

2. Sync/flush feature and weight buffers.

3. Start DMA2 S2MM first.

4. Start DMA0 feature MM2S.

5. Start DMA1 weight MM2S.

6. Wait for DMA0, DMA1, and DMA2 to complete.

7. Sync/invalidate the result buffer.

8. Compare C_hw against C_sw.
```

Only proceed to Qwen when this prints `COMPARE PASS`.

---

## 6. Required DMA order

For this accelerator, always use this order:

```text
1. Start result DMA S2MM first.
2. Start feature DMA MM2S.
3. Start weight DMA MM2S.
4. Wait for DMA0 done.
5. Wait for DMA1 done.
6. Wait for DMA2 done.
7. Check GEMM done.
```

Do not start the result DMA last. If the result stream is not ready, the accelerator can be backpressured or stalled.

---

## 7. Data layout for the accelerator

### 7.1 Feature input layout

Each AXI-Stream beat is 256 bits:

```text
32 lanes * 8 bits = 256 bits
```

Feature sequence:

```text
for row = 0 .. row_count-1:
    for k_block = 0 .. k_block_count-1:
        send one 256-bit beat
```

Inside one beat:

```text
lane 0  -> K index k_block*32 + 0
lane 1  -> K index k_block*32 + 1
...
lane 31 -> K index k_block*32 + 31
```

### 7.2 Weight input layout

Weight sequence:

```text
for k_block = 0 .. k_block_count-1:
    for k_lane = 0 .. 31:
        for n_block = 0 .. n_block_count-1:
            send one 256-bit beat
```

Inside one beat:

```text
lane 0  -> N index n_block*32 + 0
lane 1  -> N index n_block*32 + 1
...
lane 31 -> N index n_block*32 + 31
```

### 7.3 Result output layout

Result sequence:

```text
for row = 0 .. row_count-1:
    for n_block = 0 .. n_block_count-1:
        receive one 256-bit beat
```

Inside one beat:

```text
lane 0  -> N index n_block*32 + 0
...
lane 31 -> N index n_block*32 + 31
```

---

## 8. Tiling rule for Qwen matrices

The accelerator array size is 32, so the software must tile dimensions by 32.

For:

```text
C[M, N] = A[M, K] * B[K, N]
```

Use:

```c
row_count     = M;
k_block_count = (K + 31) / 32;
n_block_count = (N + 31) / 32;
padded_K      = k_block_count * 32;
padded_N      = n_block_count * 32;
```

If `K` or `N` is not divisible by 32:

```text
Pad unused feature K lanes with 0.
Pad unused weight K/N entries with 0.
Ignore result lanes beyond the real N dimension.
```

---

## 9. Which Qwen operations should use the accelerator?

A Qwen decoder layer contains more than GEMM:

```text
Embedding
RMSNorm
Q/K/V projection
RoPE
Attention score
Softmax
Value matmul
Output projection
MLP gate/up projection
SwiLU
MLP down projection
KV cache
```

The current GEMM accelerator is suitable for:

```text
Q projection
K projection
V projection
O projection
MLP gate projection
MLP up projection
MLP down projection
Other linear layers
```

Keep these on CPU at first:

```text
Tokenizer
Embedding lookup
RMSNorm / LayerNorm
RoPE
Softmax
SwiLU
KV cache management
Sampling
```

After GEMM is stable, additional nonlinear operators can be considered for FPGA acceleration.

---

## 10. Recommended software architecture

Suggested C++ source tree:

```text
src/
  main.cpp
  qwen_runtime.cpp
  qwen_runtime.h

  fpga/
    fpga_init.cpp
    fpga_init.h
    axi_lite.cpp
    axi_lite.h
    dma_buffer.cpp
    dma_buffer.h
    gemm_accel.cpp
    gemm_accel.h

  tests/
    axi_smoke_test.cpp
    gemm_32x32_test.cpp
```

### 10.1 `axi_lite`

Responsibilities:

```text
Map AXI-Lite registers.
read32(addr)
write32(addr, value)
unmap
```

Can use `/dev/mem` or UIO.

### 10.2 `dma_buffer`

Responsibilities:

```text
Allocate a DMA-safe buffer.
Return a CPU virtual address.
Return a DMA physical address.
Handle cache synchronization if the selected driver requires it.
```

Do not use normal `malloc()` buffers as DMA buffers.

### 10.3 `gemm_accel`

Responsibilities:

```text
Accept A, B, C, M, K, N, and shift.
Pack feature layout.
Pack weight layout.
Start DMA.
Wait for completion.
Unpack result.
```

Suggested API:

```cpp
class GemmAccel {
public:
    bool init();
    bool smoke_test();
    bool run_int8_gemm(
        const int8_t* A,
        const int8_t* B,
        int8_t* C,
        int M,
        int K,
        int N,
        int shift
    );
};
```

---

## 11. Example AXI-Lite mmap smoke test using `/dev/mem`

Use this only for AXI-Lite debug. Do not use this method for DMA buffers.

```cpp
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static constexpr uintptr_t PL_BASE = 0xA0000000;
static constexpr size_t PL_SIZE = 0x00040000;

static volatile uint32_t* regs = nullptr;

static uint32_t read32(uintptr_t addr) {
    uintptr_t offset = addr - PL_BASE;
    return regs[offset / 4];
}

static void write32(uintptr_t addr, uint32_t value) {
    uintptr_t offset = addr - PL_BASE;
    regs[offset / 4] = value;
}

int main() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 1;
    }

    void* map = mmap(nullptr, PL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, PL_BASE);
    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }

    regs = reinterpret_cast<volatile uint32_t*>(map);

    printf("GEMM status  = 0x%08X\n", read32(0xA0000000));
    printf("DMA0 status  = 0x%08X\n", read32(0xA0010004));
    printf("DMA1 status  = 0x%08X\n", read32(0xA0020004));
    printf("DMA2 status  = 0x%08X\n", read32(0xA0030034));

    munmap(map, PL_SIZE);
    close(fd);
    return 0;
}
```

If this hangs or causes a bus error:

```text
The bitstream may not be loaded.
The device tree or FPGA manager flow may be wrong.
The PL AXI path may not be ready.
The address map may be wrong.
```

Do not run Qwen if the smoke test does not pass.

---

## 12. Device tree and driver checklist

A Linux design needs a clear driver strategy.

### 12.1 If using UIO for AXI-Lite

The device tree should expose:

```text
GEMM control
DMA0 control
DMA1 control
DMA2 control
```

Each region may appear as a `/dev/uioX` device.

### 12.2 If using a custom DMA driver

The driver should:

```text
Map AXI DMA registers.
Allocate DMA-coherent buffers.
Expose ioctl or a character device to user-space.
Perform cache synchronization correctly.
Provide the physical address to the DMA engine.
```

### 12.3 If using udmabuf

The system needs:

```text
Reserved memory or CMA.
A /dev/udmabufX node.
Physical address from sysfs.
Virtual address mapped into user-space.
```

---

## 13. Common errors when integrating Qwen

### 13.1 Running the app before loading the bitstream

Symptoms:

```text
AXI read hangs.
Bus error.
DMA status cannot be read.
```

Prevention:

```text
Always load the bitstream first.
Always run the AXI smoke test.
```

### 13.2 Using the wrong physical address for DMA

Symptoms:

```text
DMA error bit is set.
DMADecErr.
DMASlvErr.
Result is all zero or random.
```

Prevention:

```text
Do not use a malloc pointer as a DMA address.
Use a valid DMA buffer mechanism.
```

### 13.3 Missing cache synchronization

Symptoms:

```text
Data sometimes passes and sometimes fails.
CPU reads old data.
DMA receives old input.
```

Prevention:

```text
Use DMA-coherent buffers or a driver that syncs the cache correctly.
```

### 13.4 Wrong feature or weight layout

Symptoms:

```text
DMA done.
GEMM done.
C_hw does not match C_sw.
```

Prevention:

```text
Test 32x32 first.
Then test 64x64.
Then test shapes close to the Qwen linear layers.
```

### 13.5 Wrong shift or quantization

Symptoms:

```text
Output saturates to 127 or -128.
Output becomes too small or all zero.
```

Prevention:

```text
Log accumulator min/max.
Choose shift according to the quantization scale.
Compare against an INT8 reference model.
```

### 13.6 Missing padding

Symptoms:

```text
Shapes that are not divisible by 32 produce wrong results.
```

Prevention:

```text
Pad K and N with zero.
Ignore output lanes beyond the real N dimension.
```

---

## 14. Recommended Qwen bring-up plan

Do not start with full Qwen. Increase complexity step by step:

```text
Step 1: AXI-Lite smoke test
Step 2: GEMM 32x32
Step 3: GEMM 64x64
Step 4: GEMM with M/K/N similar to a small Qwen linear layer
Step 5: Run one Qwen Linear layer on FPGA
Step 6: Run Q/K/V projection
Step 7: Run MLP projections
Step 8: Run one decoder layer
Step 9: Run full token generation
```

Every step must be compared against a CPU reference.

---

## 15. Checklist before running Qwen

Before running the Qwen application, verify:

```text
[ ] Linux boots correctly.
[ ] The bitstream is loaded.
[ ] The device tree overlay is correct.
[ ] /dev/uio or DMA device nodes exist.
[ ] AXI-Lite smoke test passes.
[ ] GEMM 32x32 passes.
[ ] GEMM 64x64 passes.
[ ] DMA buffers use valid physical addresses.
[ ] Cache coherency is handled.
[ ] Feature layout is correct.
[ ] Weight layout is correct.
[ ] Result unpacking is correct.
[ ] Quantization scale/shift is correct.
[ ] A CPU reference path exists for comparison.
```

---

## 16. Important rules to remember

```text
Never run Qwen before the AXI smoke test and GEMM test pass.

Never pass a normal malloc pointer to the DMA engine.

Do not directly reuse Xil_In32 or Xil_DCacheFlushRange from bare-metal in Linux.

Do not assume the bitstream is loaded just because Linux has booted.

Do not debug the full Qwen model while the small GEMM test is still failing.
```

---

## 17. Conclusion

The accelerator has already been proven on hardware with a bare-metal 32x32 `COMPARE PASS` test. When moving to Linux/Qwen, the main challenge is no longer “can the GEMM accelerator compute correctly?” Instead, the key issues are:

```text
1. Load the bitstream correctly.
2. Use the correct device tree and driver.
3. Use DMA-safe buffers with valid physical addresses.
4. Handle cache coherency correctly.
5. Pack feature and weight data correctly.
6. Run smoke tests before running the full model.
```

If this flow is followed, Qwen integration will be much more stable and will avoid the “sometimes works, sometimes hangs” behavior caused by incomplete hardware initialization.
