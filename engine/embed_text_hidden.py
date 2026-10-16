"""Run one padded MiniLM forward and print the hidden state.

The request JSON has model_path, input_ids, attention_mask, and
token_type_ids. Stdout is base64 of little-endian float32
last_hidden_state, row-major. Pooling stays in Dart.
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import numpy as np

from w3_embed_lib import session


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: embed_text_hidden.py <request.json>", file=sys.stderr)
        return 2
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    model = session(Path(request["model_path"]))
    feeds = {
        "input_ids": np.asarray([request["input_ids"]], dtype=np.int64),
        "attention_mask": np.asarray([request["attention_mask"]], dtype=np.int64),
        "token_type_ids": np.asarray([request["token_type_ids"]], dtype=np.int64),
    }
    hidden = model.run(["last_hidden_state"], feeds)[0]
    raw = np.ascontiguousarray(hidden, dtype="<f4").tobytes()
    sys.stdout.write(base64.b64encode(raw).decode("ascii"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
