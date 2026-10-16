"""Download the Week 3 ONNX weights into models/raw.

The root .gitignore already excludes models/raw, *.onnx, and tokenizer
sidecars that live under that tree. Re-running this script resumes from
the Hugging Face cache.
"""

from __future__ import annotations

import sys
from pathlib import Path

from huggingface_hub import snapshot_download

ROOT = Path(__file__).resolve().parents[1]

JOBS = (
    {
        "repo_id": "Xenova/paraphrase-multilingual-MiniLM-L12-v2",
        "revision": "2c4055b12046f11709e9df2c122e59ffbdc2f900",
        "local_dir": ROOT
        / "models"
        / "raw"
        / "text"
        / "paraphrase-multilingual-MiniLM-L12-v2",
        "allow_patterns": (
            "onnx/model.onnx",
            "onnx/model_int8.onnx",
            "tokenizer.json",
            "tokenizer_config.json",
            "config.json",
            "special_tokens_map.json",
        ),
    },
    {
        "repo_id": "Xenova/mobileclip_s0",
        "revision": "757d59c9c6870a76a4b0306f05f5061bca15c39f",
        "local_dir": ROOT / "models" / "raw" / "image" / "mobileclip-s0",
        "allow_patterns": (
            "onnx/vision_model.onnx",
            "onnx/vision_model_int8.onnx",
            "onnx/text_model.onnx",
            "onnx/text_model_int8.onnx",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "config.json",
        ),
    },
)


def main() -> int:
    for job in JOBS:
        dest = job["local_dir"]
        dest.mkdir(parents=True, exist_ok=True)
        print(
            f"download {job['repo_id']} @ {job['revision']} -> {dest}",
            flush=True,
        )
        snapshot_download(
            repo_id=job["repo_id"],
            revision=job["revision"],
            local_dir=str(dest),
            allow_patterns=list(job["allow_patterns"]),
        )
        missing = [
            name
            for name in job["allow_patterns"]
            if not (dest / name).is_file()
        ]
        if missing:
            print(f"missing {missing}", file=sys.stderr)
            return 1
        print(f"ok {dest}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
