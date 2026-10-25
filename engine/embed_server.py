"""Persistent ONNX process.

One process serves many forwards. A request is a big-endian uint32 length
followed by UTF-8 JSON. The response uses the same frame. Text callers ask
for last_hidden_state and pool it themselves. This process does not pool.

Errors are JSON frames with ok=false. stderr is not the success signal.
"""

from __future__ import annotations

import base64
import json
import struct
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from w3_embed_lib import session


SESSIONS: dict[str, object] = {}
LOAD_MS: dict[str, float] = {}


def _read_exact(count: int) -> bytes | None:
    chunks = bytearray()
    while len(chunks) < count:
        piece = sys.stdin.buffer.read(count - len(chunks))
        if not piece:
            return None
        chunks.extend(piece)
    return bytes(chunks)


def _read_frame() -> dict | None:
    header = _read_exact(4)
    if header is None:
        return None
    (length,) = struct.unpack(">I", header)
    body = _read_exact(length)
    if body is None:
        raise RuntimeError("frame ended before the payload")
    decoded = json.loads(body.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise RuntimeError("frame is not an object")
    return decoded


def _write_frame(payload: dict) -> None:
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(struct.pack(">I", len(raw)))
    sys.stdout.buffer.write(raw)
    sys.stdout.buffer.flush()


def _tensor(spec: dict) -> np.ndarray:
    dtype = spec["dtype"]
    shape = spec["shape"]
    if dtype == "float32":
        raw = base64.b64decode(spec["b64"])
        return np.frombuffer(raw, dtype="<f4").reshape(shape)
    if dtype == "int64":
        return np.asarray(spec["values"], dtype=np.int64).reshape(shape)
    if dtype == "int32":
        return np.asarray(spec["values"], dtype=np.int32).reshape(shape)
    if dtype == "uint8":
        raw = base64.b64decode(spec["b64"])
        return np.frombuffer(raw, dtype=np.uint8).reshape(shape)
    raise RuntimeError(f"unsupported dtype {dtype}")


def _model(path: str):
    cached = SESSIONS.get(path)
    if cached is not None:
        return cached, None
    started = time.perf_counter()
    loaded = session(Path(path))
    elapsed = (time.perf_counter() - started) * 1000.0
    SESSIONS[path] = loaded
    LOAD_MS[path] = elapsed
    return loaded, elapsed


def _handle(request: dict) -> dict:
    model, load_ms = _model(str(request["model_path"]))
    feeds = {name: _tensor(spec) for name, spec in request["inputs"].items()}
    started = time.perf_counter()
    values = model.run([request["output_name"]], feeds)[0]
    forward_ms = (time.perf_counter() - started) * 1000.0
    flat = np.ascontiguousarray(np.asarray(values, dtype=np.float32)).reshape(-1)
    return {
        "id": request.get("id"),
        "ok": True,
        "b64": base64.b64encode(flat.tobytes()).decode("ascii"),
        "shape": [int(flat.shape[0])],
        "forward_ms": forward_ms,
        "session_load_ms": load_ms,
    }


def main() -> int:
    while True:
        try:
            request = _read_frame()
        except Exception as error:  # noqa: BLE001 - keep the process up and report the frame
            _write_frame(
                {
                    "id": None,
                    "ok": False,
                    "error": {"type": type(error).__name__, "message": str(error)},
                }
            )
            continue
        if request is None:
            return 0
        try:
            _write_frame(_handle(request))
        except Exception as error:  # noqa: BLE001 - structured error, process stays up
            _write_frame(
                {
                    "id": request.get("id"),
                    "ok": False,
                    "error": {"type": type(error).__name__, "message": str(error)},
                }
            )


if __name__ == "__main__":
    raise SystemExit(main())
