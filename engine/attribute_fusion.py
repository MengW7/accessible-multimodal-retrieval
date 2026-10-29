#!/usr/bin/env python
"""Attribute the per-question error classes to channels, not to a single score.

`error_analysis.py` says *what* failed. This says *which channel* caused it, by
replaying the fusion arithmetic on the recorded hits:

  * for every question where arm X (text only) hit and arm Y (fused) missed,
    check whether the fused top-5 contains keyword-only rows, or rows that both
    channels touched
  * for every question where the fused arm hit and the single channel missed,
    check the same

No retrieval is re-run: it reads the JSONL payload that `error_analysis.py`
already wrote, so the two scripts cannot disagree about a ranking.

    python engine/attribute_fusion.py \
        --jsonl reports/week5/logs/w5_dev.jsonl --base A1 --fused A4

Report the numbers; do not tune a weight to clear them.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path: Path) -> dict[tuple[str, str], dict]:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    return {(row["id"], row["arm"]): row for row in rows}


def channel_mix(record: dict, depth: int) -> dict[str, int]:
    """What channel signatures appear in the top `depth` rows."""
    mix = collections.Counter()
    for hit in record["hits"][:depth]:
        channels = tuple(sorted(hit.get("channels") or []))
        if not channels:
            mix["none"] += 1
        elif channels == ("keyword",):
            mix["keyword_only"] += 1
        elif "keyword" in channels and "documentText" in channels:
            mix["text_and_keyword"] += 1
        elif channels == ("documentText",):
            mix["text_only"] += 1
        else:
            mix["other"] += 1
    return dict(mix)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--base", default="A1")
    parser.add_argument("--fused", default="A4")
    parser.add_argument("--cut", type=int, default=5)
    args = parser.parse_args()

    path = Path(args.jsonl)
    if not path.is_absolute():
        path = ROOT / path
    if not path.exists():
        raise SystemExit(f"Missing analysis payload: {path}")
    table = load(path)

    ids = sorted({key[0] for key in table if key[1] == args.base})
    answerable = [i for i in ids if table[(i, args.base)]["answerable"]]
    if not answerable:
        raise SystemExit("No answerable questions for that arm pair.")

    def doc_rank(question: str, arm: str) -> int:
        return int(table[(question, arm)]["detail"].get("docRank", 0))

    def hit(question: str, arm: str) -> bool:
        rank = doc_rank(question, arm)
        return 0 < rank <= args.cut

    hurt = [i for i in answerable if hit(i, args.base) and not hit(i, args.fused)]
    helped = [i for i in answerable if not hit(i, args.base) and hit(i, args.fused)]
    both = [i for i in answerable if hit(i, args.base) and hit(i, args.fused)]
    neither = [i for i in answerable if not hit(i, args.base) and not hit(i, args.fused)]

    print(f"# fusion attribution  base={args.base} fused={args.fused} cut={args.cut}")
    print(f"jsonl={path}")
    print(f"answerable={len(answerable)}")
    print(f"both_hit={len(both)} base_only={len(hurt)} fused_only={len(helped)} neither={len(neither)}")
    print()

    for label, group in (("base_only (fusion lost it)", hurt), ("fused_only (fusion gained it)", helped)):
        print(f"# --- {label}: {len(group)} ---")
        totals: collections.Counter = collections.Counter()
        for question in group:
            mix = channel_mix(table[(question, args.fused)], args.cut)
            for key, value in mix.items():
                totals[key] += value
            print(
                f"{question} base_rank={doc_rank(question, args.base)} "
                f"fused_rank={doc_rank(question, args.fused)} "
                f"mix={mix} question={table[(question, args.base)]['question'][:60]}"
            )
        if group:
            print(f"subtotal channel rows across {len(group)} questions x {args.cut}: {dict(totals)}")
        print()

    # Overall occupancy: how much of the fused top-5 is driven by the keyword
    # channel. A high number means the fused ranking is mostly a lexical ranking
    # with a semantic nudge, which is the opposite of what RRF was chosen for.
    occupancy: collections.Counter = collections.Counter()
    for question in answerable:
        for key, value in channel_mix(table[(question, args.fused)], args.cut).items():
            occupancy[key] += value
    total_slots = len(answerable) * args.cut
    print(f"# --- fused top-{args.cut} channel occupancy ---")
    for key, value in sorted(occupancy.items()):
        print(f"fused_occupancy={key} rows={value} share={value / total_slots:.4f}")
    print(f"fused_occupancy_slots={total_slots}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
