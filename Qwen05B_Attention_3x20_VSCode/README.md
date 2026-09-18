# Qwen 0.5B attention visualization on VS Code

This project runs one forward pass of `Qwen/Qwen2.5-0.5B-Instruct`, collects
post-softmax attention at an exact sequence length of 1024, applies paper-style
block pruning with block size 3x20 and alpha 20, and exports PNG heatmaps.

## 1. Open the folder in VS Code

Open the `qwen05b_attention_vscode` folder, then open a terminal in that folder.

## 2. Create and activate a virtual environment

Windows PowerShell:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

If PowerShell blocks activation, run this once in the same terminal:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

## 3. Run the default experiment

```powershell
python visualize_attention.py
```

The default configuration is:

- Model: `Qwen/Qwen2.5-0.5B-Instruct`
- Exact input length: `N = 1024`
- Block size: `3x20`
- Alpha: `20`
- Threshold: `alpha/N = 0.01953125`
- Saved layers: first, middle, and last
- Saved maps: mean across all heads and head 0

## 4. Output

The program creates `attention_outputs` containing:

- `*_01_original.png`: original attention heatmap.
- `*_02_pruned.png`: attention after 3x20 block pruning.
- `*_03_block_mask.png`: white blocks are retained; black blocks are pruned.
- `*_04_comparison.png`: original, pruned, and removed mass side by side.
- `attention_pruning_metrics.csv`: block sparsity and removed attention mass.
- `experiment_config.json`: exact run configuration.
- `input_exact_1024_tokens.txt`: decoded text used by the model.

## Useful commands

Save only the mean-head maps by disabling individual heads:

```powershell
python visualize_attention.py --heads
```

Save layers 0, 6, 12, 18, and 23:

```powershell
python visualize_attention.py --layers 0 6 12 18 23 --heads 0 7
```

Use your own long UTF-8 text:

```powershell
python visualize_attention.py --text-file input.txt
```

Force CPU:

```powershell
python visualize_attention.py --cpu
```

## Interpretation

- A bright diagonal means tokens focus strongly on nearby preceding tokens.
- Bright early columns are attention sinks or important prefix tokens.
- A white mask region is a retained 3x20 block.
- A black mask region is a block removed because all three row sums were below
  `alpha/N`.
- The pruning output is not renormalized; it represents the matrix that would
  be used in the subsequent sparse `A @ V` operation.

