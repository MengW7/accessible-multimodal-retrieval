"""Export the sample chunks and the 25 frozen questions as float32 vectors.

Chunk boundaries come from the Dart chunker, so chunk ids match the product.
Both stores later decode vectorB64. They do not embed again.

    python engine/export_vectors.py --path datasets/samples --out reports/week4/vectors/w3_samples.jsonl
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "engine"))

from w3_embed_lib import (  # noqa: E402
    CLIP_MAX_LEN,
    IMAGE_DIR,
    TEXT_DIR,
    TEXT_MAX_LEN,
    encode_text,
    image_feeds,
    l2_normalize,
    load_tokenizer,
    preprocess_image,
    session,
)

EVIDENCE = ROOT / "reports" / "week3" / "evidence_set.jsonl"
TEXT_MODEL = TEXT_DIR / "onnx" / "model.onnx"
TEXT_TOKENIZER = TEXT_DIR / "tokenizer.json"
VISION_MODEL = IMAGE_DIR / "onnx" / "vision_model.onnx"
CLIP_TEXT_MODEL = IMAGE_DIR / "onnx" / "text_model.onnx"
CLIP_TOKENIZER = IMAGE_DIR / "tokenizer.json"
# PATH 上的 dart 是 dart.bat，CreateProcess 不会执行它。这里用 SDK 里的 exe。
DART = Path(r"D:\flutter\bin\cache\dart-sdk\bin\dart.exe")
if not DART.is_file():
    DART = Path("dart")
EXPECTED_SAMPLES = 97


def _b64(vector: np.ndarray) -> str:
    raw = np.ascontiguousarray(vector, dtype="<f4").reshape(-1).tobytes()
    return base64.b64encode(raw).decode("ascii")


def _normalize(vector: np.ndarray, dim: int, label: str) -> np.ndarray:
    flat = np.asarray(vector, dtype=np.float64).reshape(-1)
    if flat.shape != (dim,):
        raise RuntimeError(f"{label} dim {flat.shape[0]} is not {dim}")
    if not np.isfinite(flat).all():
        raise RuntimeError(f"{label} is non-finite")
    normalized, _norm = l2_normalize(flat)
    return np.ascontiguousarray(normalized, dtype=np.float32)


def _mean_pool(hidden: np.ndarray, mask: np.ndarray) -> np.ndarray:
    array = np.asarray(hidden, dtype=np.float32)
    if array.ndim == 3:
        array = array[0]
    weights = np.asarray(mask, dtype=np.float32).reshape(-1)
    if array.shape[0] != weights.shape[0]:
        raise RuntimeError(
            f"hidden rows {array.shape[0]} do not match mask {weights.shape[0]}"
        )
    counted = float(weights.sum())
    if counted <= 0:
        raise RuntimeError("attention mask is empty")
    return (array * weights[:, None]).sum(axis=0) / counted


def _dump_chunks(samples: Path) -> list[dict]:
    completed = subprocess.run(
        [
            DART,
            "run",
            "packages/core_embedding/bin/dump_chunks.dart",
            "--path",
            str(samples),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"dump_chunks exited {completed.returncode}")
    rows = []
    for line in completed.stdout.splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def _write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows)
    path.write_text(text, encoding="utf-8", newline="\n")


def _evidence_rows() -> list[dict]:
    rows = []
    for line in EVIDENCE.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    if len(rows) != 25:
        raise RuntimeError(f"evidence set has {len(rows)} rows, expected 25")
    return rows


def _encode_caption(tokenizer, pad_id: int, text: str) -> np.ndarray:
    ids = tokenizer.encode(text).ids
    if len(ids) > CLIP_MAX_LEN:
        raise RuntimeError(f"{len(ids)} tokens exceed {CLIP_MAX_LEN}")
    padded = np.full((1, CLIP_MAX_LEN), pad_id, dtype=np.int64)
    padded[0, : len(ids)] = np.asarray(ids, dtype=np.int64)
    return padded


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default="datasets/samples")
    parser.add_argument("--out", default="reports/week4/vectors/w3_samples.jsonl")
    args = parser.parse_args()
    samples = Path(args.path)
    if not samples.is_absolute():
        samples = ROOT / samples
    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out

    rows = _dump_chunks(samples)
    if len(rows) != EXPECTED_SAMPLES:
        raise RuntimeError(
            f"sample export has {len(rows)} rows, expected {EXPECTED_SAMPLES}"
        )
    seen: set[str] = set()
    for row in rows:
        chunk_id = row["chunkId"]
        if chunk_id in seen:
            raise RuntimeError(f"duplicate chunkId {chunk_id}")
        seen.add(chunk_id)

    text_tokenizer, _pad = load_tokenizer(TEXT_TOKENIZER, TEXT_MAX_LEN)
    text_model = session(TEXT_MODEL)
    vision = session(VISION_MODEL)
    clip_tokenizer = __import__("tokenizers").Tokenizer.from_file(str(CLIP_TOKENIZER))
    clip_tokenizer.no_truncation()
    pad_id = clip_tokenizer.token_to_id("!")
    if pad_id is None:
        raise RuntimeError("CLIP tokenizer has no '!' pad id")
    clip_text = session(CLIP_TEXT_MODEL)

    exported = []
    for row in rows:
        if row["modality"] == "image":
            image = ROOT / row["imagePath"]
            raw = vision.run(["image_embeds"], image_feeds(vision, preprocess_image(image)))[0]
            vector = _normalize(raw, 512, row["chunkId"])
        else:
            feeds = encode_text(text_tokenizer, row["body"], text_model)
            hidden = text_model.run(["last_hidden_state"], feeds)[0]
            pooled = _mean_pool(hidden, feeds["attention_mask"])
            vector = _normalize(pooled, 384, row["chunkId"])
        exported.append({**row, "normalized": True, "vectorB64": _b64(vector)})
    _write(out, exported)

    evidence_images = []
    image_keys: set[str] = set()
    for row in _evidence_rows():
        if row.get("modality") != "image":
            continue
        key = str(row["relevantDocumentId"]).replace("\\", "/")
        if key.startswith("datasets/samples/") or key in image_keys:
            continue
        image_keys.add(key)
        path = ROOT / key
        raw = vision.run(["image_embeds"], image_feeds(vision, preprocess_image(path)))[0]
        vector = _normalize(raw, 512, key)
        evidence_images.append(
            {
                "space": "clipShared",
                "dim": 512,
                "modelId": "mobileclip-s0-vision",
                "chunkId": key,
                "normalized": True,
                "vectorB64": _b64(vector),
                "relativePath": Path(key).name,
                "documentKey": key,
                "fileName": Path(key).name,
                "extension": Path(key).suffix.lower(),
                "mimeType": "image/jpeg",
                "pageNumber": None,
                "startOffset": 0,
                "endOffset": 0,
                "chunkIndex": None,
                "body": "",
                "modality": "image",
                "contentHash": key,
                "parserName": "image",
                "parserVersion": "1",
                "chunkerVersion": "none",
                "documentId": key,
                "imagePath": key,
            }
        )
    evidence_out = out.parent / "w3_evidence_images.jsonl"
    _write(evidence_out, evidence_images)

    queries = []
    for row in _evidence_rows():
        question = row["question"]
        if row.get("modality") == "image":
            ids = _encode_caption(clip_tokenizer, pad_id, question)
            raw = clip_text.run(["text_embeds"], {"input_ids": ids})[0]
            vector = _normalize(raw, 512, row["id"])
            queries.append(
                {
                    "id": row["id"],
                    "space": "clipShared",
                    "dim": 512,
                    "modelId": "mobileclip-s0-text",
                    "vectorB64": _b64(vector),
                    "question": question,
                }
            )
        else:
            feeds = encode_text(text_tokenizer, question, text_model)
            hidden = text_model.run(["last_hidden_state"], feeds)[0]
            pooled = _mean_pool(hidden, feeds["attention_mask"])
            vector = _normalize(pooled, 384, row["id"])
            queries.append(
                {
                    "id": row["id"],
                    "space": "documentText",
                    "dim": 384,
                    "modelId": "paraphrase-multilingual-MiniLM-L12-v2",
                    "vectorB64": _b64(vector),
                    "question": question,
                }
            )
    query_out = out.parent / "w3_queries.jsonl"
    _write(query_out, queries)
    print(f"samples={len(exported)} evidence_images={len(evidence_images)} queries={len(queries)}")
    print(f"out={out.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
