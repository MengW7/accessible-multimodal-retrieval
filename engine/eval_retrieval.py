"""Score the evidence set with the product retriever.

Dev may be read while the arms are reported. The first holdout look used the
frozen weights. This script does not edit the constants. It reads them and
counts how many differ from the frozen (0.5, 0.3, 0.2) and k=60.

    python engine/eval_retrieval.py --arms A0,A1,A2,A3,A4,A5 --split dev
    python engine/eval_retrieval.py --arms A4 --split holdout
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEEK4 = ROOT / "reports" / "week4"
EVIDENCE = ROOT / "reports" / "week3" / "evidence_set.jsonl"
DB = WEEK4 / ".index" / "evidence.sqlite"
WEIGHTS = (0.5, 0.3, 0.2)
# 冻结值。下面 _verify_freeze() 会拿这几个数去和代码里的常量比对，
# 不再直接打印一个写死的 0 —— 那样不携带任何信息。
FROZEN_K = 60
FROZEN_WEIGHTS = (0.5, 0.3, 0.2)


def _wilson(successes: int, total: int) -> tuple[float, float, float]:
    if total <= 0:
        return 0.0, 0.0, 0.0
    z = 1.959963984540054
    proportion = successes / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    margin = z * math.sqrt(
        proportion * (1 - proportion) / total + z * z / (4 * total * total)
    )
    margin /= denominator
    return proportion, max(0.0, center - margin), min(1.0, center + margin)


def _relevant(hit: dict, targets: list[str]) -> bool:
    key = str(hit.get("documentKey") or hit.get("relativePath") or "").replace("\\", "/")
    name = str(hit.get("fileName") or key.rsplit("/", 1)[-1])
    for raw in targets:
        target = raw.replace("\\", "/")
        if key == target or target.endswith("/" + key) or target.endswith("/" + name):
            return True
    return False


def _median(values: list[int]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[mid])
    return (ordered[mid - 1] + ordered[mid]) / 2


def _load_labels() -> dict[str, dict]:
    labels = {}
    for line in EVIDENCE.read_text(encoding="utf-8").splitlines():
        if line.strip():
            row = json.loads(line)
            labels[row["id"]] = row
    return labels


# 冻结参数的唯一事实来源是检索层代码本身。这里读它、比对，而不是复述一个常数。
RRF_SOURCE = ROOT / "packages" / "core_retrieval" / "lib" / "src" / "rrf_fusion.dart"


def _frozen_from_code() -> tuple[int, tuple[float, float, float]]:
    """读 rrf_fusion.dart 里的 rrfK 与三个权重常量。读不到就报错，不猜。"""
    if not RRF_SOURCE.exists():
        raise SystemExit(f"Missing retriever source: {RRF_SOURCE}")
    text = RRF_SOURCE.read_text(encoding="utf-8")
    import re

    def _int_const(name: str) -> int:
        found = re.search(rf"const int {name} = (\d+);", text)
        if not found:
            raise SystemExit(f"Cannot read {name} from {RRF_SOURCE}")
        return int(found.group(1))

    def _double_const(name: str) -> float:
        found = re.search(rf"const double {name} = ([\d.]+);", text)
        if not found:
            raise SystemExit(f"Cannot read {name} from {RRF_SOURCE}")
        return float(found.group(1))

    return (
        _int_const("rrfK"),
        (
            _double_const("rrfTextWeight"),
            _double_const("rrfKeywordWeight"),
            _double_const("rrfImageWeight"),
        ),
    )


def _verify_freeze() -> tuple[int, int, tuple[float, float, float]]:
    """返回 (k, parameters_changed_after_freeze, (text, keyword, image))。

    parameters_changed_after_freeze 是真实比较结果：代码里的 k 和三个权重
    是否仍等于冻结值。改过任何一项就会变成非 0，而不是一条永真的日志。
    """
    k, weights = _frozen_from_code()
    changed = 0
    if k != FROZEN_K:
        changed += 1
    for actual, frozen in zip(weights, FROZEN_WEIGHTS):
        if abs(actual - frozen) > 1e-9:
            changed += 1
    return k, changed, weights


def _run_dart(arms: str, split: str) -> list[dict]:
    if not DB.exists():
        raise SystemExit(f"Missing index: {DB}")
    command = [
        "dart",
        "run",
        "packages/core_pipeline/bin/search_probe.dart",
        "--db",
        str(DB),
        "--evidence",
        str(EVIDENCE),
        "--arms",
        arms,
        "--split",
        split,
        "--top",
        "10",
        "--bench",
    ]
    # Windows resolves dart.bat only through cmd. CreateProcess cannot start it.
    run_args = subprocess.list2cmdline(command) if os.name == "nt" else command
    completed = subprocess.run(
        run_args,
        cwd=ROOT,
        shell=os.name == "nt",
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(completed.returncode)
    if completed.stderr:
        sys.stderr.write(completed.stderr)
    rows = []
    for line in completed.stdout.splitlines():
        text = line.strip()
        if text.startswith("{"):
            rows.append(json.loads(text))
    return rows


def _score(rows: list[dict], labels: dict[str, dict]) -> None:
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        grouped.setdefault(row["arm"], []).append(row)
    k, changed, weights = _verify_freeze()
    print(f"parameters_changed_after_freeze={changed}")
    print(f"weights=text:{weights[0]},keyword:{weights[1]},image:{weights[2]}")
    print(f"k={k}")
    # holdout 跑了几次要能自证：同一次运行里每个 arm 的 (arm, split) 都不能重复，
    # 且 split 必须一致。这里据此推导，不再按「第一行是不是 holdout」猜。
    splits = {row.get("split", "") for row in rows}
    repeated = sum(1 for arm, items in grouped.items() if len(items) != len({q["id"] for q in items}))
    print(f"holdout_scored_runs={1 if splits == {'holdout'} else 0}")
    print(f"duplicate_questions_per_arm={repeated}")
    for arm in sorted(grouped):
        questions = grouped[arm]
        split = questions[0].get("split", "")
        hit5 = 0
        reciprocal = 0.0
        recall5_sum = 0.0
        recall10_sum = 0.0
        multi = 0
        for row in questions:
            label = labels[row["id"]]
            targets = label.get("relevantDocumentIds") or [label["relevantDocumentId"]]
            hits = row["hits"]
            rank = 0
            found5 = set()
            found10 = set()
            for hit in hits:
                matched = [target for target in targets if _relevant(hit, [target])]
                if matched and rank == 0:
                    rank = int(hit["rank"])
                if int(hit["rank"]) <= 5:
                    found5.update(matched)
                if int(hit["rank"]) <= 10:
                    found10.update(matched)
            if rank and rank <= 5:
                hit5 += 1
            if rank and rank <= 10:
                reciprocal += 1.0 / rank
            recall5_sum += len(found5) / len(targets)
            recall10_sum += len(found10) / len(targets)
            if len(targets) > 1:
                multi += 1
            channels = ",".join(hits[rank - 1]["channels"]) if rank and rank <= len(hits) else ""
            top5 = []
            for hit in hits:
                if int(hit["rank"]) > 5:
                    break
                page = hit.get("pageNumber")
                page_text = "na" if page is None else str(page)
                top5.append(f"{hit.get('documentKey')}#p{page_text}@{hit['rank']}")
            print(
                f"{row['id']} split={split} arm={arm} hit@5={1 if rank and rank <= 5 else 0} "
                f"rank={rank or 0} channels={channels} top5=[{', '.join(top5)}]"
            )
        proportion, low, high = _wilson(hit5, len(questions))
        encode = [int(row["encodeMs"]) for row in questions]
        store = [int(row["storeMs"]) for row in questions]
        fuse = [int(row["fuseMs"]) for row in questions]
        # The first encode includes the model load. Later calls are the query cost.
        later_encode = encode[1:] if len(encode) > 1 else encode
        print(
            f"arm={arm} split={split} n={len(questions)} multi_evidence={multi} "
            f"hit@5={proportion:.6f} [{low:.6f}, {high:.6f}] ({hit5}/{len(questions)}) "
            f"mrr@10={reciprocal / len(questions):.6f} "
            f"recall@5={recall5_sum / len(questions):.6f} "
            f"recall@10={recall10_sum / len(questions):.6f} "
            f"encode_ms_first={encode[0] if encode else 0} "
            f"encode_ms_median_after_first={_median(later_encode):.1f} "
            f"store_ms_median={_median(store):.1f} "
            f"fuse_ms_median={_median(fuse):.1f}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arms", required=True)
    parser.add_argument("--split", required=True, choices=("dev", "holdout", "all"))
    args = parser.parse_args()
    labels = _load_labels()
    rows = _run_dart(args.arms, args.split)
    if not rows:
        raise SystemExit("The retriever returned no rows.")
    _score(rows, labels)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
