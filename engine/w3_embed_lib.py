"""Shared ONNX embedding helpers for the Week 3 Day 1 probes.

Neither script imports torch. Inference uses the onnxruntime already
installed in engine/.venv. Graph optimization is disabled while scoring a
file, so a cosine gap is the file itself and not a session rewrite.
"""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image
from tokenizers import Tokenizer

ROOT = Path(__file__).resolve().parents[1]

TEXT_DIR = (
    ROOT / "models" / "raw" / "text" / "paraphrase-multilingual-MiniLM-L12-v2"
)
IMAGE_DIR = ROOT / "models" / "raw" / "image" / "mobileclip-s0"

TEXT_MAX_LEN = 128
CLIP_MAX_LEN = 77
IMAGE_EDGE = 256

# Five sentences: one Chinese, one English, then three more for the
# conversion gate (the plan asks for 3–5). The Chinese sentence is the
# Day 1 language check.
SENTENCES: tuple[tuple[str, str], ...] = (
    ("zh", "离线检索可以在没有网络的电脑上运行。"),
    ("en", "Offline retrieval runs on a computer without a network."),
    ("en", "The Apollo 17 crew left the Moon in December 1972."),
    ("zh", "这份文档记录了页码和字符偏移。"),
    ("en", "A man is in a kitchen making pizzas."),
)

COCO_SPIKE = (
    ROOT
    / "datasets"
    / "coco"
    / "val_sample"
    / "images"
    / "000000397133.jpg"
)
COCO_CONVERT = (
    COCO_SPIKE,
    ROOT / "datasets" / "coco" / "val_sample" / "images" / "000000006818.jpg",
    ROOT / "datasets" / "coco" / "val_sample" / "images" / "000000017627.jpg",
)

COSINE_GATE = 0.999


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def file_line(path: Path) -> str:
    return f"{path.name} bytes={path.stat().st_size} sha256={file_sha256(path)}"


def tokenizer_kind(path: Path) -> str:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    model = data.get("model", {})
    kind = str(model.get("type", "unknown"))
    vocab = model.get("vocab")
    size = len(vocab) if isinstance(vocab, (dict, list)) else 0
    normalizer = data.get("normalizer") if isinstance(data.get("normalizer"), dict) else {}
    return (
        f"type={kind} vocab_size={size} "
        f"normalizer={normalizer.get('type', 'none')} "
        f"lowercase={normalizer.get('lowercase')}"
    )


def _np_int(ort_type: str) -> np.dtype:
    if "int64" in ort_type:
        return np.dtype(np.int64)
    if "int32" in ort_type:
        return np.dtype(np.int32)
    raise ValueError(f"unsupported integer onnx type {ort_type}")


def _pad_token(path: Path, tokenizer: Tokenizer) -> tuple[str, int]:
    config_path = path.with_name("tokenizer_config.json")
    candidates: list[str] = []
    if config_path.is_file():
        pad = json.loads(config_path.read_text(encoding="utf-8")).get("pad_token")
        if isinstance(pad, dict):
            pad = pad.get("content")
        if isinstance(pad, str):
            candidates.append(pad)
    candidates.extend(("<pad>", "[PAD]", "<|endoftext|>"))
    seen: set[str] = set()
    for token in candidates:
        if token in seen:
            continue
        seen.add(token)
        pad_id = tokenizer.token_to_id(token)
        if pad_id is not None:
            return token, pad_id
    raise RuntimeError(f"{path} has no usable pad token")


def load_tokenizer(path: Path, max_len: int) -> tuple[Tokenizer, int]:
    tokenizer = Tokenizer.from_file(str(path))
    pad_token, pad_id = _pad_token(path, tokenizer)
    tokenizer.enable_truncation(max_length=max_len)
    tokenizer.enable_padding(length=max_len, pad_id=pad_id, pad_token=pad_token)
    return tokenizer, pad_id


def session(path: Path) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    return ort.InferenceSession(
        str(path),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )


def signature_lines(model: ort.InferenceSession) -> list[str]:
    lines = []
    for item in model.get_inputs():
        lines.append(f"input name={item.name} type={item.type} shape={item.shape}")
    for item in model.get_outputs():
        lines.append(
            f"output name={item.name} type={item.type} shape={item.shape}"
        )
    return lines


def content_token_stats(tokenizer: Tokenizer, text: str) -> tuple[int, int]:
    encoding = tokenizer.encode(text)
    special = {
        tokenizer.token_to_id(token)
        for token in ("<s>", "</s>", "<pad>", "<unk>", "[CLS]", "[SEP]", "[PAD]", "[UNK]")
    }
    special.discard(None)
    unk = tokenizer.token_to_id("<unk>")
    if unk is None:
        unk = tokenizer.token_to_id("[UNK]")
    content = [token for token in encoding.ids if token not in special]
    unk_count = sum(1 for token in content if token == unk)
    return len(content), unk_count


def encode_text(
    tokenizer: Tokenizer,
    text: str,
    model: ort.InferenceSession,
) -> dict[str, np.ndarray]:
    encoding = tokenizer.encode(text)
    feeds: dict[str, np.ndarray] = {}
    for item in model.get_inputs():
        name = item.name
        dtype = _np_int(item.type)
        if name == "input_ids":
            feeds[name] = np.asarray([encoding.ids], dtype=dtype)
        elif name == "attention_mask":
            feeds[name] = np.asarray([encoding.attention_mask], dtype=dtype)
        elif name == "token_type_ids":
            feeds[name] = np.asarray([encoding.type_ids], dtype=dtype)
        else:
            raise RuntimeError(f"unexpected text input {name}")
    return feeds


def _as_vector(array: np.ndarray, feeds: dict[str, np.ndarray]) -> np.ndarray:
    array = array.astype(np.float32)
    if array.ndim == 3:
        mask = feeds.get("attention_mask")
        if mask is not None:
            weights = mask.astype(np.float32)[..., None]
            summed = (array * weights).sum(axis=1)
            counts = np.clip(weights.sum(axis=1), 1e-9, None)
            return summed[0] / counts[0]
        return array.mean(axis=1)[0]
    if array.ndim == 2:
        return array[0]
    return array.reshape(-1)


def vector_from_outputs(
    model: ort.InferenceSession,
    feeds: dict[str, np.ndarray],
    values: list[np.ndarray],
) -> np.ndarray:
    """Pick the sentence or image embedding, not a longer hidden-state tensor."""

    by_name = {
        item.name: value
        for item, value in zip(model.get_outputs(), values, strict=True)
    }
    for name in ("image_embeds", "text_embeds", "sentence_embedding", "embeddings"):
        chosen = by_name.get(name)
        if isinstance(chosen, np.ndarray):
            return _as_vector(chosen, feeds)
    hidden = by_name.get("last_hidden_state")
    if isinstance(hidden, np.ndarray):
        return _as_vector(hidden, feeds)
    floats = [
        value
        for value in values
        if isinstance(value, np.ndarray) and np.issubdtype(value.dtype, np.floating)
    ]
    if not floats:
        raise RuntimeError("model returned no floating-point output")
    return _as_vector(min(floats, key=lambda value: (value.ndim, value.size)), feeds)


def sentence_vector(
    model: ort.InferenceSession,
    feeds: dict[str, np.ndarray],
) -> np.ndarray:
    values = model.run(None, feeds)
    return vector_from_outputs(model, feeds, values)


def l2_normalize(vector: np.ndarray) -> tuple[np.ndarray, float]:
    norm = float(np.linalg.norm(vector))
    if not np.isfinite(norm) or norm <= 0:
        raise RuntimeError(f"vector norm is not usable: {norm}")
    return vector / norm, norm


def cosine(left: np.ndarray, right: np.ndarray) -> float:
    denom = float(np.linalg.norm(left) * np.linalg.norm(right))
    if denom == 0 or not np.isfinite(denom):
        return float("nan")
    return float(np.dot(left, right) / denom)


def infer_ms(
    model: ort.InferenceSession,
    feeds: dict[str, np.ndarray],
    repeats: int = 3,
) -> tuple[np.ndarray, float]:
    model.run(None, feeds)
    started = time.perf_counter()
    last = None
    for _ in range(repeats):
        last = model.run(None, feeds)
    elapsed = (time.perf_counter() - started) * 1000.0 / repeats
    if last is None:
        raise RuntimeError("inference did not run")
    return vector_from_outputs(model, feeds, last), elapsed


def preprocess_image(path: Path) -> np.ndarray:
    """Match Xenova preprocessor_config.json for MobileCLIP-S0.

    shortest_edge 256, bilinear resize, center crop 256, rescale 1/255.
    That file sets do_normalize to false, so mean/std stay out of this step.
    Layout is NCHW.
    """

    image = Image.open(path).convert("RGB")
    width, height = image.size
    short = min(width, height)
    scale = IMAGE_EDGE / short
    resized = (
        max(IMAGE_EDGE, round(width * scale)),
        max(IMAGE_EDGE, round(height * scale)),
    )
    image = image.resize(resized, Image.BILINEAR)
    left = (image.width - IMAGE_EDGE) // 2
    top = (image.height - IMAGE_EDGE) // 2
    image = image.crop((left, top, left + IMAGE_EDGE, top + IMAGE_EDGE))
    array = np.asarray(image).astype(np.float32) / 255.0
    return np.transpose(array, (2, 0, 1))[None, ...]


def image_feeds(model: ort.InferenceSession, pixels: np.ndarray) -> dict[str, np.ndarray]:
    feeds: dict[str, np.ndarray] = {}
    for item in model.get_inputs():
        if "float" not in item.type:
            raise RuntimeError(
                f"image input {item.name} is {item.type}, expected float"
            )
        feeds[item.name] = pixels
    if not feeds:
        raise RuntimeError("image model has no inputs")
    return feeds


def optimize_model(source: Path, dest: Path) -> Path:
    if dest.is_file() and dest.stat().st_size > 0:
        return dest
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.optimized_model_filepath = str(dest)
    optimized = ort.InferenceSession(
        str(source),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    del optimized
    if not dest.is_file():
        raise RuntimeError(f"ORT did not write {dest}")
    return dest
