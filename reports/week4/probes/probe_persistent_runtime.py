r"""W4 计划前置探针：把 W3 的「每向量起一个 Python 进程」换成常驻进程能省多少。

W3 的实测是 97 条向量 201993 ms ≈ 2082 ms/条（`reports/week3/logs/embed_probe_samples.txt`）。
本探针把同一个模型分别用两种方式跑同一批真实文本，给出可引用的对比数字：

  one_shot   —— 每条向量一次 `python embed_text_hidden.py`（W3 现状）
  persistent —— 一个进程内加载一次模型，逐条前向（W4 目标形态）
  batched    —— 同一进程内按批前向（W4 目标形态）

用法（仓库根目录）：
    engine\.venv\Scripts\python.exe week4\probes\probe_persistent_runtime.py
"""

from __future__ import annotations

import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

from w3_embed_lib import TEXT_DIR, load_tokenizer, session  # noqa: E402

MODEL = TEXT_DIR / "onnx" / "model.onnx"
TOKENIZER = TEXT_DIR / "tokenizer.json"
SCRIPT = ROOT / "engine" / "embed_text_hidden.py"
PYTHON = sys.executable

# 真实语料：仓库自己的 md 文档，按 120 字符切，和 CascadeTextChunker 的窗口一致。
CORPUS = sorted(
    [*(ROOT / "docs").rglob("*.md"), *(ROOT / "reports").rglob("*.md")]
)


def corpus_texts(limit: int) -> list[str]:
    texts: list[str] = []
    for path in CORPUS:
        body = path.read_text(encoding="utf-8")
        for start in range(0, len(body), 120):
            piece = body[start : start + 120].strip()
            if len(piece) >= 20:
                texts.append(piece)
            if len(texts) >= limit:
                return texts
    return texts


def one_shot(tokenizer, texts: list[str]) -> list[float]:
    samples: list[float] = []
    for text in texts:
        encoding = tokenizer.encode(text)
        payload = {
            "model_path": str(MODEL),
            "input_ids": encoding.ids,
            "attention_mask": encoding.attention_mask,
            "token_type_ids": encoding.type_ids,
        }
        temp = ROOT / "week4" / "probes" / "_oneshot_request.json"
        temp.write_text(json.dumps(payload), encoding="utf-8")
        started = time.perf_counter()
        subprocess.run(
            [PYTHON, str(SCRIPT), str(temp)],
            check=True,
            capture_output=True,
        )
        samples.append((time.perf_counter() - started) * 1000)
        temp.unlink(missing_ok=True)
    return samples


def persistent(tokenizer, model, texts: list[str]) -> list[float]:
    samples: list[float] = []
    for text in texts:
        encoding = tokenizer.encode(text)
        feeds = {
            "input_ids": np.asarray([encoding.ids], dtype=np.int64),
            "attention_mask": np.asarray([encoding.attention_mask], dtype=np.int64),
            "token_type_ids": np.asarray([encoding.type_ids], dtype=np.int64),
        }
        started = time.perf_counter()
        model.run(["last_hidden_state"], feeds)
        samples.append((time.perf_counter() - started) * 1000)
    return samples


def batched(tokenizer, model, texts: list[str], size: int) -> float:
    encodings = [tokenizer.encode(text) for text in texts]
    feeds = {
        "input_ids": np.asarray([e.ids for e in encodings], dtype=np.int64),
        "attention_mask": np.asarray([e.attention_mask for e in encodings], dtype=np.int64),
        "token_type_ids": np.asarray([e.type_ids for e in encodings], dtype=np.int64),
    }
    started = time.perf_counter()
    model.run(["last_hidden_state"], feeds)
    return (time.perf_counter() - started) * 1000 / size


def stats(label: str, samples: list[float], count: int | None = None) -> None:
    ordered = sorted(samples)
    n = count if count is not None else len(ordered)
    print(
        f"{label} n={n} median_ms={statistics.median(ordered):.1f} "
        f"p90_ms={ordered[int(len(ordered) * 0.9) - 1]:.1f} "
        f"max_ms={ordered[-1]:.1f} total_ms={sum(ordered):.0f}"
    )


def main() -> int:
    texts = corpus_texts(24)
    print(f"corpus_files={len(CORPUS)} texts={len(texts)} script={SCRIPT.name}")

    tokenizer, _pad = load_tokenizer(TOKENIZER, 128)

    shots = one_shot(tokenizer, texts)
    stats("one_shot", shots)

    started = time.perf_counter()
    model = session(MODEL)
    load_ms = (time.perf_counter() - started) * 1000
    print(f"session_load_ms={load_ms:.0f}")

    keep = persistent(tokenizer, model, texts)
    stats("persistent", keep)

    for size in (8, 16):
        per_item = batched(tokenizer, model, texts[:size], size)
        print(f"batched size={size} per_item_ms={per_item:.1f}")

    print(
        f"speedup_one_shot_over_persistent="
        f"{statistics.median(shots) / statistics.median(keep):.1f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
