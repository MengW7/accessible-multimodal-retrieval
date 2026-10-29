"""Per-question failure classification for the retrieval arms.

`eval_retrieval.py` answers "how many". This script answers "why", one row per
(question, arm), with a fixed failure vocabulary so two weeks can be compared.

Read-only with respect to every existing artifact: it never edits the frozen
evidence set, the bench logs, or the reports. It only runs the product probe
again with a wider `--top` and writes its own new files.

    python engine/error_analysis.py --split dev
    python engine/error_analysis.py --split dev --db reports/week4/.index/docs.sqlite \
        --evidence reports/week4/evidence_set_w4.jsonl

Failure classes (one primary class per row, plus orthogonal flags):

    label_defect         the label carries no location at all
    modality_gap         no channel in this arm can return a chunk of the gold
                         space, so the arm is blind rather than wrong
    no_recall            gold document absent from every returned position
    ranked_low           gold document returned, first rank above the cut
    wrong_span_same_doc  gold document at rank <= cut, but no returned span
                         overlaps the evidence span
    span_ranked_low      a span overlaps, but first overlapping rank above cut
    hit                  overlap inside the cut

Orthogonal flags, computable without any model:

    free_label            the gold document set covers the whole space pool, so
                          a uniform random ranking already hits with p ~ 1
    keyword_bigram_dead   the query is Han text and `keyword_term` is empty, so
                          the bigram path returns nothing and only the English
                          gloss trigram probes survive
    clip_vocab_gap        the CLIP text tokenizer has no Han token and the query
                          contains Han, so the clipShared query vector comes
                          from a string that tower cannot encode
    empty_evidence_text   the label's evidence text is empty, so no span check
                          is possible for that question
    no_span_label         the label carries no offset span (file or metadata
                          only), so span_hit degrades to doc_hit
    printed_text_only     the label says the answer is printed on the image and
                          no parser produced body text
    channel_blocked       the frozen fusion weight makes it arithmetically
                          impossible for the image channel to reach the cut

Also writes the null baselines every reported number needs:

    chance_analytic       probability a uniform random draw of `--cut` chunks
                          from the question's own space contains a gold
                          document (closed form, doc-level labels)
    chance_shuffle_doc    this arm's own returned list, shuffled, mean Hit@cut
                          over `--draws` permutations (doc-level predicate)
    chance_shuffle_span   the same, with the span-overlap predicate
    p_*_vs_shuffle        Poisson-binomial upper tail for the arm total. Every
                          question has its own chance floor, so the arm total is
                          not binomial and a plain p-value would be wrong.

Metrics are reported twice on purpose. `doc_hit` is the week-4 report
convention (a returned file matches the gold file). `span_hit` additionally
requires the returned chunk to overlap the labelled offset, which is the
stronger claim the project actually makes ("能定位到原文哪一页哪一段").
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import re
import sqlite3
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEEK4 = ROOT / "reports" / "week4"
DEFAULT_DB = WEEK4 / ".index" / "evidence.sqlite"
DEFAULT_EVIDENCE = ROOT / "reports" / "week3" / "evidence_set.jsonl"
OUT_DIR = WEEK4 / "logs"

RRF_SOURCE = ROOT / "packages" / "core_retrieval" / "lib" / "src" / "rrf_fusion.dart"
CLIP_TOKENIZER = (
    ROOT / "models" / "raw" / "image" / "mobileclip-s0" / "tokenizer.json"
)

# The evidence set was frozen here. This script reads it, never writes it.
FROZEN_EVIDENCE = ROOT / "reports" / "week3" / "evidence_set.jsonl"

# Recorded in reports/week3/证据集说明.md, section 3. LF endings, file bytes.
FROZEN_EVIDENCE_SHA256 = (
    "82c080c0c91e29551d7e3ee4a67f4ae3e421d424a2b2fb5a5d8079b23e4eb9d6"
)

CLASSES = (
    "label_defect",
    "modality_gap",
    "no_recall",
    "ranked_low",
    "wrong_span_same_doc",
    "span_ranked_low",
    "hit",
    "hit_via_neighbor",
    "unanswerable",
)

# Which space a question is scored in. The frozen labels already say.
TEXT_MODALITIES = {"text", "metadata"}

# Channels that can physically return a chunk of each space. The keyword index
# covers text chunks only (`keyword_term` and `chunk_fts` are written from
# `body`), so a keyword-only arm still reaches text documents, and it can never
# reach an image row.
REACHES = {
    "documentText": {"documentText", "keyword"},
    "clipShared": {"clipShared"},
}

# Mirrors `_armByName` in packages/core_pipeline/bin/search_probe.dart.
ARM_CHANNELS = {
    "A0": {"keyword"},
    "A1": {"documentText"},
    "A2": {"clipShared"},
    "A3": {"documentText", "keyword"},
    "A4": {"documentText", "keyword", "clipShared"},
    "A5": {"documentText", "keyword", "clipShared"},
}

HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")

# Classes that count as a hit on the bridge metric. `hit_via_neighbor` is not
# the same claim as `hit`: the anchor chunk does not cover the gold span, but
# the returned snippet includes it because neighbourhood expansion concatenates
# `chunkIndex ± 1`. Reports must show both numbers.
HIT_CLASSES = ("hit", "hit_via_neighbor")


def _load_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if text:
            rows.append(json.loads(text))
    return rows


def _has_han(text: str) -> bool:
    return HAN.search(text) is not None


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


def _normalize(path: str) -> str:
    return path.replace("\\", "/").strip()


def _label_targets(label: dict) -> list[str]:
    targets = label.get("relevantDocumentIds") or [label["relevantDocumentId"]]
    return [_normalize(item) for item in targets]


def _parse_location(raw: str) -> dict:
    """One `evidenceLocations` entry, in whichever of the three shapes it has."""
    text = _normalize(raw)
    if "#" not in text:
        return {"kind": "file", "document": text}
    document, fragment = text.split("#", 1)
    if "start=" in fragment:
        spans = {}
        for part in fragment.split(";"):
            if "=" in part:
                key, value = part.split("=", 1)
                spans[key.strip()] = value.strip()
        start = spans.get("start")
        end = spans.get("end")
        page = spans.get("page")
        # `null`, `None`, and empty all mean "this parser produced no real page
        # number". TXT/MD/DOCX labels legitimately have no page.
        no_page = page is None or page == "" or page.lower() in ("null", "none")
        return {
            "kind": "span",
            "document": document,
            "page": None if no_page else int(page),
            "start": None if start is None else int(start),
            "end": None if end is None else int(end),
            "textUnit": spans.get("textUnit", ""),
        }
    return {"kind": "metadata", "document": document, "fragment": fragment}


def _doc_matches(hit: dict, targets: list[str]) -> bool:
    key = _normalize(str(hit.get("documentKey") or hit.get("relativePath") or ""))
    name = str(hit.get("fileName") or key.rsplit("/", 1)[-1])
    for target in targets:
        if key == target or target.endswith("/" + key) or target.endswith("/" + name):
            return True
    return False


def _span_overlaps(hit: dict, location: dict, tolerance: int) -> bool:
    """True when the returned chunk covers any part of the labelled span."""
    if location["kind"] != "span":
        return False
    if not _doc_matches(hit, [location["document"]]):
        return False
    if location.get("page") is not None:
        page = hit.get("pageNumber")
        if page is None or int(page) != int(location["page"]):
            return False
    start = location.get("start")
    end = location.get("end")
    if start is None or end is None:
        return False
    low = start - tolerance
    high = end + tolerance
    hit_start = int(hit.get("startOffset") or 0)
    hit_end = int(hit.get("endOffset") or 0)
    if hit_end <= hit_start:
        return False
    return hit_start < high and low < hit_end


def _span_reached_by_neighbor(
    hit: dict, location: dict, chunk_tolerance: int, gold: dict | None
) -> bool:
    """True when the hit is a neighbouring chunk of the gold chunk.

    The product returns a snippet that concatenates the anchor chunk with its
    `chunkIndex ± 1` neighbours (`neighborhood.dart`), so the evidence text is
    visible to the reader even when the anchor chunk itself is the neighbour.
    Judging only the anchor span understates what the user sees; judging the
    whole document overstates it. Both are reported, this is the middle one.
    """
    if chunk_tolerance <= 0 or gold is None or location["kind"] != "span":
        return False
    if not _doc_matches(hit, [location["document"]]):
        return False
    if location.get("page") is not None:
        page = hit.get("pageNumber")
        gold_page = gold.get("pageNumber")
        if page is None or gold_page is None or int(page) != int(gold_page):
            return False
    gold_index = gold.get("chunkIndex")
    hit_index = hit.get("chunkIndex")
    if gold_index is None or hit_index is None:
        return False
    return abs(int(hit_index) - int(gold_index)) <= chunk_tolerance


def _first_rank(hits: list[dict], predicate) -> int:
    for hit in hits:
        if predicate(hit):
            return int(hit["rank"])
    return 0


def _rrf_constants() -> tuple[int, float, float, float]:
    """Read the frozen k and the three weights from the retriever source."""
    if not RRF_SOURCE.exists():
        raise SystemExit(f"Missing retriever source: {RRF_SOURCE}")
    text = RRF_SOURCE.read_text(encoding="utf-8")

    def as_int(name: str) -> int:
        found = re.search(rf"const int {name} = (\d+);", text)
        if not found:
            raise SystemExit(f"Cannot read {name} from {RRF_SOURCE}")
        return int(found.group(1))

    def as_double(name: str) -> float:
        found = re.search(rf"const double {name} = ([\d.]+);", text)
        if not found:
            raise SystemExit(f"Cannot read {name} from {RRF_SOURCE}")
        return float(found.group(1))

    return (
        as_int("rrfK"),
        as_double("rrfTextWeight"),
        as_double("rrfKeywordWeight"),
        as_double("rrfImageWeight"),
    )


def _clip_han_tokens() -> int:
    if not CLIP_TOKENIZER.exists():
        return -1
    payload = json.loads(CLIP_TOKENIZER.read_text(encoding="utf-8"))
    vocabulary = payload.get("model", {}).get("vocab", {})
    return sum(1 for token in vocabulary if HAN.search(token) is not None)


def _corpus(db_path: Path) -> dict:
    """Space sizes and the keyword table state, straight from the index."""
    if not db_path.exists():
        raise SystemExit(f"Missing index: {db_path}")
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        by_space: dict[str, list[dict]] = {}
        for row in connection.execute(
            "SELECT space, document_key, page_number, start_offset, end_offset,"
            "       body, modality FROM chunk"
        ):
            space = str(row[0])
            by_space.setdefault(space, []).append(
                {
                    "documentKey": _normalize(str(row[1])),
                    "pageNumber": row[2],
                    "startOffset": int(row[3]),
                    "endOffset": int(row[4]),
                    "bodyLength": len(str(row[5] or "")),
                    "modality": str(row[6]),
                }
            )
        keywords = int(
            connection.execute("SELECT COUNT(*) FROM keyword_term").fetchone()[0]
        )
        fts = int(connection.execute("SELECT COUNT(*) FROM chunk_fts").fetchone()[0])
        bodies = int(
            connection.execute("SELECT COUNT(*) FROM chunk WHERE body <> ''").fetchone()[0]
        )
    finally:
        connection.close()
    return {"bySpace": by_space, "keywordTerms": keywords, "ftsRows": fts, "bodies": bodies}


def _run_probe(
    db_path: Path, evidence_path: Path, arms: str, split: str, top: int
) -> list[dict]:
    command = [
        "dart",
        "run",
        "packages/core_pipeline/bin/search_probe.dart",
        "--db",
        str(db_path),
        "--evidence",
        str(evidence_path),
        "--arms",
        arms,
        "--split",
        split,
        "--top",
        str(top),
        "--bench",
    ]
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
    if not rows:
        raise SystemExit("The probe returned no rows.")
    return rows


def _chance_analytic(pool: list[dict], targets: list[str], cut: int) -> float:
    """Uniform draw of `cut` chunks from the space, at least one gold document.

    Doc-level labels only: the label says which documents are relevant, so the
    relevant chunk count is every chunk of those documents.
    """
    total = len(pool)
    if total == 0:
        return 0.0
    relevant = sum(1 for chunk in pool if _doc_matches(chunk, targets))
    if relevant <= 0:
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


def _chance_shuffle(
    hits: list[dict], predicate, cut: int, draws: int, seed: int
) -> tuple[float, float]:
    """Shuffle this arm's own returned ordering and measure Hit@cut.

    Isolates "did the ranking carry signal" from "was the gold inside the
    candidate pool at all". Returns (mean, p_value) where p_value is the
    fraction of shuffles reaching or beating the observed Hit@cut.
    """
    if not hits:
        return 0.0, 1.0
    observed = 1 if _first_rank(hits, predicate) else 0
    order = list(range(len(hits)))
    rng = random.Random(seed)
    reached = 0
    total = 0
    for _ in range(draws):
        rng.shuffle(order)
        window = order[:cut]
        found = 1 if any(predicate(hits[index]) for index in window) else 0
        total += found
        if found >= observed:
            reached += 1
    return (total / draws), (reached / draws)


def _poisson_binomial_tail(probabilities: list[float], observed: int) -> float:
    """P(X >= observed) where X is a sum of independent Bernoulli(p_i).

    Each question under the null carries its own shuffle probability, so the
    arm total is not binomial. The exact distribution is Poisson-binomial; this
    computes the upper tail by dynamic programming, no normal approximation.
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


def _gold_chunk_index(corpus: dict, location: dict) -> dict | None:
    """Locate the chunk that exactly matches a labelled span offset."""
    if location.get("kind") != "span":
        return None
    space = "documentText"
    for chunk in corpus["bySpace"].get(space, []):
        if (
            _doc_matches(chunk, [location["document"]])
            and int(chunk["startOffset"]) == int(location["start"])
            and int(chunk["endOffset"]) == int(location["end"])
        ):
            return chunk
    return None


def _chunk_index_for_chunk(
    db_path: Path, document_key: str, start_offset: int
) -> int | None:
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        row = connection.execute(
            "SELECT chunk_index FROM chunk WHERE document_key = ?"
            " AND start_offset = ? AND space = 'documentText'",
            (document_key, start_offset),
        ).fetchone()
    finally:
        connection.close()
    return None if row is None else int(row[0])


def _classify(
    label: dict,
    arm: str,
    hits: list[dict],
    cut: int,
    tolerance: int,
    chunk_tolerance: int = 1,
) -> tuple[str, dict]:
    """Return (primary class, evidence dict describing the nearest miss)."""
    targets = _label_targets(label)
    locations = [
        _parse_location(item) for item in (label.get("evidenceLocations") or [])
    ]
    detail: dict = {
        "targets": targets,
        "labelLocations": len(locations),
        "spanLocations": sum(1 for item in locations if item["kind"] == "span"),
    }

    if label.get("parserExtractedText") is False:
        # The answer is printed on the image and no parser produced body text,
        # so a span check cannot succeed. Retrieval may still return the file,
        # which is what the week-4 doc-level number counted; keep both.
        detail["printedTextLabel"] = 1

    if label.get("answerable") is False:
        # A no-answer question has no gold span by construction, so it is not a
        # Hit@K question at all. Scored on its own axis and never averaged into
        # Hit@K.
        #
        # Important: the current retriever has **no score threshold**. A search
        # always returns `topK` rows, so the correct-abstain rate is 0 by
        # construction, not by measurement. This row records that fact plus the
        # top score actually produced, so a later threshold can be evaluated
        # against these numbers without re-running the corpus.
        top_score = max(
            (float(hit.get("score") or 0.0) for hit in hits), default=0.0
        )
        detail["topScore"] = round(top_score, 6)
        detail["returnedRows"] = len(hits)
        detail["retrieverHasThreshold"] = 0
        detail["correctAbstain"] = 0
        detail["hitAtCut"] = 0
        detail["docHitAtCut"] = 0
        detail["spanHitAtCut"] = 0
        return "unanswerable", detail

    # A label with no recoverable location cannot be satisfied by anyone.
    if not locations:
        detail["hitAtCut"] = 0
        detail["docHitAtCut"] = 0
        detail["spanHitAtCut"] = 0
        return "label_defect", detail

    space = "documentText" if label.get("modality") in TEXT_MODALITIES else "clipShared"
    channels = ARM_CHANNELS.get(arm)
    if channels is None:
        raise SystemExit(f"Unknown arm {arm}; add it to ARM_CHANNELS.")
    reachable = channels & REACHES[space]
    if not reachable:
        # No channel in this arm can return a chunk of the gold space at all.
        # Not a ranking failure: the arm is blind to this question.
        detail["hitAtCut"] = 0
        detail["neededChannel"] = ",".join(sorted(REACHES[space]))
        detail["armChannels"] = ",".join(sorted(channels))
        return "modality_gap", detail
    detail["channelsUsed"] = ",".join(sorted(reachable))

    doc_rank = _first_rank(hits, lambda hit: _doc_matches(hit, targets))
    detail["docRank"] = doc_rank
    if doc_rank == 0:
        detail["hitAtCut"] = 0
        detail["docHitAtCut"] = 0
        detail["spanHitAtCut"] = 0
        return "no_recall", detail
    detail["docHitAtCut"] = 1 if doc_rank <= cut else 0

    def spans(hit: dict) -> bool:
        return any(_span_overlaps(hit, item, tolerance) for item in locations)

    span_rank = _first_rank(hits, spans)
    detail["spanRank"] = span_rank

    if detail["spanLocations"] == 0:
        # Metadata-only or file-only labels carry no span, so the strongest
        # claim the label supports is the document rank. Recorded, not hidden.
        detail["hitAtCut"] = detail["docHitAtCut"]
        detail["spanHitAtCut"] = detail["docHitAtCut"]
        detail["neighborHitAtCut"] = detail["docHitAtCut"]
        return ("hit" if doc_rank <= cut else "ranked_low"), detail

    # Bridge hit: the anchor chunk is an immediate neighbour of the gold chunk.
    # The reader sees the evidence text in the returned snippet, but the anchor
    # offset does not cover it. This is the honest middle ground for a chunker
    # whose median chunk is 30 characters vs a 60-character evidence span.
    gold = label.get("_goldChunk")

    def neighbors(hit: dict) -> bool:
        return any(
            _span_reached_by_neighbor(hit, item, chunk_tolerance, gold)
            for item in locations
        )

    neighbor_rank = _first_rank(hits, lambda hit: spans(hit) or neighbors(hit))
    detail["neighborRank"] = neighbor_rank
    detail["spanHitAtCut"] = 1 if span_rank and span_rank <= cut else 0
    detail["neighborHitAtCut"] = 1 if neighbor_rank and neighbor_rank <= cut else 0
    detail["hitAtCut"] = detail["neighborHitAtCut"]
    if detail["spanHitAtCut"]:
        return "hit", detail
    if detail["neighborHitAtCut"]:
        return "hit_via_neighbor", detail
    if span_rank:
        return "span_ranked_low", detail
    if doc_rank <= cut:
        # A file hit without a span hit is only acceptable where the label says
        # the text is printed on an image. Everywhere else it is a real miss.
        if detail.get("printedTextLabel"):
            detail["hitAtCut"] = detail["docHitAtCut"]
            detail["spanHitAtCut"] = detail["docHitAtCut"]
            detail["neighborHitAtCut"] = detail["docHitAtCut"]
            return "hit", detail
        return "wrong_span_same_doc", detail
    return "ranked_low", detail


def _flags(
    label: dict,
    question: str,
    corpus: dict,
    cut: int,
    constants: tuple[int, float, float, float],
    han_tokens: int,
) -> list[str]:
    flags: list[str] = []
    targets = _label_targets(label)
    space = "documentText" if label.get("modality") in TEXT_MODALITIES else "clipShared"
    pool = corpus["bySpace"].get(space, [])
    if pool:
        relevant = sum(1 for chunk in pool if _doc_matches(chunk, targets))
        if relevant >= len(pool):
            flags.append("free_label")
    # The bigram path reads `keyword_term`. With 0 rows, a Han query returns
    # nothing from it and only survives through the English gloss trigram
    # probes, so the channel is much weaker than "keyword enabled" implies.
    if corpus["keywordTerms"] == 0 and _has_han(question):
        flags.append("keyword_bigram_dead")
    if 0 <= han_tokens == 0 and _has_han(question):
        flags.append("clip_vocab_gap")
    if (label.get("evidenceText") or "").strip() == "":
        flags.append("empty_evidence_text")
    spans = sum(
        1
        for item in (label.get("evidenceLocations") or [])
        if _parse_location(item)["kind"] == "span"
    )
    if spans == 0:
        # The label points at a file or a metadata field, so span_hit falls back
        # to doc_hit. Reported so span accuracy is never read as stronger than
        # the labels allow.
        flags.append("no_span_label")
    if label.get("parserExtractedText") is False:
        flags.append("printed_text_only")
    if label.get("modality") not in TEXT_MODALITIES and _channel_blocked(
        constants, "image", cut
    ):
        flags.append("channel_blocked")
    return flags


def _channel_blocked(
    constants: tuple[int, float, float, float], channel: str, cut: int
) -> bool:
    """Can this channel reach the cut at all, given the frozen weights?

    Best case for the channel is rank 1. Worst case for the competitor is its
    rank `cut`. If the channel's rank-1 score still loses to the competitor's
    rank-`cut` score, no ordering can put it inside the cut.
    """
    k, text_weight, keyword_weight, image_weight = constants
    channel_weight = {"image": image_weight, "keyword": keyword_weight}.get(channel, 0.0)
    if channel_weight <= 0:
        return True
    best = channel_weight / (k + 1)
    worst_text = text_weight / (k + cut)
    return best < worst_text


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _freeze_report(evidence_path: Path) -> tuple[str, int]:
    """Prove this run did not touch the frozen set, or that it did."""
    if not FROZEN_EVIDENCE.exists():
        return "missing", 0
    digest = _sha256(FROZEN_EVIDENCE)
    intact = 1 if digest == FROZEN_EVIDENCE_SHA256 else 0
    return digest, intact


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--split", default="dev", choices=("dev", "holdout", "all"))
    parser.add_argument("--db", default=str(DEFAULT_DB))
    parser.add_argument("--evidence", default=str(DEFAULT_EVIDENCE))
    parser.add_argument("--arms", default="A0,A1,A2,A3,A4,A5")
    parser.add_argument("--top", type=int, default=50)
    parser.add_argument("--cut", type=int, default=5)
    parser.add_argument("--tolerance", type=int, default=0)
    parser.add_argument(
        "--chunk-tolerance",
        type=int,
        default=1,
        help="chunkIndex distance counted as a bridge hit via neighbourhood expansion",
    )
    parser.add_argument("--draws", type=int, default=1000)
    parser.add_argument(
        "--keep-hits",
        type=int,
        default=10,
        help="how many ranked hits to keep per row in the jsonl payload",
    )
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.is_absolute():
        db_path = ROOT / db_path
    evidence_path = Path(args.evidence)
    if not evidence_path.is_absolute():
        evidence_path = ROOT / evidence_path

    labels = {row["id"]: row for row in _load_jsonl(evidence_path)}
    frozen = {row["id"]: row for row in _load_jsonl(FROZEN_EVIDENCE)}
    corpus = _corpus(db_path)
    constants = _rrf_constants()
    han_tokens = _clip_han_tokens()
    result_space_hint = "cut=%d top=%d tolerance=%d draws=%d" % (
        args.cut,
        args.top,
        args.tolerance,
        args.draws,
    )

    print("# error analysis")
    print(f"db={db_path}")
    print(f"evidence={evidence_path}")
    print(f"split={args.split} arms={args.arms} {result_space_hint}")
    print(f"frozen_evidence={FROZEN_EVIDENCE}")
    frozen_digest, frozen_intact = _freeze_report(evidence_path)
    print(f"frozen_evidence_sha256={frozen_digest}")
    print(f"frozen_evidence_intact={frozen_intact}")
    print(f"evidence_is_frozen_set={int(evidence_path.resolve() == FROZEN_EVIDENCE.resolve())}")
    print("class_vocabulary=" + ",".join(CLASSES))
    print(
        "rrf="
        f"k:{constants[0]},text:{constants[1]},keyword:{constants[2]},image:{constants[3]}"
    )
    print(f"clip_text_tokenizer_han_tokens={han_tokens}")
    for space, pool in sorted(corpus["bySpace"].items()):
        documents = sorted({chunk["documentKey"] for chunk in pool})
        print(f"space={space} chunks={len(pool)} documents={len(documents)}")
    print(f"keyword_term_rows={corpus['keywordTerms']}")
    print(f"chunk_fts_rows={corpus['ftsRows']}")
    print(f"chunk_with_body={corpus['bodies']}")

    k, text_weight, keyword_weight, image_weight = constants
    print(
        "image_can_enter_cut="
        f"{int(not _channel_blocked(constants, 'image', args.cut))} "
        f"why=image_rank1:{image_weight:.4f}/{k + 1} vs "
        f"text_rank{args.cut}:{text_weight:.4f}/{k + args.cut}"
    )
    print(
        "keyword_can_enter_cut="
        f"{int(not _channel_blocked(constants, 'keyword', args.cut))} "
        f"why=keyword_rank1:{keyword_weight:.4f}/{k + 1} vs "
        f"text_rank{args.cut}:{text_weight:.4f}/{k + args.cut}"
    )

    rows = _run_probe(db_path, evidence_path, args.arms, args.split, args.top)

    records: list[dict] = []
    for row in rows:
        question_id = str(row["id"])
        label = labels.get(question_id)
        if label is None:
            raise SystemExit(f"{question_id} is not in {evidence_path}")
        arm = str(row["arm"])
        hits = row.get("hits") or []
        locations = [
            _parse_location(item) for item in (label.get("evidenceLocations") or [])
        ]
        # The bridge metric needs the gold chunk's own chunkIndex and page, which
        # the label only carries as a span. Resolved from the index, not guessed.
        if locations:
            gold_chunk = _gold_chunk_index(corpus, locations[0])
            if gold_chunk is not None:
                label = dict(label)
                label["_goldChunk"] = {
                    "chunkIndex": _chunk_index_for_chunk(
                        db_path, gold_chunk["documentKey"], gold_chunk["startOffset"]
                    ),
                    "pageNumber": gold_chunk["pageNumber"],
                }
        primary, detail = _classify(
            label, arm, hits, args.cut, args.tolerance, args.chunk_tolerance
        )
        flags = _flags(label, str(row["question"]), corpus, args.cut, constants, han_tokens)
        space = (
            "documentText"
            if label.get("modality") in TEXT_MODALITIES
            else "clipShared"
        )
        pool = corpus["bySpace"].get(space, [])
        targets = _label_targets(label)
        # A no-answer question has no gold document, so every chance-floor and
        # null computation below is undefined for it. They are skipped rather
        # than filled with a zero, which would silently become a real number.
        answers = label.get("answerable") is not False
        if answers:
            analytic = _chance_analytic(pool, targets, args.cut)
            shuffle_mean, shuffle_p = _chance_shuffle(
                hits,
                lambda hit: _doc_matches(hit, targets),
                args.cut,
                args.draws,
                seed=zlib.crc32(f"{question_id}|{arm}".encode("utf-8")),
            )
            span_shuffle_mean, span_shuffle_p = _chance_shuffle(
                hits,
                lambda hit: any(
                    _span_overlaps(hit, item, args.tolerance) for item in locations
                )
                if detail.get("spanLocations", 0)
                else _doc_matches(hit, targets),
                args.cut,
                args.draws,
                seed=zlib.crc32(f"span|{question_id}|{arm}".encode("utf-8")),
            )
        else:
            analytic = shuffle_mean = shuffle_p = 0.0
            span_shuffle_mean = span_shuffle_p = 0.0
        records.append(
            {
                "id": question_id,
                "arm": arm,
                "split": str(row.get("split", args.split)),
                "question": str(row["question"]),
                "modality": label.get("modality"),
                "space": space,
                "class": primary,
                "flags": flags,
                "detail": detail,
                "answerable": answers,
                "hitAtCut": int(detail.get("hitAtCut", 0)),
                "docHitAtCut": int(detail.get("docHitAtCut", 0)),
                "spanHitAtCut": int(detail.get("spanHitAtCut", 0)),
                "neighborHitAtCut": int(detail.get("neighborHitAtCut", 0)),
                "chanceFloorAnalytic": round(analytic, 6),
                "chanceFloorShuffle": round(shuffle_mean, 6),
                "shufflePValue": round(shuffle_p, 6),
                "chanceFloorShuffleSpan": round(span_shuffle_mean, 6),
                "shuffleSpanPValue": round(span_shuffle_p, 6),
                "hits": [
                    {
                        "rank": int(hit["rank"]),
                        "documentKey": _normalize(str(hit.get("documentKey") or "")),
                        "pageNumber": hit.get("pageNumber"),
                        "startOffset": hit.get("startOffset"),
                        "endOffset": hit.get("endOffset"),
                        "score": round(float(hit.get("score") or 0.0), 6),
                        "channels": hit.get("channels") or [],
                        "modality": hit.get("modality"),
                    }
                    for hit in hits[: args.keep_hits]
                ],
            }
        )

    # ---- per-question rows ----
    print()
    print("# --- per question ---")
    for record in records:
        detail = record["detail"]
        doc_rank = detail.get("docRank", 0)
        span_rank = detail.get("spanRank", 0)
        print(
            f"{record['id']} arm={record['arm']} split={record['split']} "
            f"modality={record['modality']} class={record['class']} "
            f"doc_rank={doc_rank} span_rank={span_rank} "
            f"neighbor_rank={detail.get('neighborRank', 0)} "
            f"doc_hit@{args.cut}={record['docHitAtCut']} "
            f"span_hit@{args.cut}={record['spanHitAtCut']} "
            f"bridge_hit@{args.cut}={record['neighborHitAtCut']} "
            f"chance_analytic={record['chanceFloorAnalytic']:.6f} "
            f"chance_shuffle_doc={record['chanceFloorShuffle']:.6f} "
            f"chance_shuffle_span={record['chanceFloorShuffleSpan']:.6f} "
            f"flags={','.join(record['flags']) or '-'}"
        )

    # ---- per arm summary ----
    print()
    print("# --- per arm ---")
    print(
        "note=doc_hit is the week-4 report convention (file match); "
        "span_hit needs the returned chunk to overlap the labelled span; "
        "unanswerable questions are excluded from both denominators"
    )
    arms = sorted({record["arm"] for record in records})
    for arm in arms:
        everything = [record for record in records if record["arm"] == arm]
        # No-answer questions have no gold span, so including them would deflate
        # Hit@K with a failure mode Hit@K cannot express. Counted separately.
        subset = [r for r in everything if r["class"] != "unanswerable"]
        unanswerable = [r for r in everything if r["class"] == "unanswerable"]
        total = len(subset)
        if total == 0:
            continue
        doc_hits = sum(record["docHitAtCut"] for record in subset)
        span_hits = sum(record["spanHitAtCut"] for record in subset)
        bridge_hits = sum(record["neighborHitAtCut"] for record in subset)
        doc_p, doc_low, doc_high = _wilson(doc_hits, total)
        span_p, span_low, span_high = _wilson(span_hits, total)
        bridge_p, bridge_low, bridge_high = _wilson(bridge_hits, total)
        counts = {name: 0 for name in CLASSES}
        for record in subset:
            counts[record["class"]] += 1
        mean_analytic = sum(r["chanceFloorAnalytic"] for r in subset) / total
        mean_doc = sum(r["chanceFloorShuffle"] for r in subset) / total
        mean_span = sum(r["chanceFloorShuffleSpan"] for r in subset) / total
        # The null for the arm total is Poisson-binomial, not binomial: every
        # question has its own chance floor. Same for the shuffle variant.
        doc_null_p = _poisson_binomial_tail(
            [r["chanceFloorShuffle"] for r in subset], doc_hits
        )
        span_null_p = _poisson_binomial_tail(
            [r["chanceFloorShuffleSpan"] for r in subset], span_hits
        )
        analytic_null_p = _poisson_binomial_tail(
            [r["chanceFloorAnalytic"] for r in subset], doc_hits
        )
        print(
            f"arm={arm} n={total} "
            f"doc_hit@{args.cut}={doc_p:.6f} [{doc_low:.6f}, {doc_high:.6f}] "
            f"({doc_hits}/{total}) "
            f"span_hit@{args.cut}={span_p:.6f} [{span_low:.6f}, {span_high:.6f}] "
            f"({span_hits}/{total}) "
            f"bridge_hit@{args.cut}={bridge_p:.6f} "
            f"[{bridge_low:.6f}, {bridge_high:.6f}] ({bridge_hits}/{total}) "
            f"null_doc_chance={mean_analytic:.6f} "
            f"null_doc_shuffle={mean_doc:.6f} null_span_shuffle={mean_span:.6f} "
            f"p_doc_vs_chance={analytic_null_p:.4f} "
            f"p_doc_vs_shuffle={doc_null_p:.4f} "
            f"p_span_vs_shuffle={span_null_p:.4f}"
        )
        for name in CLASSES:
            if counts[name]:
                print(f"arm={arm} class={name} count={counts[name]}")
        flag_counts: dict[str, int] = {}
        for record in subset:
            for flag in record["flags"]:
                flag_counts[flag] = flag_counts.get(flag, 0) + 1
        for flag, count in sorted(flag_counts.items()):
            print(f"arm={arm} flag={flag} count={count}")
        if unanswerable:
            # Reported on its own axis. The retriever has no score threshold, so
            # every no-answer query still returns `topK` rows and the abstain
            # rate is 0 by construction. The top scores are printed so a future
            # threshold can be chosen from data instead of guessed.
            top_scores = sorted(
                (r["detail"].get("topScore", 0.0) for r in unanswerable),
                reverse=True,
            )
            abstain = sum(r["detail"].get("correctAbstain", 0) for r in unanswerable)
            print(
                f"arm={arm} unanswerable={len(unanswerable)} "
                f"correct_abstain={abstain} "
                f"retriever_has_threshold=0 "
                f"top_score_max={top_scores[0]:.6f} "
                f"top_score_median={top_scores[len(top_scores) // 2]:.6f} "
                f"top_score_min={top_scores[-1]:.6f}"
            )

    # ---- per-class, across arms ----
    print()
    print("# --- per class, all arms ---")
    for name in CLASSES:
        ids = [r["id"] for r in records if r["class"] == name]
        if ids:
            print(f"class={name} count={len(ids)} ids={','.join(sorted(set(ids)))}")

    out_stem = args.out or f"error_analysis_{args.split}"
    # Output goes beside the evidence set, not to a hardcoded week. A week-5 run
    # must not write into reports/week4/logs.
    out_dir = evidence_path.parent / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / f"{out_stem}.jsonl"
    with jsonl_path.open("w", encoding="utf-8", newline="\n") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    print()
    print(f"jsonl={jsonl_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
