import re
import ast
import numpy as np
from pathlib import Path


# =========================
# CONFIG
# =========================
LOG_PATH = r"e:\Everything_with_VIVADO\MM_final\python\data.txt"

SHIFT = 9
ROUND_BIAS = 1 << (SHIFT - 1)   # 256 neu SHIFT = 9

INT8_MIN = -128
INT8_MAX = 127


# =========================
# READ FILE
# =========================
def read_text(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


# =========================
# READ MATRIX x, y
# =========================
def get_matrix(text, label):
    m = re.search(rf"(?m)^\s*{label}\s*:\s*$", text)

    if not m:
        raise ValueError(f"Khong tim thay label {label}:")

    start = text.find("[", m.end())

    if start == -1:
        raise ValueError(f"Khong tim thay dau '[' sau {label}:")

    depth = 0

    for i in range(start, len(text)):
        if text[i] == "[":
            depth += 1

        elif text[i] == "]":
            depth -= 1

            if depth == 0:
                matrix_text = text[start:i + 1]
                return np.array(ast.literal_eval(matrix_text), dtype=np.int64)

    raise ValueError(f"Khong doc duoc ma tran {label}")


# =========================
# READ HARDWARE OUTPUT
# =========================
def get_output_flat(text, label, shape):
    m = re.search(rf"(?m)^\s*{label}\s*:\s*$", text)

    if not m:
        raise ValueError(f"Khong tim thay label {label}:")

    block = text[m.end():]

    # Cat bot phan ket thuc simulation neu co
    for key in ["No Error", "No zero_error", "$finish"]:
        pos = block.find(key)

        if pos != -1:
            block = block[:pos]

    nums = [int(x) for x in re.findall(r"[-+]?\d+", block)]

    expected = shape[0] * shape[1]

    if len(nums) != expected:
        raise ValueError(
            f"{label} co {len(nums)} phan tu, nhung can {expected}"
        )

    return np.array(nums, dtype=np.int64).reshape(shape)


# =========================
# SATURATE INT8
# =========================
def saturate_int8(x):
    return np.clip(x, INT8_MIN, INT8_MAX)


# =========================
# MAIN
# =========================
def main():
    text = read_text(LOG_PATH)

    # Trong file log:
    # x = F / feature matrix
    # y = W / weight matrix
    F = get_matrix(text, "x")
    W = get_matrix(text, "y")

    output_shape = (F.shape[0], W.shape[1])

    # Output hardware tu Vivado
    z_hard = get_output_flat(text, "z_hard", output_shape)

    # Software GEMM giong hardware:
    # acc = F @ W
    # z_soft = saturate_int8((acc + 256) >> 9)
    acc = F @ W
    z_soft = saturate_int8((acc + ROUND_BIAS) >> SHIFT)

    # So sanh
    diff = z_soft - z_hard
    mismatch = np.count_nonzero(diff)

    total = z_hard.size
    match_count = total - mismatch
    match_rate = match_count / total * 100

    print("========== MATRIX INFO ==========")
    print("F shape      :", F.shape)
    print("W shape      :", W.shape)
    print("Output shape :", z_hard.shape)

    print()
    print("========== COMPARE ==========")
    print("Total elements:", total)
    print("Match count   :", match_count)
    print("Mismatch      :", mismatch)
    print("Match rate    :", f"{match_rate:.6f}%")

    if mismatch == 0:
        print("PASS")
    else:
        print("FAIL")


if __name__ == "__main__":
    main()