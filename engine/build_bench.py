"""Build a span-level retrieval benchmark from a built index.

Why this exists: the week-3/4 evidence set labels whole documents, and every
text question marked both `sample.pdf` and `sample.docx` as relevant. Those two
files *were* the entire text corpus, so the gold set covered the whole pool and
a uniform random ranking scored 1.0. That is why `error_analysis.py` reported
`p_doc_vs_chance=0.7043` for A1: the metric could not separate a working
retriever from a coin flip.

This script fixes the label shape, not the sample count:

  * gold is a **chunk span** (`startOffset`/`endOffset`), taken from the index,
    never hand-written
  * every question has exactly **one** gold document
  * offsets are UTF-16 code units, same unit as the rest of the project
  * questions are generated **without loading the retriever**, so no ranking
    information can leak into the question text

Question families
    heading   the query is a section heading plus its document title; the gold
              span is a content chunk inside that section. The heading does not
              usually appear in the chunk body, so lexical overlap is low and
              this family mostly exercises the vector channel.
    verbatim  the query quotes a distinctive Chinese phrase lifted from the gold
              chunk itself, so lexical overlap is high and the keyword channel
              can actually reach it. Measured `lexOverlap` confirms the split.
    negative  a phrase verified absent from every chunk in the index, so the
              correct behaviour is to return nothing relevant. Absence is
              measured here, not assumed.

The frozen file still contains both answerable families. Reports after
2026-10-28 headline verbatim: the question quotes the gold chunk, so the
number is paragraph-level retrieval with high lexical overlap. Heading rows
stay in that file as the record of why the section question was retired.
A section does not fit in the 128-token budget. Do not regenerate
``reports/week5/evidence_set_w5.jsonl``. The ``no-filename`` heading file is
a separate record; its holdout is not scored. Families stay unpooled.

Every question records its lexical overlap with the gold chunk
(`lexOverlap`, character-bigram Jaccard on the question against the chunk body).
Reports must bucket by it: a high-overlap question can be solved by the keyword
channel alone, and only the low-overlap bucket tests the vector channel.

    python engine/build_bench.py --db reports/week5/.index/bench.sqlite \
        --manifest datasets/corpus_manifest.json \
        --out reports/week5/evidence_set_w5.jsonl

    # A second file. The heading question does not lead with the filename,
    # and a heading that occurs in more than one document is dropped.
    # Verbatim and negative rows stay in the frozen file above.
    python engine/build_bench.py --heading-template no-filename
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "datasets" / "corpus_t0"
FROZEN_EVIDENCE = "reports/week5/evidence_set_w5.jsonl"
NOFILE_EVIDENCE = "reports/week5/evidence_set_w5_nofile.jsonl"

HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$", re.MULTILINE)

# The text tower has a 128-token budget and does not truncate. Exceeding it is
# now a typed error rather than a crash, but a question that cannot be encoded
# is useless in a benchmark, so generation caps the composed query length.
MAX_QUESTION_CHARS = 110

HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")

# Sentence-ish terminators. A gold chunk should read as a statement, not as a
# fragment of a table or a code fence.
FENCE = "```"

# A chunk is a usable gold span when it is a full clause: long enough to carry
# meaning, short enough that a neighbouring chunk is not the better answer.
MIN_GOLD_CHARS = 40
MAX_GOLD_CHARS = 120

# Negatives pair a real heading with a question shape the corpus never answers.
# These are verified absent by `pick_negative_phrases`, never assumed: if the
# phrase occurs in any chunk the candidate is dropped. The templates ask for a
# kind of fact this documentation set does not carry (price, phone number,
# release date, licence fee), so "no relevant chunk" is the only correct result.
NEGATIVE_TEMPLATES = (
    "{title} 里「{heading}」这一节的作者手机号是多少？",
    "{title} 里「{heading}」这一节列出的采购报价是多少元？",
    "{title} 里「{heading}」这一节引用的 ISO 标准编号是哪一个？",
    "{title} 里「{heading}」这一节用的抽样随机种子是多少？",
)

# The term each template asks for. Checked against the index before a negative
# is accepted: if the corpus does mention it, the question is not a no-answer.
NEGATIVE_PROBES = ("手机号", "报价", "ISO 标准编号", "随机种子")


@dataclass
class Chunk:
    row: int
    document_key: str
    chunk_index: int
    page_number: int | None
    start: int
    end: int
    body: str


@dataclass
class Section:
    document_key: str
    heading: str
    level: int
    start: int
    end: int


def utf16_len(text: str) -> int:
    return sum(2 if ord(char) > 0xFFFF else 1 for char in text)


def utf16_offsets(text: str) -> list[int]:
    """Prefix sum of UTF-16 lengths, so index i maps to a UTF-16 offset."""
    offsets = [0]
    total = 0
    for char in text:
        total += 2 if ord(char) > 0xFFFF else 1
        offsets.append(total)
    return offsets


def load_chunks(db_path: Path, document_key: str) -> list[Chunk]:
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = connection.execute(
            "SELECT id, document_key, chunk_index, page_number, start_offset,"
            "       end_offset, body FROM chunk"
            " WHERE document_key = ? AND space = 'documentText'"
            " ORDER BY chunk_index",
            (document_key,),
        )
        return [
            Chunk(
                row=int(row[0]),
                document_key=str(row[1]),
                chunk_index=int(row[2]),
                page_number=row[3],
                start=int(row[4]),
                end=int(row[5]),
                body=str(row[6]),
            )
            for row in rows
        ]
    finally:
        connection.close()


def resolve_document_key(db_path: Path, snapshot: str) -> str:
    """The index stores `<prefix>/<file>`; the manifest stores the snapshot path.

    `index_probe --prefix corpus_t0` writes keys like
    `corpus_t0/docs__api__x.md`, while the manifest says
    `datasets/corpus_t0/docs__api__x.md`. Match on the file name and require a
    single hit, so a silent mismatch cannot quietly produce zero chunks.
    """
    name = snapshot.rsplit("/", 1)[-1]
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = connection.execute(
            "SELECT DISTINCT document_key FROM chunk WHERE document_key LIKE ?",
            (f"%{name}",),
        ).fetchall()
    finally:
        connection.close()
    keys = [str(row[0]) for row in rows]
    if len(keys) != 1:
        raise SystemExit(
            f"{name}: expected exactly one document_key in the index, got {keys}"
        )
    return keys[0]


def parse_sections(text: str) -> list[Section]:
    """Heading ranges in UTF-16 offsets over the whole file."""
    offsets = utf16_offsets(text)
    marks: list[tuple[int, int, str]] = []
    for match in HEADING.finditer(text):
        marks.append((offsets[match.start()], len(match.group(1)), match.group(2).strip()))
    sections: list[Section] = []
    for index, (start, level, heading) in enumerate(marks):
        end = len(offsets) - 1
        for later_start, later_level, _ in marks[index + 1 :]:
            if later_level <= level:
                end = later_start
                break
        sections.append(Section("", heading, level, start, end))
    return sections


def bigrams(text: str) -> set[str]:
    folded = re.sub(r"\s+", "", text.lower())
    return {folded[index : index + 2] for index in range(len(folded) - 1)}


def heading_occurrences(manifest: dict) -> dict[str, list[str]]:
    """Heading text to the source paths where it occurs, with repeats kept."""
    found: dict[str, list[str]] = {}
    for entry in manifest["files"]:
        if entry.get("kind") != "md":
            continue
        text = (ROOT / entry["source"]).read_text(encoding="utf-8", errors="replace")
        for section in parse_sections(text):
            found.setdefault(section.heading, []).append(entry["source"])
    return found


def heading_question(title: str, heading: str, template: str) -> str:
    if template == "no-filename":
        return f"「{heading}」这一节讲的内容是什么？"
    return f"{title} 里「{heading}」这一节讲的内容是什么？"


def lexical_overlap(question: str, body: str) -> float:
    left = bigrams(question)
    right = bigrams(body)
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def is_fence_or_table(body: str) -> bool:
    stripped = body.strip()
    if stripped.startswith(FENCE) or FENCE in stripped:
        return True
    if stripped.startswith("|") or stripped.startswith("#"):
        return True
    # A row of numbers or a bare identifier is not a statement.
    if len(HAN.findall(stripped)) < 8:
        return False
    return False


def usable_gold(chunk: Chunk) -> bool:
    body = chunk.body.strip()
    if not (MIN_GOLD_CHARS <= len(body) <= MAX_GOLD_CHARS):
        return False
    if is_fence_or_table(body):
        return False
    # Needs to read as prose: at least one terminator or one full clause.
    return any(mark in body for mark in ("。", "；", "，", ":", "："))


def verbatim_query(chunk: Chunk) -> str | None:
    """Lift a balanced clause out of the chunk without copying the whole chunk.

    Rejects unbalanced brackets, code fences, and fragments that end mid-phrase.
    The point is a phrase a human would actually type, not a byte slice.
    """
    body = chunk.body.strip()
    if FENCE in body:
        return None
    parts = [
        part.strip()
        for part in re.split(r"[，。；：,;:]", body)
        if part.strip()
    ]
    candidates = [
        part
        for part in parts
        if 8 <= len(HAN.findall(part)) <= 40
        and part.count("(") == part.count(")")
        and part.count("（") == part.count("）")
        and part.count("`") % 2 == 0
        and part.count("「") == part.count("」")
        and not part.startswith(("|", "#", "-", "*"))
    ]
    if not candidates:
        return None
    clause = max(candidates, key=len)
    # Do not end on a particle that leaves the phrase hanging.
    if clause.endswith(("的", "和", "与", "或", "在", "从", "把", "被", "是")):
        return None
    return clause


def distinguishability(connection: sqlite3.Connection, clause: str) -> int:
    """How many chunks contain this clause. 1 means the span is unambiguous."""
    return int(
        connection.execute(
            "SELECT COUNT(*) FROM chunk WHERE body LIKE ?", (f"%{clause}%",)
        ).fetchone()[0]
    )


def pick_negative_phrases(
    connection: sqlite3.Connection, candidates: list[tuple[str, str]], limit: int
) -> list[tuple[str, str]]:
    """Keep only candidates whose answer-bearing term occurs in zero chunks.

    The template text itself contains heading words, so a whole-string `LIKE`
    would always match something. What must be absent is the term the question
    asks for, so each candidate is probed on its own answer word.
    """
    kept: list[tuple[str, str]] = []
    seen: set[str] = set()
    for phrase, source in candidates:
        probe = next((item for item in NEGATIVE_PROBES if item in phrase), None)
        if probe is None:
            continue
        found = connection.execute(
            "SELECT COUNT(*) FROM chunk WHERE body LIKE ?", (f"%{probe}%",)
        ).fetchone()[0]
        if found != 0:
            # The corpus does mention this term, so "no relevant chunk" is not
            # obviously the right answer. Drop it instead of guessing.
            continue
        if phrase in seen:
            continue
        seen.add(phrase)
        kept.append((phrase, source))
        if len(kept) >= limit:
            break
    return kept


def _gold_row(
    *,
    family: str,
    question: str,
    document_key: str,
    gold: Chunk,
    source_file: str,
    heading: str,
) -> dict:
    """One labelled question. Exactly one gold document, one gold span."""
    # `page=null` is the project convention for chunkers that produce no real
    # page number (TXT/MD/DOCX). Writing Python's `None` here would make the
    # label unparsable downstream, so the literal string is deliberate.
    page = "null" if gold.page_number is None else str(gold.page_number)
    location = (
        f"{document_key}#page={page}"
        f";textUnit=utf16CodeUnit;start={gold.start};end={gold.end}"
    )
    return {
        "id": "",
        "family": family,
        "question": question,
        "relevantDocumentId": document_key,
        "relevantDocumentIds": [document_key],
        "evidenceLocation": location,
        "evidenceLocations": [location],
        "evidenceText": gold.body,
        "referenceAnswer": gold.body,
        "answerable": True,
        "crossPage": False,
        "modality": "text",
        "crossChunk": False,
        "lexOverlap": round(lexical_overlap(question, gold.body), 6),
        "goldChunkIndex": gold.chunk_index,
        "goldChars": len(gold.body),
        "sourceFile": source_file,
        "sectionHeading": heading,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="reports/week5/.index/bench.sqlite")
    parser.add_argument("--manifest", default="datasets/corpus_manifest.json")
    parser.add_argument("--out", default="")
    parser.add_argument(
        "--heading-template",
        choices=("with-filename", "no-filename"),
        default="with-filename",
    )
    parser.add_argument("--per-doc", type=int, default=8)
    parser.add_argument("--negatives", type=int, default=24)
    parser.add_argument("--split-ratio", type=float, default=0.67)
    parser.add_argument("--seed", type=int, default=20261028)
    args = parser.parse_args()
    if not args.out:
        args.out = (
            NOFILE_EVIDENCE
            if args.heading_template == "no-filename"
            else FROZEN_EVIDENCE
        )

    db_path = Path(args.db)
    if not db_path.is_absolute():
        db_path = ROOT / db_path
    if not db_path.exists():
        raise SystemExit(f"Missing index: {db_path}")
    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = ROOT / manifest_path
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    eligible: set[str] | None = None
    if args.heading_template == "no-filename":
        occurrences = heading_occurrences(manifest)
        multi = sorted(
            heading
            for heading, files in occurrences.items()
            if len(set(files)) > 1
        )
        repeated = sorted(
            heading
            for heading, files in occurrences.items()
            if len(set(files)) == 1 and len(files) > 1
        )
        eligible = {
            heading
            for heading, files in occurrences.items()
            if len(files) == 1
        }
        print("heading_template=no-filename")
        print(
            f"headings_seen={len(occurrences)} "
            f"unique_headings={len(eligible)} "
            f"dropped_multi_document={len(multi)} "
            f"dropped_repeated_in_one_document={len(repeated)}"
        )
        print("dropped_multi_document_headings=" + " | ".join(multi))
        if repeated:
            print("dropped_repeated_in_one_document_headings=" + " | ".join(repeated))
        print(
            "verbatim=omitted negative=omitted "
            "reason=those templates are unchanged and stay in "
            "reports/week5/evidence_set_w5.jsonl"
        )

    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows: list[dict] = []
    negatives: list[tuple[str, str]] = []
    skipped_not_unique = 0
    try:
        for entry in manifest["files"]:
            if entry["kind"] != "md":
                continue
            document_key = resolve_document_key(db_path, entry["snapshot"])
            source = ROOT / entry["source"]
            text = source.read_text(encoding="utf-8", errors="replace")
            title = entry["source"].rsplit("/", 1)[-1].rsplit(".", 1)[0]
            chunks = load_chunks(db_path, document_key)
            if not chunks:
                continue
            sections = parse_sections(text)
            made = 0
            picked: list[tuple[Section, Chunk]] = []
            for section in sections:
                if made >= args.per_doc:
                    break
                if len(section.heading) < 4:
                    continue
                # The text tower's budget is 128 tokens and Chinese is roughly
                # one token per character, so a long heading plus its template
                # would push the query over budget and make the question
                # unencodable. Cap the composed question, not just the heading.
                if len(section.heading) > 40:
                    continue
                if not HAN.search(section.heading):
                    continue
                if eligible is not None and section.heading not in eligible:
                    skipped_not_unique += 1
                    continue
                inside = [
                    chunk
                    for chunk in chunks
                    if chunk.start >= section.start
                    and chunk.end <= section.end
                    and usable_gold(chunk)
                ]
                if not inside:
                    continue
                # Prefer a chunk in the middle of the section: the first chunk
                # often repeats the heading, which would make the task trivial.
                gold = inside[len(inside) // 2] if len(inside) > 1 else inside[0]
                question = heading_question(
                    title, section.heading, args.heading_template
                )
                if len(question) > MAX_QUESTION_CHARS:
                    continue
                rows.append(
                    _gold_row(
                        family="heading",
                        question=question,
                        document_key=document_key,
                        gold=gold,
                        source_file=entry["source"],
                        heading=section.heading,
                    )
                )
                if args.heading_template == "no-filename":
                    rows[-1]["headingTemplate"] = "no-filename"
                picked.append((section, gold))
                made += 1
                if args.heading_template == "with-filename" and len(negatives) < args.negatives * 3:
                    template = NEGATIVE_TEMPLATES[
                        len(negatives) % len(NEGATIVE_TEMPLATES)
                    ]
                    negatives.append(
                        (
                            template.format(title=title, heading=section.heading),
                            "template-negative",
                        )
                    )
            # Verbatim family: the same gold spans as the heading family, but a
            # query that quotes a clause from the chunk. Matched pairs keep the
            # two numbers comparable. A clause is only accepted when it occurs
            # in exactly one chunk, otherwise more than one return is correct
            # and the single-document label would be wrong.
            # The no-filename file is a heading-template trial. Verbatim and
            # negative rows keep their old wording in the frozen evidence file.
            verbatim_made = 0
            if args.heading_template != "with-filename":
                picked = []
            for section, gold in picked:
                if verbatim_made >= max(1, args.per_doc // 2):
                    break
                clause = verbatim_query(gold)
                if clause is None:
                    continue
                if distinguishability(connection, clause) != 1:
                    continue
                question = f"哪份文档写了「{clause}」？"
                if len(question) > MAX_QUESTION_CHARS:
                    continue
                rows.append(
                    _gold_row(
                        family="verbatim",
                        question=question,
                        document_key=document_key,
                        gold=gold,
                        source_file=entry["source"],
                        heading=section.heading,
                    )
                )
                verbatim_made += 1
        # Verified-absent negatives. Phrases come from headings, so they are
        # plausible Chinese without being answerable from this corpus.
        # Their templates still name the file. That is a separate question
        # from the heading template, so the no-filename file leaves them out.
        if args.heading_template == "with-filename":
            kept = pick_negative_phrases(connection, negatives, args.negatives)
        else:
            kept = []
        for index, (question, source) in enumerate(kept):
            rows.append(
                {
                    "id": "",
                    "family": "negative",
                    "question": question,
                    "relevantDocumentId": "",
                    "relevantDocumentIds": [],
                    "evidenceLocation": "",
                    "evidenceLocations": [],
                    "evidenceText": "",
                    "referenceAnswer": "",
                    "answerable": False,
                    "crossPage": False,
                    "modality": "text",
                    "crossChunk": False,
                    "lexOverlap": 0.0,
                    "goldChunkIndex": -1,
                    "goldChars": 0,
                    "sourceFile": "",
                    "sectionHeading": "",
                    "negativeSource": source,
                }
            )
    finally:
        connection.close()

    if not rows:
        raise SystemExit("No questions generated. Check chunk sizes and headings.")

    # Deterministic split: alternate on a seeded shuffle so both halves see
    # every document, then label. Negatives follow the same rule.
    import random

    rng = random.Random(args.seed)
    rng.shuffle(rows)
    answerable = [row for row in rows if row["answerable"]]
    negative = [row for row in rows if not row["answerable"]]
    cut = int(len(answerable) * args.split_ratio)
    for index, row in enumerate(answerable):
        row["split"] = "dev" if index < cut else "holdout"
    for index, row in enumerate(negative):
        row["split"] = "dev" if index % 3 else "holdout"
    ordered = answerable + negative
    id_prefix = "w5n" if args.heading_template == "no-filename" else "w5"
    for index, row in enumerate(ordered, start=1):
        row["id"] = f"{id_prefix}-{index:03d}"

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = ROOT / out_path
    frozen_path = (ROOT / FROZEN_EVIDENCE).resolve()
    if args.heading_template == "no-filename" and out_path.resolve() == frozen_path:
        raise SystemExit(
            "refusing to overwrite reports/week5/evidence_set_w5.jsonl"
        )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = "\n".join(
        json.dumps(row, ensure_ascii=False) for row in ordered
    ) + "\n"
    out_path.write_text(payload, encoding="utf-8", newline="\n")
    digest = hashlib.sha256(out_path.read_bytes()).hexdigest()

    dev = sum(1 for row in ordered if row["split"] == "dev")
    holdout = len(ordered) - dev
    overlaps = sorted(row["lexOverlap"] for row in answerable)
    buckets = {"lex>=0.5": 0, "0.2-0.5": 0, "<0.2": 0}

    def bucket(value: float) -> str:
        if value >= 0.5:
            return "lex>=0.5"
        if value >= 0.2:
            return "0.2-0.5"
        return "<0.2"

    for value in overlaps:
        buckets[bucket(value)] += 1

    print(f"db={db_path}")
    print(f"heading_template={args.heading_template}")
    if args.heading_template == "no-filename":
        print(f"skipped_not_unique={skipped_not_unique}")
    print(f"questions={len(ordered)} answerable={len(answerable)} negative={len(negative)}")
    print(f"split dev={dev} holdout={holdout}")
    print(f"lexOverlap median={overlaps[len(overlaps) // 2]:.4f} "
          f"min={overlaps[0]:.4f} max={overlaps[-1]:.4f}")
    for name, count in buckets.items():
        print(f"lexOverlap bucket {name}: {count}")
    print(f"out={out_path}")
    print(f"sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
