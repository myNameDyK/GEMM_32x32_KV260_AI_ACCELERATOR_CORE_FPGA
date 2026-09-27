# Attention Sparsity Block Pruning Survey

This notebook is intended to be run on **Google Colab with an NVIDIA GPU**.

## Requirements

- Google Colab with GPU enabled
- Hugging Face account
- Access to the gated model:
  `meta-llama/Llama-2-7b-chat-hf`
- Hugging Face token with permission to download the model
- Internet connection for downloading the model, LongBench, datasets, and Python packages

## Run

Open `OFFICIAL_SPARSITY_TEST.ipynb` in Google Colab.

Enable GPU:

`Runtime -> Change runtime type -> GPU`

Then run the notebook **from top to bottom**.

When the Hugging Face login cell appears:

```python
from huggingface_hub import login
login()
```

enter your Hugging Face token.

The notebook automatically installs the required packages and clones LongBench into:

```text
/content/LongBench
```

When prompted:

```text
Select task (A=row, B=column, C=2D):
```

choose one of:

```text
A
B
C
```

Then continue running the remaining cells in order.

The dense baseline must finish before the block sweep is started.

Expected dense result:

```text
pred/dense/result.json
```

The complete block sweep then generates sparse predictions, evaluates them with the official LongBench evaluator, and saves the final results.

## Output

Predictions and LongBench evaluation results:

```text
pred/
├── dense/
│   ├── narrativeqa.jsonl
│   ├── qasper.jsonl
│   ├── gov_report.jsonl
│   └── result.json
│
├── sparse_<rows>x<cols>/
│   ├── narrativeqa.jsonl
│   ├── qasper.jsonl
│   ├── gov_report.jsonl
│   └── result.json
│
└── ...
```

Final block-sweep results:

```text
results/
├── block_sweep_results.json
└── block_sweep_results.csv
```

The last cells also plot:

- sparsity vs. block size
- average score loss vs. block size
- LongBench average score vs. block size

## Important Notes

1. **Use a GPU runtime.**  
   The notebook loads a 7B model with 4-bit quantization and is not intended for a CPU-only Colab runtime.

2. **The Hugging Face model is gated.**  
   Before running the notebook, make sure your Hugging Face account has access to:

   ```text
   meta-llama/Llama-2-7b-chat-hf
   ```

3. **The current notebook uses Llama-2-7B-chat-hf.**  
   Even if the surrounding directory or older experiment name contains `Qwen05B`, the current notebook variable is:

   ```python
   MODEL_NAME = "meta-llama/Llama-2-7b-chat-hf"
   ```

4. **Do not skip the dense baseline.**  
   The block sweep requires:

   ```text
   pred/dense/result.json
   ```

   If it does not exist, the sweep will stop.

5. **Run cells in order after restarting the Colab runtime.**  
   Several later cells depend on variables, model hooks, LongBench configuration files, and functions defined earlier in the notebook.

6. **Do not delete `/content/LongBench` while the notebook is running.**  
   The evaluator and configuration files are read directly from this path.

7. **Colab storage is temporary.**  
   Files under `/content` can disappear when the runtime is reset or disconnected. Download or copy the `results/` directory after an experiment if the results need to be preserved.

8. **The block sweep can resume from completed results.**  
   If:

   ```text
   results/block_sweep_results.json
   ```

   already exists in the current runtime, completed block sizes are loaded and skipped.

9. **Keep the task selection fixed for one sweep.**  
   If switching between Task A, B, and C, it is safer to use a fresh result directory or remove the previous `results/block_sweep_results.json` so results from different search spaces are not mixed.

10. **Do not change the LongBench directory structure unless the paths in the notebook are also updated.**

11. **Generated prediction folders must follow the expected names.**  
    The evaluator expects names such as:

    ```text
    pred/dense/
    pred/sparse_3x20/
    pred/sparse_32x32/
    ```

12. **If Colab runs out of GPU memory**, restart the runtime and run the notebook again from the beginning. Avoid keeping additional large models or tensors in memory in the same session.

13. **Do not interrupt a block while its predictions are being generated.**  
    A partially generated prediction directory may not contain a valid `result.json`.

14. After the sweep finishes, verify that both files exist before closing the Colab session:

    ```text
    results/block_sweep_results.json
    results/block_sweep_results.csv
    ```
