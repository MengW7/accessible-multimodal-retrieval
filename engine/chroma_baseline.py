"""Chroma cosine control for the exported vectors.

The collection metric is cosine. search_ef is raised so HNSW stays close to
brute force. A numpy ranking is written beside the Chroma ranking so a
divergence is visible before anyone blames SQLite.

    python engine/chroma_baseline.py
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "week4" / "vectors"
LOGS = ROOT / "week4" / "logs"


def _load(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def _vector(row: dict) -> np.ndarray:
    raw = base64.b64decode(row["vectorB64"])
    values = np.frombuffer(raw, dtype="<f4")
    if values.shape != (int(row["dim"]),):
        raise RuntimeError(f"{row.get('chunkId', row.get('id'))} dim {values.shape}")
    return np.array(values, dtype=np.float32, copy=True)


def _sort(hits: list[dict]) -> list[dict]:
    def key(hit: dict) -> tuple:
        page = hit["pageNumber"]
        return (
            -float(hit["score"]),
            hit["relativePath"],
            page is None,
            0 if page is None else int(page),
            int(hit["startOffset"]),
        )

    return sorted(hits, key=key)


def _collection(client, name: str, rows: list[dict]):
    metadata = {"hnsw:space": "cosine", "hnsw:search_ef": 512}
    try:
        collection = client.create_collection(name=name, metadata=metadata)
    except Exception:
        collection = client.create_collection(
            name=name,
            metadata={"hnsw:space": "cosine"},
        )
        print(f"{name}_search_ef=rejected", file=sys.stderr)
    ids = []
    embeddings = []
    metadatas = []
    for row in rows:
        chunk_id = row["chunkId"]
        if chunk_id in ids:
            raise RuntimeError(f"duplicate chunkId {chunk_id}")
        ids.append(chunk_id)
        embeddings.append(_vector(row).tolist())
        page = row.get("pageNumber")
        metadatas.append(
            {
                "relativePath": row["relativePath"],
                "pageNumber": -1 if page is None else int(page),
                "startOffset": int(row["startOffset"]),
            }
        )
    collection.add(ids=ids, embeddings=embeddings, metadatas=metadatas)
    return collection


def _numpy_top5(rows: list[dict], query: np.ndarray) -> list[dict]:
    hits = []
    query64 = query.astype(np.float64)
    for row in rows:
        score = float(np.dot(_vector(row).astype(np.float64), query64))
        page = row.get("pageNumber")
        hits.append(
            {
                "chunkId": row["chunkId"],
                "score": score,
                "relativePath": row["relativePath"],
                "pageNumber": page,
                "startOffset": int(row["startOffset"]),
            }
        )
    return _sort(hits)[:5]


def _chroma_top5(collection, query: np.ndarray, n_results: int = 5) -> list[dict]:
    found = collection.query(
        query_embeddings=[query.tolist()],
        n_results=n_results,
        include=["distances", "metadatas"],
    )
    hits = []
    ids = found["ids"][0]
    distances = found["distances"][0]
    metadatas = found["metadatas"][0]
    for chunk_id, distance, meta in zip(ids, distances, metadatas, strict=True):
        page = int(meta["pageNumber"])
        hits.append(
            {
                "chunkId": chunk_id,
                "score": 1.0 - float(distance),
                "relativePath": meta["relativePath"],
                "pageNumber": None if page < 0 else page,
                "startOffset": int(meta["startOffset"]),
            }
        )
    return _sort(hits)


def _relevant(relative_path: str, targets: list[str]) -> bool:
    path = relative_path.replace("\\", "/")
    name = path.rsplit("/", 1)[-1]
    for raw in targets:
        target = raw.replace("\\", "/")
        if path == target or target.endswith("/" + path) or target.endswith("/" + name):
            return True
    return False


def _wilson(successes: int, total: int) -> tuple[float, float, float]:
    if total <= 0:
        return 0.0, 0.0, 0.0
    z = 1.959963984540054
    proportion = successes / total
    denominator = 1 + z * z / total
    center = (proportion + z * z / (2 * total)) / denominator
    margin = z * ((proportion * (1 - proportion) / total + z * z / (4 * total * total)) ** 0.5)
    margin /= denominator
    return proportion, max(0.0, center - margin), min(1.0, center + margin)


def main() -> int:
    import chromadb

    samples = _load(VECTORS / "w3_samples.jsonl")
    evidence = _load(VECTORS / "w3_evidence_images.jsonl")
    queries = _load(VECTORS / "w3_queries.jsonl")
    rows = samples + evidence
    by_space: dict[str, list[dict]] = {}
    for row in rows:
        by_space.setdefault(row["space"], []).append(row)
    client = chromadb.EphemeralClient()
    collections = {
        space: _collection(client, space, space_rows)
        for space, space_rows in by_space.items()
    }
    labels = {
        row["id"]: row
        for row in _load(ROOT / "reports" / "week3" / "evidence_set.jsonl")
    }
    LOGS.mkdir(parents=True, exist_ok=True)
    top_path = LOGS / "chroma_top5.jsonl"
    numpy_lines = []
    compared = 0
    agreed = 0
    hit5 = 0
    reciprocal = 0.0
    scored = 0
    with top_path.open("w", encoding="utf-8", newline="\n") as handle:
        for query in queries:
            space = query["space"]
            vector = _vector(query)
            chroma_hits = _chroma_top5(collections[space], vector, n_results=10)
            numpy_hits = _numpy_top5(by_space[space], vector)
            handle.write(
                json.dumps(
                    {"queryId": query["id"], "top5": chroma_hits[:5]},
                    ensure_ascii=False,
                )
                + "\n"
            )
            for slot in range(5):
                compared += 1
                if (
                    slot < len(chroma_hits)
                    and slot < len(numpy_hits)
                    and chroma_hits[slot]["chunkId"] == numpy_hits[slot]["chunkId"]
                ):
                    agreed += 1
            item = labels.get(query["id"])
            if item is None:
                continue
            targets = item.get("relevantDocumentIds") or [item["relevantDocumentId"]]
            rank = 0
            for index, hit in enumerate(chroma_hits, start=1):
                if _relevant(hit["relativePath"], targets):
                    rank = index
                    break
            scored += 1
            if rank and rank <= 5:
                hit5 += 1
            if rank and rank <= 10:
                reciprocal += 1.0 / rank
    rate = agreed / compared if compared else 0.0
    proportion, low, high = _wilson(hit5, scored)
    numpy_lines.append(f"chroma_vs_numpy_positions={compared}")
    numpy_lines.append(f"chroma_vs_numpy_agreed={agreed}")
    numpy_lines.append(f"chroma_vs_numpy_agreement={rate:.6f}")
    numpy_lines.append("score=1-distance")
    numpy_lines.append("hnsw_space=cosine")
    numpy_lines.append(f"chromadb_version={chromadb.__version__}")
    numpy_lines.append(f"queries={scored}")
    numpy_lines.append(
        f"hit@5={proportion:.6f} [{low:.6f}, {high:.6f}] ({hit5}/{scored})"
    )
    numpy_lines.append(f"mrr@10={reciprocal / scored if scored else 0.0:.6f}")
    numpy_lines.append("metric_layer=storage_baseline")
    numpy_lines.append(
        "note=query vectors are the exported question embeddings; "
        "this is the Chroma control, not the product retriever"
    )
    text = "\n".join(numpy_lines) + "\n"
    (LOGS / "chroma_numpy.txt").write_text(text, encoding="utf-8")
    (LOGS / "chroma_baseline.txt").write_text(text, encoding="utf-8")
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
