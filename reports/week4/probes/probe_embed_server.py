"""Drive engine/embed_server.py on 24 real markdown windows.

The first response includes session load. forward_ms is the server-side
ONNX time after that. e2e_ms includes the length-prefixed frame and the
base64 hidden state, so it can be slower than the 30 ms forward target.

    engine\\.venv\\Scripts\\python.exe week4\\probes\\probe_embed_server.py
"""

from __future__ import annotations

import base64
import json
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

from w3_embed_lib import TEXT_DIR, TEXT_MAX_LEN, load_tokenizer  # noqa: E402

MODEL = TEXT_DIR / "onnx" / "model.onnx"
TOKENIZER = TEXT_DIR / "tokenizer.json"
SERVER = ROOT / "engine" / "embed_server.py"
PYTHON = sys.executable
LOG = ROOT / "week4" / "logs" / "embed_server_median.txt"


def _texts(limit: int) -> list[str]:
    texts: list[str] = []
    paths = sorted((ROOT / "docs").rglob("*.md")) + sorted((ROOT / "reports").rglob("*.md"))
    for path in paths:
        body = path.read_text(encoding="utf-8")
        for start in range(0, len(body), 120):
            piece = body[start : start + 120].strip()
            if len(piece) >= 20:
                texts.append(piece)
            if len(texts) >= limit:
                return texts
    return texts


def _frame(payload: dict) -> bytes:
    raw = json.dumps(payload).encode("utf-8")
    return struct.pack(">I", len(raw)) + raw


def _read_exact(stream, count: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < count:
        piece = stream.read(count - len(chunks))
        if not piece:
            raise RuntimeError("embed server closed")
        chunks.extend(piece)
    return bytes(chunks)


def _request(process, payload: dict) -> tuple[dict, float]:
    started = time.perf_counter()
    process.stdin.write(_frame(payload))
    process.stdin.flush()
    header = _read_exact(process.stdout, 4)
    (length,) = struct.unpack(">I", header)
    body = _read_exact(process.stdout, length)
    elapsed = (time.perf_counter() - started) * 1000.0
    return json.loads(body.decode("utf-8")), elapsed


def main() -> int:
    tokenizer, _pad = load_tokenizer(TOKENIZER, TEXT_MAX_LEN)
    texts = _texts(24)
    if len(texts) != 24:
        raise RuntimeError(f"expected 24 texts, found {len(texts)}")
    process = subprocess.Popen(
        [PYTHON, str(SERVER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    forwards: list[float] = []
    e2e: list[float] = []
    session_load = None
    try:
        for index, text in enumerate(texts):
            encoding = tokenizer.encode(text)
            payload = {
                "id": index,
                "model_path": str(MODEL),
                "output_name": "last_hidden_state",
                "inputs": {
                    "input_ids": {
                        "dtype": "int64",
                        "shape": [1, len(encoding.ids)],
                        "values": encoding.ids,
                    },
                    "attention_mask": {
                        "dtype": "int64",
                        "shape": [1, len(encoding.attention_mask)],
                        "values": encoding.attention_mask,
                    },
                    "token_type_ids": {
                        "dtype": "int64",
                        "shape": [1, len(encoding.type_ids)],
                        "values": encoding.type_ids,
                    },
                },
            }
            response, elapsed = _request(process, payload)
            if not response.get("ok"):
                raise RuntimeError(response.get("error"))
            raw = base64.b64decode(response["b64"])
            hidden = np.frombuffer(raw, dtype="<f4")
            if hidden.size == 0 or hidden.size % 384 != 0:
                raise RuntimeError(f"hidden size {hidden.size}")
            if index == 0:
                session_load = response.get("session_load_ms")
            else:
                forwards.append(float(response["forward_ms"]))
                e2e.append(elapsed)
    finally:
        process.kill()
        process.wait(timeout=5)
    forward_median = statistics.median(forwards)
    e2e_median = statistics.median(e2e)
    lines = [
        "runtime=embed_server.py",
        "texts=24",
        "output=last_hidden_state",
        "pooling=not_in_server",
        f"session_load_ms={session_load}",
        f"forward_ms_median={forward_median:.3f}",
        f"forward_ms_max={max(forwards):.3f}",
        f"e2e_ms_median={e2e_median:.3f}",
        f"e2e_ms_max={max(e2e):.3f}",
        "forward_excludes=session_load_and_ipc",
        "e2e_includes=length_prefix_and_base64_hidden_state",
        "forward_target_ms=30",
        f"forward_target_met={1 if forward_median <= 30 else 0}",
    ]
    text = "\n".join(lines) + "\n"
    LOG.parent.mkdir(parents=True, exist_ok=True)
    LOG.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if forward_median <= 30 else 1


if __name__ == "__main__":
    raise SystemExit(main())
