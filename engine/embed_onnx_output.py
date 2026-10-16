"""Run one ONNX output and print little-endian float32 base64.

The request JSON has model_path, output_name, and inputs. Each input is
float32 bytes in base64 or an int64 values list, plus shape.

    python embed_onnx_output.py <request.json>
    python embed_onnx_output.py --reference-image <image> <vision_model.onnx>

The reference mode preprocesses with the Week 3 Pillow path, runs the
vision tower, L2-normalizes, and prints the same base64 layout.
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from w3_embed_lib import image_feeds, l2_normalize, preprocess_image, session


def _tensor(spec: dict) -> np.ndarray:
    dtype = spec["dtype"]
    shape = spec["shape"]
    if dtype == "float32":
        raw = base64.b64decode(spec["b64"])
        return np.frombuffer(raw, dtype="<f4").reshape(shape)
    if dtype == "int64":
        return np.asarray(spec["values"], dtype=np.int64).reshape(shape)
    raise RuntimeError(f"unsupported dtype {dtype}")


def _write(vector: np.ndarray) -> None:
    raw = np.ascontiguousarray(vector, dtype="<f4").reshape(-1).tobytes()
    sys.stdout.write(base64.b64encode(raw).decode("ascii"))


def reference_image(image_path: Path, model_path: Path) -> int:
    pixels = preprocess_image(image_path)
    model = session(model_path)
    values = model.run(["image_embeds"], image_feeds(model, pixels))[0]
    vector, _norm = l2_normalize(np.asarray(values, dtype=np.float32).reshape(-1))
    _write(vector)
    return 0


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--reference-image":
        return reference_image(Path(sys.argv[2]), Path(sys.argv[3]))
    if len(sys.argv) != 2:
        print(
            "usage: embed_onnx_output.py <request.json> | "
            "--reference-image <image> <vision_model.onnx>",
            file=sys.stderr,
        )
        return 2
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    model = session(Path(request["model_path"]))
    feeds = {
        name: _tensor(spec) for name, spec in request["inputs"].items()
    }
    output = request["output_name"]
    values = model.run([output], feeds)[0]
    _write(np.asarray(values, dtype=np.float32))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
