"""用 week4 自建证据集验证邻域扩展。

证据集 `reports/week4/evidence_set_w4.jsonl` 是 2026-10-25 在 `docs.sqlite`
上标好的：每条题给了命中的 chunk 序号 `chunkIndexes`，其中 `crossChunk: true`
表示证据横跨多个块。此前这份集子从未被任何日志引用（只建集、没验证）。

本脚本做两件事，都不改任何既有文件：

1. **块级覆盖**：从库中取出该文档的全部块，检查证据集声称的 `chunkIndexes`
   是否真是包含答案的相邻块（用 evidenceText 的片段做子串核对）。
2. **邻域可达**：对每个 `crossChunk: true` 的题，验证「只取其中一块再扩展
   到同页相邻块」能否覆盖全部声称的块 —— 这是 W4 决策 5 的承诺，
   也是 W5 拿结果去高亮时的前提。

用法（仓库根目录）：

    engine\\.venv\\Scripts\\python.exe engine\\eval_neighborhood.py
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "reports" / "week4" / "evidence_set_w4.jsonl"
DB = ROOT / "reports" / "week4" / ".index" / "docs.sqlite"


def _load_evidence() -> list[dict]:
    rows = []
    for line in EVIDENCE.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def _chunks(connection: sqlite3.Connection, document_key: str) -> list[tuple[int, int, str]]:
    """(chunk_index, rowid, body) 按块序返回。"""
    cursor = connection.execute(
        "SELECT chunk_index, id, body FROM chunk WHERE document_key = ? "
        "ORDER BY chunk_index",
        (document_key,),
    )
    return [(int(row[0]), int(row[1]), row[2]) for row in cursor.fetchall()]


def main() -> int:
    if not DB.exists():
        raise SystemExit(f"Missing index: {DB}")
    if not EVIDENCE.exists():
        raise SystemExit(f"Missing evidence set: {EVIDENCE}")

    rows = _load_evidence()
    connection = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        covered = 0
        reached = 0
        exists_count = 0
        cross_total = 0
        problems: list[str] = []
        order: dict[str, list[int]] = {}

        for row in rows:
            evidence_id = row["id"]
            document = row["relevantDocumentId"]
            claimed = [int(value) for value in row.get("chunkIndexes") or []]
            chunks = _chunks(connection, document)
            if not chunks:
                problems.append(f"{evidence_id}: no chunks for {document}")
                continue
            index_of = {chunk_index: position for position, (chunk_index, _, _) in enumerate(chunks)}
            order[document] = [chunk_index for chunk_index, _, _ in chunks]

            # 1) 声称的块是否真的存在，且拼起来能覆盖 evidenceText 的首尾片段。
            if not all(index in index_of for index in claimed):
                problems.append(f"{evidence_id}: claimed chunks {claimed} not all present")
                continue
            bodies = [chunks[index_of[index]][2] for index in claimed]
            joined = "\n".join(bodies)
            head = row["evidenceText"].strip()[:24]
            if head and head not in joined:
                problems.append(f"{evidence_id}: evidenceText head not found in claimed chunks")
                continue
            covered += 1

            # 2) 跨块题。±1 规则不变。两个数分开报，不改标注：
            # exists：存在某一块，它的 ±1 能盖住全部声称块。
            # forall：无论命中声称块里的哪一块，±1 都能盖住全部。
            # reachable_with_one_hop 保持原来的 forall 口径，已记录的 5/7 不改含义。
            if row.get("crossChunk"):
                cross_total += 1
                positions = [index_of[index] for index in claimed]
                windows = []
                for start in positions:
                    windows.append({
                        chunks[position][0]
                        for position in range(
                            max(0, start - 1),
                            min(len(chunks), start + 2),
                        )
                    })
                exists = any(set(claimed).issubset(window) for window in windows)
                forall = all(set(claimed).issubset(window) for window in windows)
                if exists:
                    exists_count += 1
                if forall:
                    reached += 1
                print(
                    f"row {evidence_id} span={len(claimed)} "
                    f"exists={int(exists)} forall={int(forall)}"
                )
                if not forall:
                    problems.append(
                        f"{evidence_id}: forall ±1 cannot cover {claimed} "
                        f"(exists={int(exists)}, positions {positions})"
                    )

        print(f"evidence_rows={len(rows)}")
        print(f"chunk_coverage_ok={covered}")
        print(f"cross_chunk_rows={cross_total}")
        print(f"exists_one_anchor={exists_count}")
        print(f"forall_anchors={reached}")
        print(f"reachable_with_one_hop={reached}")
        print(f"documents={len(order)}")
        for document, indexes in sorted(order.items()):
            print(f"document_chunks={document} n={len(indexes)}")
        if problems:
            print("problems:")
            for problem in problems:
                print(f"  - {problem}")
        else:
            print("problems=0")
        return 0 if covered == len(rows) and reached == cross_total else 1
    finally:
        connection.close()


if __name__ == "__main__":
    sys.exit(main())
