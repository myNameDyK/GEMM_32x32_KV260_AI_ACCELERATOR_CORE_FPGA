# FPGA GEMM Integration for llama.cpp (KV260)

Ý tưởng: Tích hợp FPGA GEMM accelerator (32×32 INT8) vào llama.cpp chạy trên board Kria KV260, nhằm tăng tốc phép nhân ma trận (GEMM) bằng phần cứng FPGA thay vì CPU.

---

## Mục tiêu

Thay thế phép nhân ma trận (GEMM) trong llama.cpp bằng FPGA hardware accelerator. Khi chạy inference mô hình ngôn ngữ (LLM), phần lớn thời gian tính toán nằm ở các phép GEMM. Dự án này hook vào đúng điểm đó trong llama.cpp, kiểm tra điều kiện phù hợp (kiểu quantization, kích thước ma trận), và chuyển công việc sang FPGA qua DMA — trong khi CPU vẫn xử lý các phần còn lại.

Hỗ trợ các kiểu quantization: **Q5_0**, **Q8_0**, **Q4_K**.

---

## Luồng hoạt động tổng quan

```
llama.cpp (ggml-cpu.c)
└── ggml_compute_forward_mul_mat()
    │   src0 = weight (quantized), src1 = activation (F32), dst = output (F32)
    │
    └── [FPGA HOOK — #ifdef GGML_USE_FPGA, chỉ thread ith==0]
        │
        ├── Điều kiện bắt buộc (tất cả phải đúng):
        │   ├── fpga_gemm_is_ready() == true
        │   ├── src0->type ∈ {Q5_0, Q8_0, Q4_K}
        │   ├── src1->type == F32
        │   ├── không batch: ne02==1, ne03==1, ne12==1, ne13==1
        │   ├── K khớp: ne10 == ne00
        │   ├── kích thước hợp lệ: ne01 < 65537, ne00 < 65537, ne11 > 0
        │   └── block aligned:
        │       ├── Q4_K → (K×N) % 256 == 0
        │       └── Q5_0 / Q8_0 → (K×N) % 32 == 0
        │
        ├── Nếu đủ điều kiện → fpga_gemm_run(weight, quant, activation, output, M, K, N, shift=0)
        │   │
        │   ├── A. Quantize activation: scale_B = max|B|/127 ; feat_q = clamp(round(B/scale_B))
        │   │       → ghi vào DDR_FEAT (M × K_pad bytes, zero-pad K → K_pad = ceil32(K))
        │   │
        │   ├── B. Cache weight (một lần duy nhất theo con trỏ src0->data):
        │   │       dequant Q5_0/Q8_0/Q4_K → float → quantize → int8
        │   │       zero-pad K→K_pad, N→N_pad → ghi vào weight pool trong DDR_WGHT
        │   │       lưu WeightEntry{phys_addr, scale_W, size, K_pad, N_pad}
        │   │
        │   ├── C. Tính shift = floor(log2(K_pad × 127)), clamp [0, 24]
        │   │
        │   ├── D. Ghi AXI-Lite config:
        │   │       REG_SHIFT    = shift
        │   │       REG_F_LENGTH = M
        │   │       REG_F_WIDTH  = K_pad / 32
        │   │       REG_W_WIDTH  = N_pad / 32
        │   │
        │   ├── E. DMA sequence:
        │   │       dma_recv_start(DDR_RSLT, M×N_pad)   ← bắt đầu nhận trước
        │   │       dma_send(DDR_FEAT, M×K_pad)          ← gửi activation
        │   │       dma_send(DDR_WGHT+offset, size)      ← gửi weight
        │   │       dma_recv_wait()                      ← đợi kết quả
        │   │
        │   └── F. Dequant output: C[m,n] = ddr_rslt[m×N_pad+n] × scale_B × scale_W × 2^shift
        │
        ├── ggml_barrier() — đồng bộ các thread
        ├── return  ← bỏ qua toàn bộ CPU path
        │
        └── Ngược lại → CPU path bình thường (vec_dot, multi-thread, v.v.)
```

### Math pipeline (quantization)

```
scale_B = max|activation| / 127
scale_W = max|weight_f32| / 127       (tính lúc cache, lưu trong WeightEntry)
out_scale = scale_B × scale_W × 2^shift

FPGA tính: acc[m,n] = Σ_k feat_q[m,k] × wght_q[k,n]   (INT8 × INT8 → ACC)
           rslt[m,n] = clamp(acc >> shift, -128, 127)    (INT8 output)

CPU nhận:  C[m,n] = rslt[m,n] × out_scale               (→ F32)
```

---

## Model đang sử dụng
**Qwen2.5-0.5B-Instruct (Q4_K_M)**

| Thông số | Giá trị |
|----------|---------|
| Model | Qwen2.5-0.5B-Instruct-Q4_K_M |
| Số transformer layer | 24 |
| Hidden size | 896 |
| FFN intermediate size | 4864 |
| Vocab size | 151936 |

### Phân bổ tensor theo layer (runtime type sau khi llama.cpp load)

| Tensor | Shape | Type (file) | Type (runtime) | Là MUL_MAT | Chia hết 32 | Size (MB) | Chạy trên |
|--------|-------|------------|----------------|-----------|------------|-----------|-----------|
| token_embd.weight *(shape lẻ)* | [151936×896] | Q8_0 | Q8_0 | Có | Không | 137.94 | CPU |
| blk.N.attn_norm.weight ×24 | [896] | F32 | F32 | Không | Có | <0.01 | CPU |
| blk.N.attn_q.weight ×24 | [896×896] | Q4_K | **Q5_0** | Có | Có | 0.53 | **FPGA** |
| blk.N.attn_q.bias ×24 | [896] | F32 | F32 | Không | Có | <0.01 | CPU |
| blk.N.attn_k.weight ×24 | [128×896] | Q4_K | **Q5_0** | Có | Có | 0.08 | **FPGA** |
| blk.N.attn_k.bias ×24 | [128] | F32 | F32 | Không | Có | <0.01 | CPU |
| blk.N.attn_v.weight ×24 | [128×896] | Q4_K | **Q5_0** | Có | Có | 0.08 | **FPGA** |
| blk.N.attn_v.bias ×24 | [128] | F32 | F32 | Không | Có | <0.01 | CPU |
| blk.N.attn_output.weight ×24 | [896×896] | Q4_K | **Q5_0** | Có | Có | 0.53 | **FPGA** |
| blk.N.ffn_norm.weight ×24 | [896] | F32 | F32 | Không | Có | <0.01 | CPU |
| blk.N.ffn_gate.weight ×24 | [4864×896] | Q4_K | Q4_K | Có | Có | 2.34 | **FPGA** |
| blk.N.ffn_up.weight ×24 | [4864×896] | Q4_K | Q4_K | Có | Có | 2.34 | **FPGA** |
| blk.N.ffn_down.weight ×24 | [896×4864] | Q4_K | Q4_K | Có | Có | 2.34 | **FPGA** |
| output_norm.weight | [896] | F32 | F32 | Không | Có | <0.01 | CPU |
| output.weight *(shape lẻ)* | [151936×896] | Q4_K | Q4_K | Có | Không | 80.54 | CPU |

> **Ghi chú:** llama.cpp tự requantize một số tensor từ Q4_K → Q5_0 tại runtime (xác nhận qua debugger: `src0 type=GGML_TYPE_Q5_0`). `token_embd.weight` và `output.weight` có shape lẻ (151936 không chia hết 32) → CPU. FFN weights giữ nguyên Q4_K và được offload FPGA qua `cache_q4_K()`.

---

## Các file đã thêm / sửa

### Files mới tạo

**`ggml/src/ggml-cpu/FPGA_GEMM/FPGA_GEMM.h`**
Header định nghĩa API công khai cho FPGA driver, bao gồm:
- `fpga_gemm_init()` — khởi tạo driver, map địa chỉ AXI-Lite và DMA buffer
- `fpga_gemm_run()` — thực hiện toàn bộ pipeline GEMM trên FPGA
- `fpga_gemm_is_ready()` — kiểm tra trạng thái sẵn sàng
- Struct `WeightEntry` cho weight cache, enum `FpgaQuantType`, các hằng số địa chỉ DDR và AXI-Lite

**`ggml/src/ggml-cpu/FPGA_GEMM/FPGA_GEMM.cpp`**
Driver chính, gồm các thành phần:

- **`fpga_gemm_init()`** — mở `/dev/mem`, `mmap` 4 vùng AXI-Lite (`AXILITE_BASE`), 3 DMA controller (`DMA_FEAT/WGHT/RSLT`), và 3 vùng DDR vật lý (`DDR_FEAT/WGHT/RSLT`). Reset các DMA channel. Trên Windows dùng `mock_init()`.
- **`fpga_gemm_run()`** — pipeline 6 bước: quantize activation → cache weight → tính shift → ghi AXI-Lite → DMA sequence → dequant output. Trên Windows build, sau lần chạy đầu tiên còn in thêm CPU reference GEMM để so sánh `max_diff` / `mean_diff`.
- **Weight cache** (`g_weight_cache`) — `unordered_map<const void*, WeightEntry>` key theo con trỏ `src0->data`. Mỗi weight tensor chỉ dequant và ghi DDR một lần duy nhất trong suốt session.
- **Weight pool allocator** (`alloc_weight`) — phân bổ tuyến tính trong `DDR_WGHT` (0x84000000, 512 MB), align 64 byte. Không có free/LRU — pool reset khi `fpga_gemm_cleanup()`.
- **Dequant helpers** — `dequant_q5_0`, `dequant_q8_0`, `dequant_q4_K` convert block format của ggml sang float32 trước khi re-quantize INT8.

**`ggml/src/ggml-cpu/FPGA_GEMM/fpga_win_mock.h`**
Mock layer cho Windows/PC: giả lập `mmap` (dùng `malloc`), DMA send/recv (dùng `memcpy` + tính INT8 GEMM bằng CPU), và AXI-Lite register writes (log ra stdout). Khi build trên `_WIN32`, file này được include trực tiếp trong `FPGA_GEMM.cpp`, thay thế toàn bộ phần hardware. Đặc biệt: mock tính sẵn kết quả INT8 GEMM trong `dma_recv_start` để `fpga_gemm_run` có thể đọc về và so sánh với CPU float reference.

**`cmake/aarch64-toolchain.cmake`**
Toolchain cross-compile cho board KV260 (target: `aarch64-linux-gnu`).

**`CMakeUserPresets.json`**
Preset build `debug-fpga` với flag `DGGML_USE_FPGA=ON`, cấu hình sẵn cho cross-compile.

**`tests/fpga_gemm_test.cpp`**
Unit test kiểm tra độ chính xác FPGA GEMM so với CPU reference: chạy cùng một phép GEMM trên cả hai đường, so sánh `max_diff` và `mean_diff`.

### Files sửa đổi

**`ggml/src/ggml-cpu/ggml-cpu.c`**
Thêm FPGA GEMM hook vào đầu hàm `ggml_compute_forward_mul_mat()` (trong block `#ifdef GGML_USE_FPGA`). Hook chỉ chạy trên thread `ith == 0` và kiểm tra đầy đủ: `fpga_gemm_is_ready()`, quant type hợp lệ, `src1->type == F32`, không batch (`ne02/ne03/ne12/ne13 == 1`), K khớp (`ne10 == ne00`), kích thước trong phạm vi (`< 65537`), và `block_aligned` (tùy quant type). Sau `fpga_gemm_run()` gọi `ggml_barrier()` để đồng bộ rồi `return` bỏ qua toàn bộ CPU path.

**`ggml/src/CMakeLists.txt`** và **`ggml/src/ggml-cpu/CMakeLists.txt`**
Thêm build target cho `FPGA_GEMM` và compile flag `GGML_USE_FPGA=ON/OFF`. Khi bật, `FPGA_GEMM.cpp` được thêm vào build.

---

## Tổ chức bộ nhớ trong DDR

<img width="352" height="587" alt="image" src="https://github.com/user-attachments/assets/06e73cc2-40d6-4904-b857-e0ca49c9282b" />


```

AXI-Lite / DMA Register Map:
  DMA_FEAT  0xA0000000  — MM2S gửi feature lên FPGA
  DMA_WGHT  0xA0010000  — MM2S gửi weight lên FPGA
  DMA_RSLT  0xA0020000  — S2MM nhận kết quả từ FPGA
  AXILITE   0xA0030000  — Control registers:
              +0x00  REG_SHIFT    = shift (số bit dịch phải output)
              +0x04  REG_F_LENGTH = M     (số hàng activation)
              +0x08  REG_F_WIDTH  = K_pad/32
              +0x0C  REG_W_WIDTH  = N_pad/32
```

Weight pool dùng allocator tuyến tính (`alloc_weight`): mỗi tensor được ghi một lần, align 64 byte, không bao giờ giải phóng trong session. `g_weight_cache` (hash map theo con trỏ `src0->data`) giúp bỏ qua bước dequant từ lần thứ hai trở đi — quan trọng với auto-regressive generation (mỗi token dùng lại cùng weight).

---

## Kết quả debug (Qwen2.5-0.5B, Q5_0)

| Thông số | Giá trị |
|----------|---------|
| Ma trận test | M=2, K=896, N=896 |
| Kiểu quant | Q5_0 |
| DMA time | ~19ms |
| scale_B (activation) | 0.01327 |
| scale_W (weight) | 0.00966 |
| out_scale | 0.01641 |
| max_diff (FPGA vs CPU) | 0.0627 |
| mean_diff | 0.0129 |

---

## Breakpoints debug

> 📄 **Tài liệu debug chi tiết (giá trị biến, screenshot debugger):**
> [llama.cpp debug session — Google Docs](https://docs.google.com/document/d/1uPPehYYf_vkRd8qAYk1fcu2wlW_GFQ006bVToX3j-AQ/edit?usp=sharing)

| # | Vị trí | Mục đích |
|---|--------|---------|
| BP1 | `ggml_compute_forward_mul_mat` dòng 1281 | Xem shape tensor đầu vào |
| BP2 | dòng 1314 | Xác nhận điều kiện FPGA & block alignment |
| BP3 | dòng 1323 | Xem tham số truyền vào `fpga_gemm_run()` |
| BP4 | `fpga_gemm_run` dòng 415 | Kiểm tra init & tham số đầu vào |
| BP5 | dòng 434 | Kết quả quantize activation |
| BP6 | dòng 473 | Weight cache & sanity check padding |
| BP7 | dòng 501 | Sau DMA: kiểm tra out_scale, dequant INT8 → F32, so sánh FPGA vs CPU reference |

---

## File test

`tests/fpga_gemm_test.cpp` kiểm tra độ chính xác của FPGA GEMM so với CPU reference float. Với mỗi test case, file này tạo weight ngẫu nhiên, encode sang định dạng quantized (Q5_0 / Q8_0 / Q4_K), chạy `fpga_gemm_run()`, rồi so sánh kết quả với CPU GEMM float qua `nRMSE`, `max_abs`, và tỉ lệ đúng dấu. Có 14 test case bao phủ các shape thực tế của model (896×896, 128×896, 4864×896...) và các trường hợp K/N không chia hết cho 32.

```bash
# Build trên Windows (dùng MSVC, không cần board)
cl /EHsc /I ggml\src\ggml-cpu\FPGA_GEMM ^
   tests\fpga_gemm_test.cpp ^
   ggml\src\ggml-cpu\FPGA_GEMM\FPGA_GEMM.cpp ^
   /Fe:fpga_test.exe
fpga_test.exe
```

Ngưỡng pass: `nRMSE < 0.30` với Q5_0/Q8_0, `nRMSE < 0.40` với Q4_K (do double-quantization), và tỉ lệ đúng dấu ≥ 80%.

---

## Build

```bash
# Cross-compile cho KV260
cmake --preset debug-fpga \
      -DCMAKE_TOOLCHAIN_FILE=cmake/aarch64-toolchain.cmake \
      -DGGML_USE_FPGA=ON
make -j$(nproc)
```

> Nếu bạn cần bổ sung thêm tài liệu (địa chỉ AXI-Lite cụ thể, cấu trúc FPGA IP, kết quả benchmark đầy đủ...), hãy gắn thêm vào để README được cập nhật chính xác hơn.
