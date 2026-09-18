from __future__ import annotations

import argparse
import csv
import gc
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
from matplotlib.colors import LogNorm
from transformers import AutoModelForCausalLM, AutoTokenizer


DEFAULT_TEXT = """
Sparse attention reduces computation by retaining only the most important
connections between query and key tokens. A block-pruning method divides the
post-softmax attention matrix into small rectangular regions. Each region is
examined using the sum of the attention probabilities in its rows. Blocks with
little probability mass can be removed, while important blocks near the
diagonal, the first tokens, and semantically related positions are retained.

Hardware accelerators based on systolic arrays are efficient for regular dense
matrix multiplication. Sparse matrices, however, create irregular memory
accesses and poor processing-element utilization. Block aggregation restores a
regular execution order by merging column indices and inserting zero bubbles
where an attention row does not contain a retained block. The resulting data
stream can reuse a static GEMM datapath, although bubbles and index processing
still introduce overhead.

This experiment visualizes attention before and after block pruning. It uses a
sequence length of 1024 tokens and a three-by-twenty pruning block. The images
help reveal diagonal patterns, attention sinks in early columns, clusters, and
the block-shaped regions removed by pruning. The goal is analysis rather than
text generation, training, or hardware-performance measurement.
""".strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Visualize original and 3x20 block-pruned Qwen attention."
    )
    parser.add_argument(
        "--model",
        default="Qwen/Qwen2.5-0.5B-Instruct",
        help="Hugging Face model ID.",
    )
    parser.add_argument("--n", type=int, default=1024, help="Exact token count.")
    parser.add_argument("--alpha", type=float, default=20.0)
    parser.add_argument("--block-rows", type=int, default=3)
    parser.add_argument("--block-cols", type=int, default=20)
    parser.add_argument(
        "--layers",
        type=int,
        nargs="*",
        default=None,
        help="Layers to save. Default: first, middle, last.",
    )
    parser.add_argument(
        "--heads",
        type=int,
        nargs="*",
        default=(0,),
        help="Individual heads to save in addition to the mean-head map.",
    )
    parser.add_argument(
        "--text-file",
        type=Path,
        default=None,
        help="Optional UTF-8 input text. It is repeated/truncated to exactly N tokens.",
    )
    parser.add_argument("--output-dir", type=Path, default=Path("attention_outputs"))
    parser.add_argument(
        "--cpu",
        action="store_true",
        help="Force CPU even when CUDA is available.",
    )
    return parser.parse_args()


def build_exact_input(tokenizer, text: str, n: int) -> tuple[torch.Tensor, str]:
    if n <= 0:
        raise ValueError("N must be positive.")

    token_ids = tokenizer.encode(text, add_special_tokens=False)
    if not token_ids:
        raise ValueError("The input text produced no tokens.")

    bos_id = tokenizer.bos_token_id
    prefix = [bos_id] if bos_id is not None else []
    body_len = n - len(prefix)
    if body_len < 1:
        return torch.tensor([prefix[:n]], dtype=torch.long), ""

    repeats = math.ceil(body_len / len(token_ids))
    exact_ids = prefix + (token_ids * repeats)[:body_len]
    input_ids = torch.tensor([exact_ids], dtype=torch.long)
    decoded = tokenizer.decode(exact_ids, skip_special_tokens=False)
    return input_ids, decoded


def block_prune_attention(
    attention: torch.Tensor,
    alpha: float,
    n: int,
    block_rows: int,
    block_cols: int,
) -> tuple[torch.Tensor, torch.Tensor, dict[str, float]]:
    """Apply paper-style post-softmax block pruning to one [N, N] map.

    For every block, compute one sum per query row. Prune the entire block only
    when all row sums are smaller than t = alpha / N. No renormalization is
    applied because the pruned matrix is intended for the subsequent A @ V.
    """
    if attention.ndim != 2:
        raise ValueError(f"Expected [N,N], got {tuple(attention.shape)}")

    rows, cols = attention.shape
    threshold = alpha / float(n)
    pruned = attention.clone()
    n_block_rows = math.ceil(rows / block_rows)
    n_block_cols = math.ceil(cols / block_cols)
    keep_mask = torch.zeros(
        (n_block_rows, n_block_cols), dtype=torch.bool, device=attention.device
    )

    total_blocks = 0
    kept_blocks = 0
    original_mass = float(attention.sum().item())

    for br_idx, row_start in enumerate(range(0, rows, block_rows)):
        row_end = min(row_start + block_rows, rows)
        for bc_idx, col_start in enumerate(range(0, cols, block_cols)):
            col_end = min(col_start + block_cols, cols)
            block = attention[row_start:row_end, col_start:col_end]
            row_sums = block.sum(dim=-1)
            keep = bool(torch.any(row_sums >= threshold).item())
            total_blocks += 1
            keep_mask[br_idx, bc_idx] = keep
            if keep:
                kept_blocks += 1
            else:
                pruned[row_start:row_end, col_start:col_end] = 0

    remaining_mass = float(pruned.sum().item())
    removed_mass_fraction = (
        0.0 if original_mass == 0 else 1.0 - remaining_mass / original_mass
    )
    metrics = {
        "threshold": threshold,
        "total_blocks": total_blocks,
        "kept_blocks": kept_blocks,
        "pruned_blocks": total_blocks - kept_blocks,
        "block_sparsity": 1.0 - kept_blocks / max(total_blocks, 1),
        "original_attention_mass": original_mass,
        "remaining_attention_mass": remaining_mass,
        "removed_mass_fraction": removed_mass_fraction,
    }
    return pruned, keep_mask, metrics


def positive_limits(array: np.ndarray) -> tuple[float, float]:
    positive = array[array > 0]
    if positive.size == 0:
        return 1e-8, 1.0
    vmin = max(float(np.percentile(positive, 1.0)), 1e-8)
    vmax = max(float(np.percentile(positive, 99.9)), vmin * 10.0)
    return vmin, vmax


def save_heatmap(
    array: np.ndarray,
    destination: Path,
    title: str,
    vmin: float,
    vmax: float,
) -> None:
    fig, ax = plt.subplots(figsize=(8.2, 7.2), dpi=170)
    image = ax.imshow(
        np.maximum(array, vmin),
        origin="upper",
        aspect="auto",
        interpolation="nearest",
        cmap="magma",
        norm=LogNorm(vmin=vmin, vmax=vmax),
    )
    ax.set_title(title)
    ax.set_xlabel("Key-token index")
    ax.set_ylabel("Query-token index")
    colorbar = fig.colorbar(image, ax=ax, fraction=0.046, pad=0.04)
    colorbar.set_label("Attention probability (log scale)")
    fig.tight_layout()
    fig.savefig(destination, bbox_inches="tight")
    plt.close(fig)


def save_mask(
    keep_mask: np.ndarray,
    destination: Path,
    title: str,
) -> None:
    fig, ax = plt.subplots(figsize=(10.0, 7.0), dpi=170)
    image = ax.imshow(
        keep_mask,
        origin="upper",
        aspect="auto",
        interpolation="nearest",
        cmap="gray_r",
        vmin=0,
        vmax=1,
    )
    ax.set_title(title + " (white = kept, black = pruned)")
    ax.set_xlabel("Key-block index (20 tokens/block)")
    ax.set_ylabel("Query-block index (3 tokens/block)")
    fig.colorbar(image, ax=ax, ticks=[0, 1], fraction=0.025, pad=0.03)
    fig.tight_layout()
    fig.savefig(destination, bbox_inches="tight")
    plt.close(fig)


def save_comparison(
    original: np.ndarray,
    pruned: np.ndarray,
    destination: Path,
    title: str,
) -> None:
    vmin, vmax = positive_limits(original)
    removed = np.clip(original - pruned, 0.0, None)
    fig, axes = plt.subplots(1, 3, figsize=(18.0, 5.7), dpi=150)
    arrays = (original, pruned, removed)
    labels = ("Original A", "After 3x20 pruning", "Removed attention mass")
    for ax, data, label in zip(axes, arrays, labels):
        image = ax.imshow(
            np.maximum(data, vmin),
            origin="upper",
            aspect="auto",
            interpolation="nearest",
            cmap="magma",
            norm=LogNorm(vmin=vmin, vmax=vmax),
        )
        ax.set_title(label)
        ax.set_xlabel("Key-token index")
        ax.set_ylabel("Query-token index")
    fig.suptitle(title)
    fig.colorbar(image, ax=axes, fraction=0.018, pad=0.02)
    fig.subplots_adjust(left=0.05, right=0.92, bottom=0.10, top=0.86, wspace=0.20)
    fig.savefig(destination, bbox_inches="tight")
    plt.close(fig)


def analyze_map(
    attention_map: torch.Tensor,
    layer_idx: int,
    map_name: str,
    args: argparse.Namespace,
    metrics_rows: list[dict[str, object]],
) -> None:
    attention_map = attention_map.detach().float().cpu()
    pruned, keep_mask, metrics = block_prune_attention(
        attention_map,
        alpha=args.alpha,
        n=args.n,
        block_rows=args.block_rows,
        block_cols=args.block_cols,
    )
    original_np = attention_map.numpy()
    pruned_np = pruned.numpy()
    keep_np = keep_mask.numpy().astype(np.uint8)
    vmin, vmax = positive_limits(original_np)

    safe_name = map_name.replace(" ", "_")
    stem = f"layer_{layer_idx:02d}_{safe_name}"
    save_heatmap(
        original_np,
        args.output_dir / f"{stem}_01_original.png",
        f"Layer {layer_idx} - {map_name} - original attention",
        vmin,
        vmax,
    )
    save_heatmap(
        pruned_np,
        args.output_dir / f"{stem}_02_pruned.png",
        f"Layer {layer_idx} - {map_name} - pruned (3x20, alpha={args.alpha:g})",
        vmin,
        vmax,
    )
    save_mask(
        keep_np,
        args.output_dir / f"{stem}_03_block_mask.png",
        f"Layer {layer_idx} - {map_name} - block keep mask",
    )
    save_comparison(
        original_np,
        pruned_np,
        args.output_dir / f"{stem}_04_comparison.png",
        f"Layer {layer_idx} - {map_name}; N={args.n}, block=3x20, alpha={args.alpha:g}",
    )

    metrics_rows.append(
        {
            "layer": layer_idx,
            "map": map_name,
            **metrics,
        }
    )


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    use_cuda = torch.cuda.is_available() and not args.cpu
    device = torch.device("cuda" if use_cuda else "cpu")
    dtype = torch.float16 if use_cuda else torch.float32

    print(f"Model       : {args.model}")
    print(f"Device      : {device}")
    print(f"N           : {args.n}")
    print(f"Alpha       : {args.alpha}")
    print(f"Block       : {args.block_rows}x{args.block_cols}")
    print(f"Threshold   : alpha/N = {args.alpha / args.n:.8f}")

    text = (
        args.text_file.read_text(encoding="utf-8")
        if args.text_file is not None
        else DEFAULT_TEXT
    )

    print("\n[1/4] Loading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    input_ids, decoded_text = build_exact_input(tokenizer, text, args.n)
    attention_mask = torch.ones_like(input_ids)
    (args.output_dir / "input_exact_1024_tokens.txt").write_text(
        decoded_text, encoding="utf-8"
    )

    print("[2/4] Loading model with eager attention...")
    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        torch_dtype=dtype,
        attn_implementation="eager",
        trust_remote_code=True,
        low_cpu_mem_usage=True,
    ).to(device)
    model.eval()

    input_ids = input_ids.to(device)
    attention_mask = attention_mask.to(device)

    print("[3/4] Running one forward pass and collecting attention...")
    with torch.inference_mode():
        outputs = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            use_cache=False,
            output_attentions=True,
            return_dict=True,
        )

    attentions = outputs.attentions
    if attentions is None:
        raise RuntimeError(
            "The model returned no attention. Ensure attn_implementation='eager'."
        )

    num_layers = len(attentions)
    num_heads = int(attentions[0].shape[1])
    selected_layers = (
        sorted(set(args.layers))
        if args.layers
        else sorted({0, num_layers // 2, num_layers - 1})
    )
    for layer_idx in selected_layers:
        if not 0 <= layer_idx < num_layers:
            raise ValueError(
                f"Layer {layer_idx} is invalid; model has layers 0..{num_layers - 1}."
            )
    for head_idx in args.heads:
        if not 0 <= head_idx < num_heads:
            raise ValueError(
                f"Head {head_idx} is invalid; model has heads 0..{num_heads - 1}."
            )

    print(
        f"Collected  : {num_layers} layers, {num_heads} heads, "
        f"shape={tuple(attentions[0].shape)}"
    )
    print(f"Saving     : layers {selected_layers}; individual heads {list(args.heads)}")
    print("[4/4] Pruning selected maps and writing figures...")

    metrics_rows: list[dict[str, object]] = []
    for layer_idx in selected_layers:
        layer_attention = attentions[layer_idx][0]
        analyze_map(
            layer_attention.mean(dim=0),
            layer_idx,
            "mean_heads",
            args,
            metrics_rows,
        )
        for head_idx in args.heads:
            analyze_map(
                layer_attention[head_idx],
                layer_idx,
                f"head_{head_idx:02d}",
                args,
                metrics_rows,
            )
        print(f"  Finished layer {layer_idx}")

    csv_path = args.output_dir / "attention_pruning_metrics.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(metrics_rows[0].keys()))
        writer.writeheader()
        writer.writerows(metrics_rows)

    config = {
        "model": args.model,
        "n": args.n,
        "alpha": args.alpha,
        "threshold_alpha_over_n": args.alpha / args.n,
        "block_rows": args.block_rows,
        "block_cols": args.block_cols,
        "device": str(device),
        "dtype": str(dtype),
        "num_layers": num_layers,
        "num_attention_heads": num_heads,
        "selected_layers": selected_layers,
        "selected_individual_heads": list(args.heads),
        "note": "Pruning is applied to post-softmax attention without renormalization.",
    }
    (args.output_dir / "experiment_config.json").write_text(
        json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    del outputs, attentions, model
    gc.collect()
    if use_cuda:
        torch.cuda.empty_cache()

    print("\nDONE")
    print(f"Images and metrics: {args.output_dir.resolve()}")
    print(f"Metrics CSV       : {csv_path.resolve()}")


if __name__ == "__main__":
    main()

