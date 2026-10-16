"""NQ-open embedding proxy for Week 3.

This is not document retrieval. The repository subset has question and
answer strings only. Queries are the 300 questions, in file order:
nq_open_val50.jsonl then nq_open_val250_part2.jsonl. The candidate pool
is the 300 first gold answers plus the 300 questions (600 rows).

Each query drops its own question row before ranking. That row is the
query text, so its cosine is 1 and would pin recall@1 at 0. The other
299 questions stay as distractors. The relevant row is that question's
own first answer. Ties keep the lower candidate index.

Token ids follow tokenizers 0.23.2 with truncation disabled. Padding,
mean pooling, and L2 follow TextInputBuilder and TextEmbedder. Inputs
longer than 128 tokens are refused, not truncated.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from tokenizers import Tokenizer

from w3_embed_lib import ROOT, TEXT_DIR, TEXT_MAX_LEN, l2_normalize, session

NQ_FILES = (
    ROOT / "datasets" / "nq" / "validation" / "nq_open_val50.jsonl",
    ROOT / "datasets" / "nq" / "validation" / "nq_open_val250_part2.jsonl",
)
MODEL_PATH = TEXT_DIR / "onnx" / "model.onnx"
TOKENIZER_PATH = TEXT_DIR / "tokenizer.json"


def _read_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in NQ_FILES:
        if not path.is_file():
            raise RuntimeError(f"missing {path}")
        file_rows = 0
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            item = json.loads(line)
            if not isinstance(item, dict):
                raise RuntimeError(f"{path.name}:{line_number} is not an object")
            question = item.get("question")
            answers = item.get("answers")
            if not isinstance(question, str) or not question:
                raise RuntimeError(f"{path.name}:{line_number} has no question")
            if not isinstance(answers, list) or not answers or not isinstance(answers[0], str):
                raise RuntimeError(f"{path.name}:{line_number} has no first answer")
            if not answers[0]:
                raise RuntimeError(f"{path.name}:{line_number} first answer is empty")
            rows.append({"question": question, "answer": answers[0], "file": path.name})
            file_rows += 1
        print(f"nq_file={path.relative_to(ROOT).as_posix()} lines={file_rows}")
    if len(rows) != 300:
        raise RuntimeError(f"expected 300 questions, found {len(rows)}")
    return rows


def _encode(tokenizer: Tokenizer, pad_id: int, text: str) -> tuple[np.ndarray, np.ndarray]:
    encoding = tokenizer.encode(text)
    ids = encoding.ids
    if len(ids) > TEXT_MAX_LEN:
        raise RuntimeError(
            f"{len(ids)} tokens exceed {TEXT_MAX_LEN}: {text[:80]}"
        )
    padded = np.zeros((1, TEXT_MAX_LEN), dtype=np.int64)
    mask = np.zeros((1, TEXT_MAX_LEN), dtype=np.int64)
    padded[0, : len(ids)] = np.asarray(ids, dtype=np.int64)
    mask[0, : len(ids)] = 1
    if len(ids) < TEXT_MAX_LEN:
        padded[0, len(ids) :] = pad_id
    return padded, mask


def _embed_many(
    model,
    tokenizer: Tokenizer,
    pad_id: int,
    texts: list[str],
) -> tuple[np.ndarray, list[float]]:
    vectors = np.empty((len(texts), 384), dtype=np.float32)
    timings: list[float] = []
    for index, text in enumerate(texts):
        ids, mask = _encode(tokenizer, pad_id, text)
        feeds = {
            "input_ids": ids,
            "attention_mask": mask,
            "token_type_ids": np.zeros_like(ids),
        }
        started = time.perf_counter()
        hidden = model.run(["last_hidden_state"], feeds)[0]
        timings.append((time.perf_counter() - started) * 1000.0)
        weights = mask.astype(np.float32)[..., None]
        counted = int(mask.sum())
        if counted == 0:
            raise RuntimeError("attention mask is empty")
        pooled = (hidden.astype(np.float32) * weights).sum(axis=1)[0] / counted
        if not np.isfinite(pooled).all():
            raise RuntimeError(f"non-finite pooled vector at {index}")
        normalized, norm = l2_normalize(pooled)
        if abs(norm) == 0 or not np.isfinite(normalized).all():
            raise RuntimeError(f"normalization failed at {index}")
        vectors[index] = normalized
    return vectors, timings


def _median(values: list[float]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def _rank_gold(scores: np.ndarray, query_index: int) -> int:
    own_question = 300 + query_index
    usable = scores.copy()
    usable[own_question] = -np.inf
    order = np.argsort(-usable, kind="stable")
    gold_at = int(np.where(order == query_index)[0][0])
    return gold_at + 1


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    print("metric_layer=embedding_proxy")
    print("not_measured=document_retrieval")
    print("not_measured=generation")
    print("protocol=nq-a")
    print("query_order=nq_open_val50 then nq_open_val250_part2")
    print("pool=600")
    print("pool_parts=first_gold_answer:300 question_distractor:300")
    print(
        "ranking_exclusion=drop the query's own question row; "
        "the other 299 questions stay"
    )
    print("ranking_pool=599")
    print("relevant=the paired first gold answer row")
    print("tie_break=higher cosine, then lower candidate index")
    print("tokenizer=tokenizers no_truncation manual_pad")
    print("pooling=mean attention_mask")
    print("normalized=l2")
    print(f"max_length={TEXT_MAX_LEN}")
    print(f"model={MODEL_PATH.relative_to(ROOT).as_posix()}")

    rows = _read_rows()
    tokenizer = Tokenizer.from_file(str(TOKENIZER_PATH))
    tokenizer.no_truncation()
    pad_id = tokenizer.token_to_id("<pad>")
    if pad_id is None:
        raise RuntimeError("tokenizer has no <pad>")

    texts = [str(row["answer"]) for row in rows] + [str(row["question"]) for row in rows]
    if len(texts) != 600:
        raise RuntimeError(f"pool size {len(texts)}")

    load_started = time.perf_counter()
    model = session(MODEL_PATH)
    load_ms = (time.perf_counter() - load_started) * 1000.0
    print(f"load_ms={load_ms:.2f}")

    vectors, timings = _embed_many(model, tokenizer, pad_id, texts)
    if vectors.shape != (600, 384):
        raise RuntimeError(f"unexpected matrix {vectors.shape}")
    print(f"embedded=600 dim=384 space=documentText")
    print(f"infer_ms_median={_median(timings):.2f}")
    print(f"infer_ms_max={max(timings):.2f}")
    print("infer_ms_excludes=model_load")

    scores = vectors @ vectors.T
    ranks: list[int] = []
    for index in range(300):
        ranks.append(_rank_gold(scores[300 + index], index))
    hits_at_1 = sum(rank <= 1 for rank in ranks)
    hits_at_5 = sum(rank <= 5 for rank in ranks)
    reciprocal = sum(1.0 / rank for rank in ranks)
    print(f"queries_scored=300")
    print(f"queries_skipped=0")
    print(f"recall@1_hits={hits_at_1}/300")
    print(f"recall@5_hits={hits_at_5}/300")
    print(f"recall@1={hits_at_1 / 300:.6f}")
    print(f"recall@5={hits_at_5 / 300:.6f}")
    print(f"mrr={reciprocal / 300:.6f}")
    print(f"rank_min={min(ranks)}")
    print(f"rank_median={_median([float(rank) for rank in ranks]):.1f}")
    print(f"rank_max={max(ranks)}")
    print(f"chance_recall@1={1 / 599:.6f}")
    print(f"chance_recall@5={5 / 599:.6f}")
    print("single_relevant=1")
    print("recall_equals_hit=1")

    for index in range(3):
        question = str(rows[index]["question"]).replace("\n", " ")
        answer = str(rows[index]["answer"]).replace("\n", " ")
        print(
            f"example index={index} rank={ranks[index]} "
            f"question={question} gold={answer}"
        )
    print("gate=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001 — probe should print the reason
        print(f"gate=fail error={error}")
        print(f"gate=fail error={error}", file=sys.stderr)
        raise SystemExit(1) from error
