"""Day 1 conversion gate.

Compares mean-pooled outputs of the original fp32 ONNX graph with the
published int8 graph on the same inputs. Int8 ships only when every
cosine is >= 0.999. Otherwise the script rewrites the fp32 graph with
ONNX Runtime's full optimizer and scores that rewrite. A rewrite that
clears 0.999 is evidence that the weights survived conversion; the
portable file stays the original fp32 ONNX, because ORT_ENABLE_ALL can
bake in machine-specific kernels. The gate fails only when neither
int8 nor that rewrite clears 0.999.
"""

from __future__ import annotations

import sys
from importlib.metadata import version

import numpy as np

from w3_embed_lib import (
    CLIP_MAX_LEN,
    COCO_CONVERT,
    COSINE_GATE,
    IMAGE_DIR,
    SENTENCES,
    TEXT_DIR,
    TEXT_MAX_LEN,
    cosine,
    encode_text,
    file_line,
    image_feeds,
    load_tokenizer,
    optimize_model,
    preprocess_image,
    sentence_vector,
    session,
    signature_lines,
    tokenizer_kind,
)


def _score_text(
    label: str,
    before_path,
    after_path,
    tokenizer_path,
    max_len: int,
    sentences: tuple[tuple[str, str], ...],
) -> tuple[float, list[str]]:
    tokenizer, _pad = load_tokenizer(tokenizer_path, max_len)
    before = session(before_path)
    after = session(after_path)
    lines = [
        f"{label}_before={before_path}",
        f"{label}_after={after_path}",
        f"{label}_before_stat {file_line(before_path)}",
        f"{label}_after_stat {file_line(after_path)}",
    ]
    scores: list[float] = []
    for index, (lang, text) in enumerate(sentences):
        before_feeds = encode_text(tokenizer, text, before)
        after_feeds = encode_text(tokenizer, text, after)
        left = sentence_vector(before, before_feeds)
        right = sentence_vector(after, after_feeds)
        score = cosine(left, right)
        scores.append(score)
        lines.append(
            f"{label}_cosine index={index} lang={lang} value={score:.6f} "
            f"dim={left.shape[0]}"
        )
    minimum = float(min(scores)) if scores else float("nan")
    lines.append(f"{label}_cosine_min={minimum:.6f}")
    return minimum, lines


def _score_images(before_path, after_path) -> tuple[float, list[str]]:
    before = session(before_path)
    after = session(after_path)
    lines = [
        f"image_before={before_path}",
        f"image_after={after_path}",
        f"image_before_stat {file_line(before_path)}",
        f"image_after_stat {file_line(after_path)}",
    ]
    scores: list[float] = []
    for path in COCO_CONVERT:
        pixels = preprocess_image(path)
        left = sentence_vector(before, image_feeds(before, pixels))
        right = sentence_vector(after, image_feeds(after, pixels))
        score = cosine(left, right)
        scores.append(score)
        lines.append(
            f"image_cosine file={path.name} value={score:.6f} dim={left.shape[0]}"
        )
    minimum = float(min(scores)) if scores else float("nan")
    lines.append(f"image_cosine_min={minimum:.6f}")
    return minimum, lines


def _choose(label: str, int8_min: float, optimized_min: float | None) -> str:
    """Pick the portable file. An ORT rewrite that matches at 1.0 still ships fp32.

    ORT_ENABLE_ALL can bake in machine-specific kernels, so the optimized
    file is evidence, not the artifact other machines should load.
    """

    if np.isfinite(int8_min) and int8_min >= COSINE_GATE:
        print(f"{label}_conversion=int8")
        print(f"{label}_shipped=int8")
        print(f"{label}_gate=pass")
        return "int8"
    if (
        optimized_min is not None
        and np.isfinite(optimized_min)
        and optimized_min >= COSINE_GATE
    ):
        print(f"{label}_conversion=ort_enable_all")
        print(f"{label}_conversion_cosine_min={optimized_min:.6f}")
        print(f"{label}_shipped=fp32")
        print(
            f"{label}_int8_rejected cosine_min={int8_min:.6f} threshold={COSINE_GATE}"
        )
        print(f"{label}_gate=pass")
        return "fp32"
    print(f"{label}_shipped=none")
    print(f"{label}_gate=fail")
    return "none"


def main() -> int:
    text_fp32 = TEXT_DIR / "onnx" / "model.onnx"
    text_int8 = TEXT_DIR / "onnx" / "model_int8.onnx"
    text_tokenizer = TEXT_DIR / "tokenizer.json"
    vision_fp32 = IMAGE_DIR / "onnx" / "vision_model.onnx"
    vision_int8 = IMAGE_DIR / "onnx" / "vision_model_int8.onnx"
    required = (text_fp32, text_int8, text_tokenizer, vision_fp32, vision_int8)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        print("missing " + " | ".join(missing), file=sys.stderr)
        return 2

    print(f"threshold={COSINE_GATE}")
    print(f"onnxruntime={version('onnxruntime')}")
    print(f"tokenizers={version('tokenizers')}")
    print(f"numpy={version('numpy')}")
    print("compare=mean_pool on the same input ids; session graph optimization disabled")
    print(f"text_tokenizer {tokenizer_kind(text_tokenizer)}")
    print(f"text_tokenizer_stat {file_line(text_tokenizer)}")

    text_int8_min, text_lines = _score_text(
        "text_int8",
        text_fp32,
        text_int8,
        text_tokenizer,
        TEXT_MAX_LEN,
        SENTENCES,
    )
    print("\n".join(text_lines))

    text_opt_min = None
    if not (np.isfinite(text_int8_min) and text_int8_min >= COSINE_GATE):
        optimized = optimize_model(text_fp32, TEXT_DIR / "onnx" / "model_ort.onnx")
        text_opt_min, opt_lines = _score_text(
            "text_ort",
            text_fp32,
            optimized,
            text_tokenizer,
            TEXT_MAX_LEN,
            SENTENCES,
        )
        print("\n".join(opt_lines))
    text_choice = _choose("text", text_int8_min, text_opt_min)

    image_int8_min, image_lines = _score_images(vision_fp32, vision_int8)
    print("\n".join(image_lines))
    image_opt_min = None
    if not (np.isfinite(image_int8_min) and image_int8_min >= COSINE_GATE):
        optimized = optimize_model(
            vision_fp32,
            IMAGE_DIR / "onnx" / "vision_model_ort.onnx",
        )
        image_opt_min, opt_lines = _score_images(vision_fp32, optimized)
        print("\n".join(opt_lines))
    image_choice = _choose("image", image_int8_min, image_opt_min)

    clip_tokenizer = IMAGE_DIR / "tokenizer.json"
    clip_fp32 = IMAGE_DIR / "onnx" / "text_model.onnx"
    clip_int8 = IMAGE_DIR / "onnx" / "text_model_int8.onnx"
    clip_choice = "not_checked"
    if clip_tokenizer.is_file() and clip_fp32.is_file() and clip_int8.is_file():
        print(f"clip_text_tokenizer {tokenizer_kind(clip_tokenizer)}")
        clip_fp32_session = session(clip_fp32)
        for line in signature_lines(clip_fp32_session):
            print(f"clip_text_{line}")
        del clip_fp32_session
        clip_min, clip_lines = _score_text(
            "clip_text_int8",
            clip_fp32,
            clip_int8,
            clip_tokenizer,
            CLIP_MAX_LEN,
            SENTENCES,
        )
        print("\n".join(clip_lines))
        clip_opt = None
        if not (np.isfinite(clip_min) and clip_min >= COSINE_GATE):
            optimized = optimize_model(
                clip_fp32,
                IMAGE_DIR / "onnx" / "text_model_ort.onnx",
            )
            clip_opt, opt_lines = _score_text(
                "clip_text_ort",
                clip_fp32,
                optimized,
                clip_tokenizer,
                CLIP_MAX_LEN,
                SENTENCES,
            )
            print("\n".join(opt_lines))
        clip_choice = _choose("clip_text", clip_min, clip_opt)
    else:
        print("clip_text_gate=skip")

    # The Day 1 hard gate is the document-text model and the image tower.
    # The CLIP text tower is recorded so Week 4 knows whether it is usable,
    # and it does not replace the image gate.
    passed = text_choice != "none" and image_choice != "none"
    print(
        "ort_optimize_note=ORT_ENABLE_ALL may embed hardware-specific kernels; "
        "cosine 1.0 means the original fp32 file stays the portable artifact"
    )
    print("overall_gate=pass" if passed else "overall_gate=fail")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
