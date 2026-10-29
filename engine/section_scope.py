#!/usr/bin/env python
"""Score a heading question against the section it names.

`build_bench.py` asks "what does this section say?" and then labels one
middle chunk of that section. The two are not the same claim. This script
keeps the chunk span and adds the section range beside it. It does not
re-run retrieval and does not edit the evidence file: offsets come from the
jsonl `error_analysis.py` already wrote, and section bounds come from the
same heading parser `build_bench.parse_sections` used when the questions
were built.

The heading primary is a returned chunk of the gold document whose start
offset sits strictly inside the section. That chunk overlaps the section
and does not contain the heading-line start. Two diagnostics stay beside
it: any overlap of the section, including the heading line, and the
verbatim chunk span. Verbatim questions keep the chunk span as their
metric.

    python engine/section_scope.py \
        --jsonl reports/week5/logs/w5_dev.jsonl \
        --evidence reports/week5/evidence_set_w5.jsonl
"""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_bench import parse_sections, utf16_len  # noqa: E402

# `#### ` is 5 units and the heading line ends with one newline. A returned
# chunk no longer than the heading text plus this allowance is the heading
# line itself. A longer chunk can still contain the heading start; the body
# metric does not count it.
HEADING_LINE_ALLOWANCE = 6


def wilson(successes: int, total: int) -> tuple[float, float, float]:
    if total <= 0:
        return 0.0, 0.0, 0.0
    z = 1.959963984540054
    proportion = successes / total
    z2 = z * z
    denominator = 1.0 + z2 / total
    center = (proportion + z2 / (2.0 * total)) / denominator
    margin = z * math.sqrt(
        proportion * (1.0 - proportion) / total + z2 / (4.0 * total * total)
    )
    margin /= denominator
    return proportion, max(0.0, center - margin), min(1.0, center + margin)


def fmt(successes: int, total: int) -> str:
    proportion, low, high = wilson(successes, total)
    return f"{proportion:.6f} [{low:.6f}, {high:.6f}] ({successes}/{total})"


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def parse_span(raw: str) -> tuple[int, int] | None:
    start = end = None
    for part in raw.split(";"):
        if part.startswith("start="):
            start = int(part.split("=", 1)[1])
        elif part.startswith("end="):
            end = int(part.split("=", 1)[1])
    if start is None or end is None:
        return None
    return start, end


def overlaps(left: int, right: int, start: int, end: int) -> bool:
    return left < end and start < right


def body_start(start_offset: int, bounds: dict) -> bool:
    """Chunk start sits strictly inside the section, after the heading line."""
    return bounds["start"] < start_offset < bounds["end"]


def at_least_one(total: int, relevant: int, cut: int) -> float:
    """P(a uniform draw of `cut` chunks hits at least one relevant chunk)."""
    if total <= 0 or relevant <= 0:
        return 0.0
    if relevant >= total:
        return 1.0
    cut = min(cut, total)
    missed = 1.0
    for index in range(cut):
        missed *= (total - relevant - index) / (total - index)
        if missed <= 0.0:
            return 1.0
    return 1.0 - missed


def poisson_binomial_tail(probabilities: list[float], observed: int) -> float:
    """P(X >= observed) for independent Bernoulli trials with unequal p.

    Same recurrence as `error_analysis._poisson_binomial_tail`. Questions
    share one corpus, so the independence is the reporting convention, not
    a second retrieval.
    """
    if not probabilities:
        return 1.0
    distribution = [1.0]
    for probability in probabilities:
        probability = min(max(probability, 0.0), 1.0)
        updated = [0.0] * (len(distribution) + 1)
        for index, weight in enumerate(distribution):
            updated[index] += weight * (1.0 - probability)
            updated[index + 1] += weight * probability
        distribution = updated
    tail = sum(distribution[observed:]) if observed < len(distribution) else 0.0
    return min(1.0, max(0.0, tail))


def load_text_chunks(db_path: Path) -> dict[str, list[tuple[int, int]]] | None:
    if not db_path.exists():
        return None
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = connection.execute(
            "SELECT document_key, start_offset, end_offset FROM chunk "
            "WHERE space = 'documentText'"
        ).fetchall()
    finally:
        connection.close()
    grouped: dict[str, list[tuple[int, int]]] = {}
    for document_key, start_offset, end_offset in rows:
        grouped.setdefault(str(document_key), []).append(
            (int(start_offset), int(end_offset))
        )
    return grouped


class SectionIndex:
    """Heading ranges for one markdown file, in UTF-16 code units."""

    def __init__(self, root: Path) -> None:
        self._root = root
        self._cache: dict[str, list] = {}

    def sections(self, source_file: str) -> list:
        if source_file not in self._cache:
            path = self._root / source_file
            text = path.read_text(encoding="utf-8")
            self._cache[source_file] = parse_sections(text)
        return self._cache[source_file]

    def locate(self, label: dict) -> dict | None:
        heading = str(label.get("sectionHeading") or "")
        span = parse_span(str(label.get("evidenceLocation") or ""))
        source = str(label.get("sourceFile") or "")
        if not heading or span is None or not source:
            return None
        gold_start, gold_end = span
        matches = [
            section
            for section in self.sections(source)
            if section.heading == heading
            and section.start <= gold_start
            and gold_end <= section.end
        ]
        if len(matches) != 1:
            return None
        section = matches[0]
        return {
            "start": section.start,
            "end": section.end,
            "chars": section.end - section.start,
            "goldStart": gold_start,
            "goldEnd": gold_end,
        }


def section_rank(record: dict, bounds: dict, *, body: bool) -> int:
    target = str((record["detail"].get("targets") or [""])[0])
    best = 0
    for hit in record["hits"]:
        if str(hit.get("documentKey") or "") != target:
            continue
        start_offset = int(hit["startOffset"])
        end_offset = int(hit["endOffset"])
        if body:
            matched = body_start(start_offset, bounds)
        else:
            matched = overlaps(start_offset, end_offset, bounds["start"], bounds["end"])
        if not matched:
            continue
        rank = int(hit["rank"])
        if best == 0 or rank < best:
            best = rank
    return best


def _longest_heading_line(record: dict, bounds: dict, cut: int) -> int:
    target = str((record["detail"].get("targets") or [""])[0])
    longest = 0
    for hit in record["hits"]:
        if str(hit.get("documentKey") or "") != target:
            continue
        if int(hit["rank"]) > cut:
            continue
        start_offset = int(hit["startOffset"])
        end_offset = int(hit["endOffset"])
        if not overlaps(start_offset, end_offset, bounds["start"], bounds["end"]):
            continue
        if body_start(start_offset, bounds):
            continue
        longest = max(longest, end_offset - start_offset)
    return longest


def summarize(
    records: list[dict],
    labels: dict[str, dict],
    index: SectionIndex,
    cut: int,
    chunks_by_doc: dict[str, list[tuple[int, int]]] | None,
) -> None:
    by_id_arm = {(row["id"], row["arm"]): row for row in records}
    arms = sorted({row["arm"] for row in records})
    families = ("heading", "verbatim")

    located = 0
    missing = 0
    missing_ids: list[str] = []
    lengths: list[int] = []
    for label in labels.values():
        if not label.get("answerable") or label.get("family") != "heading":
            continue
        bounds = index.locate(label)
        if bounds is None:
            missing += 1
            missing_ids.append(str(label["id"]))
            continue
        located += 1
        lengths.append(bounds["chars"])
    lengths.sort()
    print(f"heading_section_located={located} unresolved={missing}")
    if missing_ids:
        print("unresolved_ids=" + ",".join(missing_ids))
    if lengths:
        print(
            "section_utf16_chars"
            f" n={len(lengths)} min={lengths[0]}"
            f" median={lengths[len(lengths) // 2]}"
            f" p90={lengths[min(len(lengths) - 1, int(len(lengths) * 0.9))]}"
            f" max={lengths[-1]}"
        )
    print(
        "section_body_hit_definition=stored chunk of the gold document whose "
        "start offset is strictly inside the section"
    )
    print(
        "section_hit_definition=stored chunk of the gold document overlaps the "
        "section, heading line included; diagnostic"
    )
    print(
        f"heading_line_allowance={HEADING_LINE_ALLOWANCE} "
        "pure_heading_line means the longest in-section stored chunk that "
        "contains the heading start is at most len(heading)+allowance"
    )
    print("stored_hits_limit=the jsonl keeps 10 hits; a rank above 10 is unseen")
    print("span_chance_one_chunk=0.000996 does not test a section-body hit")
    _print_body_chance(records, labels, index, chunks_by_doc, cut)
    print()

    print("# --- per arm, per family ---")
    for arm in arms:
        for family in families:
            rows = []
            for (question_id, row_arm), record in by_id_arm.items():
                if row_arm != arm:
                    continue
                label = labels.get(question_id)
                if label is None or label.get("family") != family or not label.get("answerable"):
                    continue
                rows.append((label, record))
            if not rows:
                continue
            doc_hits = sum(int(record["docHitAtCut"]) for _, record in rows)
            span_hits = sum(int(record["spanHitAtCut"]) for _, record in rows)
            section_hits = 0
            body_hits = 0
            heading_line_only = 0
            pure_heading_line = 0
            longer_than_heading = 0
            longer_ids: list[str] = []
            file_in_not_stored = 0
            section_known = 0
            wrong_span = 0
            wrong_span_in_section = 0
            doc_outside_label = 0
            doc_outside_located = 0
            for label, record in rows:
                if record["class"] == "wrong_span_same_doc":
                    wrong_span += 1
                if int(record["docHitAtCut"]) == 0:
                    doc_outside_label += 1
                bounds = index.locate(label)
                if bounds is None:
                    continue
                section_known += 1
                inclusive = section_rank(record, bounds, body=False)
                body_rank = section_rank(record, bounds, body=True)
                in_section = 0 < inclusive <= cut
                in_body = 0 < body_rank <= cut
                if in_section:
                    section_hits += 1
                if record["class"] == "wrong_span_same_doc" and in_section:
                    wrong_span_in_section += 1
                if in_body:
                    body_hits += 1
                elif in_section:
                    heading_line_only += 1
                    longest = _longest_heading_line(record, bounds, cut)
                    allowance = utf16_len(str(label.get("sectionHeading") or ""))
                    allowance += HEADING_LINE_ALLOWANCE
                    if longest <= allowance:
                        pure_heading_line += 1
                    else:
                        longer_than_heading += 1
                        longer_ids.append(str(record["id"]))
                elif int(record["docHitAtCut"]) == 0:
                    doc_outside_located += 1
                else:
                    file_in_not_stored += 1
            total = len(rows)
            outside_section = wrong_span - wrong_span_in_section
            other_miss = section_known - section_hits - outside_section - doc_outside_label
            print(
                f"arm={arm} family={family} n={total} section_located={section_known} "
                f"doc_hit@{cut}={fmt(doc_hits, total)} "
                f"span_hit@{cut}={fmt(span_hits, total)} "
                f"section_body_hit@{cut}={fmt(body_hits, section_known)} "
                f"section_hit@{cut}={fmt(section_hits, section_known)} "
                f"heading_line_only={heading_line_only} "
                f"pure_heading_line={pure_heading_line} "
                f"longer_than_heading={longer_than_heading} "
                f"file_outside_cut={doc_outside_located} "
                f"file_in_section_not_in_stored_hits={file_in_not_stored} "
                f"wrong_span={wrong_span} "
                f"wrong_span_inside_section={wrong_span_in_section} "
                f"section_miss_file_outside_cut={doc_outside_label} "
                f"section_miss_wrong_section={outside_section} "
                f"section_miss_other={other_miss}"
            )
            if longer_ids:
                print(
                    f"arm={arm} family={family} longer_than_heading_ids="
                    + ",".join(longer_ids)
                )
    print()


def _print_body_chance(
    records: list[dict],
    labels: dict[str, dict],
    index: SectionIndex,
    chunks_by_doc: dict[str, list[tuple[int, int]]] | None,
    cut: int,
) -> None:
    """Analytic null for the heading body metric on this payload's questions."""
    print("# --- heading body chance, this payload ---")
    if chunks_by_doc is None:
        print("skipped=missing index")
        return
    pool = sum(len(chunks) for chunks in chunks_by_doc.values())
    probability_by_id: dict[str, float] = {}
    relevant_counts: list[int] = []
    for record in records:
        question_id = str(record["id"])
        if question_id in probability_by_id:
            continue
        label = labels.get(question_id)
        if label is None or label.get("family") != "heading" or not label.get("answerable"):
            continue
        bounds = index.locate(label)
        if bounds is None:
            continue
        document = str(label.get("relevantDocumentId") or "")
        relevant = sum(
            1
            for start_offset, _end in chunks_by_doc.get(document, [])
            if body_start(start_offset, bounds)
        )
        relevant_counts.append(relevant)
        probability_by_id[question_id] = at_least_one(pool, relevant, cut)
    if not relevant_counts:
        print("heading_questions=0")
        return
    relevant_counts.sort()
    mean_chance = sum(probability_by_id.values()) / len(probability_by_id)
    print(f"pool_chunks={pool} space=documentText")
    print(
        "relevant_definition=chunk of the gold document with "
        "section.start < start_offset < section.end"
    )
    print(
        "relevant_chunks"
        f" n={len(relevant_counts)} min={relevant_counts[0]}"
        f" median={relevant_counts[len(relevant_counts) // 2]}"
        f" p90={relevant_counts[min(len(relevant_counts) - 1, int(len(relevant_counts) * 0.9))]}"
        f" max={relevant_counts[-1]}"
    )
    print(f"mean_body_chance@{cut}={mean_chance:.6f}")
    by_arm: dict[str, list[str]] = {}
    for record in records:
        question_id = str(record["id"])
        if question_id not in probability_by_id:
            continue
        by_arm.setdefault(str(record["arm"]), []).append(question_id)
    for arm in sorted(by_arm):
        arm_ids = by_arm[arm]
        arm_probabilities = [probability_by_id[question_id] for question_id in arm_ids]
        observed = 0
        for question_id in arm_ids:
            record = next(
                row
                for row in records
                if str(row["id"]) == question_id and str(row["arm"]) == arm
            )
            bounds = index.locate(labels[question_id])
            if bounds is None:
                continue
            rank = section_rank(record, bounds, body=True)
            if 0 < rank <= cut:
                observed += 1
        tail = poisson_binomial_tail(arm_probabilities, observed)
        print(
            f"arm={arm} section_body_hits={observed} "
            f"body_null_p={tail:.6f} questions={len(arm_ids)}"
        )


def wrong_section_examples(
    records: list[dict],
    labels: dict[str, dict],
    index: SectionIndex,
    db_path: Path,
    cut: int,
) -> None:
    """Rank-1 text for heading questions that hit the file and miss the section.

    Limited to arm A1. Holdout is not inspected here.
    """
    if not db_path.exists():
        print("# --- wrong-section examples ---")
        print(f"skipped=missing index {db_path}")
        return
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    print("# --- A1 heading, file in the cut, section not in the stored hits ---")
    print(f"db={db_path}")
    shown = 0
    starts_at_zero = 0
    for record in records:
        if record["arm"] != "A1" or not record["answerable"]:
            continue
        label = labels.get(record["id"])
        if label is None or label.get("family") != "heading":
            continue
        if int(record["docHitAtCut"]) != 1:
            continue
        bounds = index.locate(label)
        if bounds is None or 0 < section_rank(record, bounds, body=False) <= cut:
            continue
        target = str(record["detail"]["targets"][0])
        top = next(
            (
                hit
                for hit in record["hits"]
                if str(hit.get("documentKey") or "") == target
            ),
            None,
        )
        if top is None:
            continue
        row = connection.execute(
            "SELECT body FROM chunk WHERE document_key = ? AND start_offset = ? AND end_offset = ?",
            (target, int(top["startOffset"]), int(top["endOffset"])),
        ).fetchone()
        body = " ".join(str(row[0]).split()) if row else ""
        if int(top["startOffset"]) == 0:
            starts_at_zero += 1
        print(
            f"{record['id']} rank={top['rank']} "
            f"offsets={top['startOffset']}-{top['endOffset']} "
            f"chars={int(top['endOffset']) - int(top['startOffset'])} "
            f"heading={label.get('sectionHeading')} "
            f"body={body[:80]}"
        )
        shown += 1
    connection.close()
    print(f"shown={shown} same_file_best_hit_starts_at_0={starts_at_zero}")
    print(
        "reading=the gold file is inside the cut and no stored hit overlaps the "
        "named section. same_file_best_hit_starts_at_0 counts how often that "
        "chunk is the H1 at offset 0"
    )
    print()


def keyword_difference(records: list[dict], labels: dict[str, dict], cut: int) -> None:
    table = {(row["id"], row["arm"]): row for row in records}
    if not any(arm == "A0" for _, arm in table) or not any(arm == "A1" for _, arm in table):
        print("# --- keyword difference ---")
        print("skipped=this payload has no A0/A1 pair")
        return
    ids = sorted(
        question_id
        for question_id, label in labels.items()
        if label.get("answerable") and (question_id, "A0") in table and (question_id, "A1") in table
    )
    both = a0_only = a1_only = neither = 0
    a0_only_ids: list[str] = []
    # Slots in A0's stored top-`cut` whose document is absent from A1's stored hits.
    # This is the candidate-pool difference the fused top-5 cannot show, because
    # a keyword-only row is arithmetically below a full text top-5.
    exclusive_slots = 0
    questions_with_exclusive = 0
    for question_id in ids:
        a0 = table[(question_id, "A0")]
        a1 = table[(question_id, "A1")]
        a0_hit = int(a0["docHitAtCut"]) == 1
        a1_hit = int(a1["docHitAtCut"]) == 1
        if a0_hit and a1_hit:
            both += 1
        elif a0_hit:
            a0_only += 1
            a0_only_ids.append(question_id)
        elif a1_hit:
            a1_only += 1
        else:
            neither += 1
        a1_docs = {str(hit.get("documentKey") or "") for hit in a1["hits"]}
        exclusive = [
            hit
            for hit in a0["hits"]
            if int(hit["rank"]) <= cut
            and str(hit.get("documentKey") or "") not in a1_docs
        ]
        exclusive_slots += len(exclusive)
        if exclusive:
            questions_with_exclusive += 1
    print("# --- keyword difference, gold document ---")
    print(f"answerable={len(ids)} cut={cut}")
    print(
        f"both_doc_hit={both} a0_only={a0_only} a1_only={a1_only} neither={neither}"
    )
    if a0_only_ids:
        print("a0_only_ids=" + ",".join(a0_only_ids))
    print(
        f"a0_top{cut}_slots_whose_document_is_absent_from_a1_stored_hits="
        f"{exclusive_slots}"
    )
    print(
        f"questions_with_such_a_slot={questions_with_exclusive} "
        "stored_hits_limit=10"
    )
    print(
        "reading=a0_only is a gold-file the keyword arm ranks in the cut and "
        "the text arm does not; fused keyword_only=0 does not measure this"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--evidence", default="reports/week5/evidence_set_w5.jsonl")
    parser.add_argument("--holdout-jsonl", default="")
    parser.add_argument("--db", default="reports/week5/.index/bench.sqlite")
    parser.add_argument("--cut", type=int, default=5)
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    if args.out:
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = ROOT / out_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        sys.stdout = out_path.open("w", encoding="utf-8", newline="\n")

    jsonl_path = Path(args.jsonl)
    if not jsonl_path.is_absolute():
        jsonl_path = ROOT / jsonl_path
    evidence_path = Path(args.evidence)
    if not evidence_path.is_absolute():
        evidence_path = ROOT / evidence_path
    if not jsonl_path.exists():
        raise SystemExit(f"Missing analysis payload: {jsonl_path}")
    if not evidence_path.exists():
        raise SystemExit(f"Missing evidence: {evidence_path}")

    labels = {row["id"]: row for row in load_jsonl(evidence_path)}
    index = SectionIndex(ROOT)
    dev = load_jsonl(jsonl_path)
    db_path = Path(args.db)
    if not db_path.is_absolute():
        db_path = ROOT / db_path
    chunks_by_doc = load_text_chunks(db_path)
    print("# section scope")
    print(f"jsonl={jsonl_path}")
    print(f"evidence={evidence_path}")
    print("retrieval_rerun=0")
    print(f"cut={args.cut}")
    print(f"db={db_path}")
    print()
    summarize(dev, labels, index, args.cut, chunks_by_doc)
    wrong_section_examples(dev, labels, index, db_path, args.cut)
    keyword_difference(dev, labels, args.cut)

    holdout_arg = args.holdout_jsonl
    if holdout_arg:
        holdout_path = Path(holdout_arg)
        if not holdout_path.is_absolute():
            holdout_path = ROOT / holdout_path
        if not holdout_path.exists():
            raise SystemExit(f"Missing holdout payload: {holdout_path}")
        print()
        print("# --- holdout payload, not a new retrieval ---")
        print(f"jsonl={holdout_path}")
        print("retrieval_rerun=0")
        summarize(load_jsonl(holdout_path), labels, index, args.cut, chunks_by_doc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
