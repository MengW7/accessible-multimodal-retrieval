"""Print tokenizers ids for a JSON list of sentences.

Usage: dump_token_ids.py <tokenizer.json> <sentences.json> [--truncate N]
sentences.json is a JSON list of strings. Stdout is a JSON list of
objects with ids and tokens. Truncation uses the file default unless
--truncate is omitted and --no-truncate is passed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from tokenizers import Tokenizer


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: dump_token_ids.py <tokenizer.json> <sentences.json> [--no-truncate]",
            file=sys.stderr,
        )
        return 2
    tokenizer = Tokenizer.from_file(sys.argv[1])
    if "--no-truncate" in sys.argv:
        tokenizer.no_truncation()
    sentences = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    rows = []
    for sentence in sentences:
        encoding = tokenizer.encode(sentence)
        rows.append({"ids": encoding.ids, "tokens": encoding.tokens})
    sys.stdout.write(json.dumps(rows, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
