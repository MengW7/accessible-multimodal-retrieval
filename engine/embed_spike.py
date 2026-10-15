"""Day 1 feasibility probe.

One Chinese sentence, one English sentence, and one COCO image each
produce a vector. Prints dimension, L2 norm, and inference time.
Exit 0 when all three are finite. This process is the external ONNX
Runtime fallback: the Dart package does not load the weights.
"""

from __future__ import annotations

import sys
from importlib.metadata import version

import numpy as np

from w3_embed_lib import (
    COCO_SPIKE,
    SENTENCES,
    TEXT_DIR,
    TEXT_MAX_LEN,
    IMAGE_DIR,
    content_token_stats,
    encode_text,
    image_feeds,
    infer_ms,
    l2_normalize,
    load_tokenizer,
    preprocess_image,
    session,
    signature_lines,
)


def main() -> int:
    text_model_path = TEXT_DIR / "onnx" / "model.onnx"
    text_tokenizer_path = TEXT_DIR / "tokenizer.json"
    vision_path = IMAGE_DIR / "onnx" / "vision_model.onnx"
    required = (text_model_path, text_tokenizer_path, vision_path, COCO_SPIKE)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        print("missing " + " | ".join(missing), file=sys.stderr)
        return 2

    print("runtime=onnxruntime-cpu")
    print(f"onnxruntime={version('onnxruntime')}")
    print(f"tokenizers={version('tokenizers')}")
    print(f"pillow={version('pillow')}")
    print(f"numpy={version('numpy')}")
    print("infer_ms=mean of 3 runs after 1 warmup; session graph optimization disabled")
    print("text_model=paraphrase-multilingual-MiniLM-L12-v2")
    print(f"text_file={text_model_path}")
    print("image_model=mobileclip-s0")
    print(f"image_file={vision_path}")
    print(
        "image_preprocess=shortest_edge_256,bilinear,center_crop_256,"
        "rescale_1_255,do_normalize=false"
    )

    tokenizer, _pad = load_tokenizer(text_tokenizer_path, TEXT_MAX_LEN)
    text_model = session(text_model_path)
    for line in signature_lines(text_model):
        print(f"text_{line}")

    failed = False
    for index, (lang, text) in enumerate(SENTENCES[:2]):
        content, unks = content_token_stats(tokenizer, text)
        feeds = encode_text(tokenizer, text, text_model)
        vector, elapsed = infer_ms(text_model, feeds)
        finite = bool(np.all(np.isfinite(vector)))
        normed, raw_norm = l2_normalize(vector) if finite else (vector, float("nan"))
        print(
            f"sentence index={index} lang={lang} dim={vector.shape[0]} "
            f"l2_raw={raw_norm:.6f} l2_normalized={float(np.linalg.norm(normed)):.6f} "
            f"infer_ms={elapsed:.2f} content_tokens={content} unk_tokens={unks} "
            f"finite={int(finite)}"
        )
        if not finite or content < 2 or unks == content:
            failed = True

    vision = session(vision_path)
    for line in signature_lines(vision):
        print(f"image_{line}")
    pixels = preprocess_image(COCO_SPIKE)
    vector, elapsed = infer_ms(vision, image_feeds(vision, pixels))
    finite = bool(np.all(np.isfinite(vector)))
    normed, raw_norm = l2_normalize(vector) if finite else (vector, float("nan"))
    print(
        f"image file={COCO_SPIKE.name} dim={vector.shape[0]} "
        f"l2_raw={raw_norm:.6f} l2_normalized={float(np.linalg.norm(normed)):.6f} "
        f"infer_ms={elapsed:.2f} finite={int(finite)}"
    )
    if not finite:
        failed = True

    print("gate=fail" if failed else "gate=pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
