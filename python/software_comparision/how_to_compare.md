# How to Run the GEMM Verification Script

## Step 1: Run FPGA Simulation

Run the GEMM accelerator on the FPGA and print the following matrices to the console:

- Input Matrix A
- Input Matrix B
- Output Matrix C

## Step 2: Save Matrices

Copy the printed matrices and paste them into `data.txt`.

Example:

```txt
Matrix A:
1 2 3
4 5 6

Matrix B:
7 8
9 10
11 12

Matrix C:
58 64
139 154
```

## Step 3: Update Python Script

Open the Python verification script and update the path of `data.txt`.

Example:

```python
DATA_FILE = "D:/GEMM_Test/data.txt"
```

## Step 4: Run the Python Script

```bash
python verify.py
```

The script will:

- Parse Matrix A, Matrix B, and Matrix C from `data.txt`
- Compute the reference result using NumPy
- Compare the FPGA output with the software result
- Report whether the verification passes or fails

Enjoy! 🚀
