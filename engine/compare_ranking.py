"""Compare Chroma and Dart Top-5 on the exported vectors.

Same tie-break on both files: score descending, relative path ascending,
null page last, start offset ascending. A near-tie that changes the chunk
id counts as a miss. The comparator is not loosened to clear the gate.

    python engine/compare_ranking.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "reports" / "week4" / "logs"
GATE = 0.96


def _load(path: Path) -> dict[str, list[dict]]:
    rows: dict[str, list[dict]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        rows[record["queryId"]] = _sort(record["top5"])
    return rows


def _sort(hits: list[dict]) -> list[dict]:
    def key(hit: dict) -> tuple:
        page = hit.get("pageNumber")
        return (
            -float(hit["score"]),
            hit["relativePath"],
            page is None,
            0 if page is None else int(page),
            int(hit["startOffset"]),
        )

    return sorted(hits, key=key)


def main() -> int:
    dart = _load(LOGS / "dart_top5.jsonl")
    chroma = _load(LOGS / "chroma_top5.jsonl")
    query_ids = list(dict.fromkeys([*dart.keys(), *chroma.keys()]))
    compared = 0
    agreed = 0
    max_rank_delta = 0.0
    max_same_chunk_delta = 0.0
    misses: list[str] = []
    for query_id in query_ids:
        left = dart.get(query_id, [])
        right = chroma.get(query_id, [])
        same_score: dict[str, float] = {}
        for hit in left:
            same_score[hit["chunkId"]] = float(hit["score"])
        for slot in range(5):
            compared += 1
            left_hit = left[slot] if slot < len(left) else None
            right_hit = right[slot] if slot < len(right) else None
            if left_hit is not None and right_hit is not None:
                max_rank_delta = max(
                    max_rank_delta,
                    abs(float(left_hit["score"]) - float(right_hit["score"])),
                )
                if left_hit["chunkId"] == right_hit["chunkId"]:
                    agreed += 1
                else:
                    misses.append(
                        f"{query_id} slot={slot + 1} dart={left_hit['chunkId']} chroma={right_hit['chunkId']}"
                    )
            else:
                misses.append(f"{query_id} slot={slot + 1} missing")
        for hit in right:
            other = same_score.get(hit["chunkId"])
            if other is not None:
                max_same_chunk_delta = max(
                    max_same_chunk_delta,
                    abs(other - float(hit["score"])),
                )
    rate = agreed / compared if compared else 0.0
    lines = [
        "comparison=chroma_top5_vs_dart_sqlite_top5",
        "slots_per_query=5",
        f"queries={len(query_ids)}",
        f"positions={compared}",
        f"agreed={agreed}",
        f"agreement={rate:.6f}",
        f"gate={GATE:.2f}",
        f"max_abs_score_delta_same_rank={max_rank_delta:.8f}",
        f"max_abs_score_delta_same_chunk={max_same_chunk_delta:.8f}",
        "tie_break=score_desc,relativePath_asc,page_asc_null_last,startOffset_asc",
        "query_vectors=exported_vectorB64",
        f"passed={1 if rate >= GATE else 0}",
    ]
    if misses:
        lines.append("mismatches:")
        lines.extend(misses[:40])
    text = "\n".join(lines) + "\n"
    out = LOGS / "storage_equivalence.txt"
    out.write_text(text, encoding="utf-8")
    print(text, end="")
    if rate < GATE:
        print("H1 gate not met. Fix cosine space, L2, or tie-break before fusion.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
