"""COCO image-to-caption sanity check for Week 3.

Both sides use MobileCLIP-S0 in clipShared: vision_model.onnx for the
image and text_model.onnx for the caption. Captions are not encoded with
MiniLM. Image pixels follow the Pillow shortest-edge path in
w3_embed_lib. Text ids follow tokenizers 0.23.2 with truncation off, then
pad to 77 with the '!' id, matching ClipTextEmbedder.

Fifty captioned images cannot support a precision claim. The numbers are
a sanity check. image-to-image nearest neighbors are printed in a separate
block and are not the completion metric. A missing text tower is reported
as incomplete and does not get replaced by that block.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from tokenizers import Tokenizer

from w3_embed_lib import (
    CLIP_MAX_LEN,
    IMAGE_DIR,
    ROOT,
    image_feeds,
    l2_normalize,
    preprocess_image,
    session,
)

CAPTIONS = ROOT / "datasets" / "coco" / "val_sample" / "captions.jsonl"
IMAGES = ROOT / "datasets" / "coco" / "val_sample" / "images"
VISION_PATH = IMAGE_DIR / "onnx" / "vision_model.onnx"
TEXT_PATH = IMAGE_DIR / "onnx" / "text_model.onnx"
TOKENIZER_PATH = IMAGE_DIR / "tokenizer.json"


def _pairs() -> list[tuple[str, str]]:
    if not CAPTIONS.is_file():
        raise RuntimeError(f"missing {CAPTIONS}")
    pairs: list[tuple[str, str]] = []
    for line_number, line in enumerate(CAPTIONS.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        item = json.loads(line)
        if not isinstance(item, dict):
            raise RuntimeError(f"caption line {line_number} is not an object")
        name = item.get("file_name")
        caption = item.get("caption")
        if not isinstance(name, str) or not name:
            raise RuntimeError(f"caption line {line_number} has no file_name")
        if not isinstance(caption, str) or not caption.strip():
            raise RuntimeError(f"caption line {line_number} has no caption")
        image = IMAGES / name
        if not image.is_file():
            raise RuntimeError(f"missing image {name}")
        pairs.append((name, caption))
    if len(pairs) != 50:
        raise RuntimeError(f"expected 50 captioned images, found {len(pairs)}")
    return pairs


def _median(values: list[float]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def _encode_caption(tokenizer: Tokenizer, pad_id: int, text: str) -> np.ndarray:
    ids = tokenizer.encode(text).ids
    if len(ids) > CLIP_MAX_LEN:
        raise RuntimeError(f"{len(ids)} tokens exceed {CLIP_MAX_LEN}: {text[:80]}")
    padded = np.full((1, CLIP_MAX_LEN), pad_id, dtype=np.int64)
    padded[0, : len(ids)] = np.asarray(ids, dtype=np.int64)
    return padded


def _normalize(vector: np.ndarray, label: str) -> np.ndarray:
    flat = np.asarray(vector, dtype=np.float32).reshape(-1)
    if flat.shape != (512,):
        raise RuntimeError(f"{label} dim {flat.shape}")
    if not np.isfinite(flat).all():
        raise RuntimeError(f"{label} is non-finite")
    normalized, _norm = l2_normalize(flat)
    return normalized


def _image_to_image(images: np.ndarray) -> None:
    scores = images @ images.T
    diagonal = np.diag(scores).copy()
    np.fill_diagonal(scores, -np.inf)
    nearest = scores.max(axis=1)
    print("block=image_to_image_sanity")
    print("image_to_image_not_completion=1")
    print(f"self_cosine_min={float(diagonal.min()):.6f}")
    print(f"self_cosine_max={float(diagonal.max()):.6f}")
    print(f"nearest_other_cosine_median={_median([float(value) for value in nearest]):.6f}")
    print(f"nearest_other_cosine_max={float(nearest.max()):.6f}")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    print("metric_layer=image_caption_sanity")
    print("not_measured=pdf_figure_understanding")
    print("not_measured=statistical_precision")
    print("space=clipShared")
    print("caption_encoder=mobileclip-s0-text")
    print("caption_encoder_not=paraphrase-multilingual-MiniLM-L12-v2")
    print("n_captioned_images=50")
    print("n_rvlcdip_unlabeled=16")
    print("rvlcdip_in_this_run=0")

    if not TEXT_PATH.is_file() or not TOKENIZER_PATH.is_file():
        print("text_tower=missing")
        print("function_status=incomplete")
        print("completion_metric=none")
        if VISION_PATH.is_file():
            pairs = _pairs()
            vision = session(VISION_PATH)
            images = np.empty((len(pairs), 512), dtype=np.float32)
            for index, (name, _caption) in enumerate(pairs):
                raw = vision.run(
                    ["image_embeds"],
                    image_feeds(vision, preprocess_image(IMAGES / name)),
                )[0]
                images[index] = _normalize(raw, name)
            _image_to_image(images)
        print("gate=fail")
        return 2

    pairs = _pairs()
    print(f"captions={CAPTIONS.relative_to(ROOT).as_posix()} lines={len(pairs)}")
    print(f"vision_model={VISION_PATH.relative_to(ROOT).as_posix()}")
    print(f"text_model={TEXT_PATH.relative_to(ROOT).as_posix()}")
    print("preprocess=shortest_edge_256 bilinear center_crop rescale_1_255 do_normalize=false")
    print("text_pad=exclamation_to_77")
    print(f"max_length={CLIP_MAX_LEN}")

    tokenizer = Tokenizer.from_file(str(TOKENIZER_PATH))
    tokenizer.no_truncation()
    pad_id = tokenizer.token_to_id("!")
    if pad_id is None:
        raise RuntimeError("CLIP tokenizer has no '!' pad token")

    load_started = time.perf_counter()
    vision = session(VISION_PATH)
    text = session(TEXT_PATH)
    print(f"load_ms={(time.perf_counter() - load_started) * 1000.0:.2f}")

    image_vectors = np.empty((len(pairs), 512), dtype=np.float32)
    text_vectors = np.empty((len(pairs), 512), dtype=np.float32)
    image_ms: list[float] = []
    text_ms: list[float] = []
    for index, (name, caption) in enumerate(pairs):
        started = time.perf_counter()
        raw = vision.run(
            ["image_embeds"],
            image_feeds(vision, preprocess_image(IMAGES / name)),
        )[0]
        image_ms.append((time.perf_counter() - started) * 1000.0)
        image_vectors[index] = _normalize(raw, name)

        ids = _encode_caption(tokenizer, pad_id, caption)
        started = time.perf_counter()
        raw = text.run(["text_embeds"], {"input_ids": ids})[0]
        text_ms.append((time.perf_counter() - started) * 1000.0)
        text_vectors[index] = _normalize(raw, f"caption {index}")

    print("embedded_images=50 dim=512")
    print("embedded_captions=50 dim=512")
    print(f"image_infer_ms_median={_median(image_ms):.2f}")
    print(f"image_infer_ms_max={max(image_ms):.2f}")
    print(f"text_infer_ms_median={_median(text_ms):.2f}")
    print(f"text_infer_ms_max={max(text_ms):.2f}")
    print("infer_ms_excludes=model_load")

    scores = image_vectors @ text_vectors.T
    ranks: list[int] = []
    for index in range(len(pairs)):
        order = np.argsort(-scores[index], kind="stable")
        ranks.append(int(np.where(order == index)[0][0]) + 1)
    hits_at_1 = sum(rank <= 1 for rank in ranks)
    hits_at_5 = sum(rank <= 5 for rank in ranks)
    print("block=image_to_caption")
    print("function_status=complete")
    print(f"recall@1_hits={hits_at_1}/50")
    print(f"recall@5_hits={hits_at_5}/50")
    print(f"recall@1={hits_at_1 / 50:.6f}")
    print(f"recall@5={hits_at_5 / 50:.6f}")
    print(f"mean_rank={sum(ranks) / len(ranks):.2f}")
    print(f"rank_min={min(ranks)}")
    print(f"rank_median={_median([float(rank) for rank in ranks]):.1f}")
    print(f"rank_max={max(ranks)}")
    print(f"chance_recall@1={1 / 50:.6f}")
    print(f"chance_recall@5={5 / 50:.6f}")

    for index in (0, 1, 2):
        name, caption = pairs[index]
        print(
            f"example index={index} file={name} rank={ranks[index]} "
            f"caption={caption.strip()}"
        )

    _image_to_image(image_vectors)
    print("gate=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 — probe should print the reason
        print(f"gate=fail error={error}")
        print(f"gate=fail error={error}", file=sys.stderr)
        raise SystemExit(1) from error
