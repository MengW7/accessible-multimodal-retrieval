"""Freeze a Tier-0 corpus snapshot from the repository's Markdown.

Why a snapshot instead of indexing the live tree: a benchmark corpus has to be
stable. `reports/` changes every week, so indexing it live means last week's
numbers cannot be reproduced. This script copies the selected Markdown into
`datasets/corpus_t0/` with flattened names, records a sha256 per file, and
writes `datasets/corpus_manifest.json`.

What it does NOT do: no download, no PDF generation, no question generation.
Those are Tier 2 / `build_bench.py`. Run this, then index, then build questions.

    python engine/build_corpus.py
    python engine/build_corpus.py --dry-run

Scope note: Tier 0 is repository documentation, so every question derived from
it is self-referential. The manifest marks that, and any report built on this
corpus must say so. It is still the right first step: the point of Tier 0 is to
move the pool from 96 chunks to several thousand so the chance floor stops
saturating, not to claim external validity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "datasets" / "corpus_t0"
MANIFEST = ROOT / "datasets" / "corpus_manifest.json"

# Included: durable documentation with a stable subject.
#   docs/ packages/ apps/   architecture, API, design records
#   reports/week1..week3    historical week reports. Their numbers are already
#                           superseded and they state no week-5 result, so they
#                           cannot leak an answer to a question about this
#                           corpus. `reports/week4` is excluded below because it
#                           quotes the frozen 25-question results verbatim.
INCLUDE_ROOTS = (
    "docs",
    "packages",
    "apps",
    "reports/week1",
    "reports/week2",
    "reports/week3",
)

# Extensions copied into the snapshot. `.pdf` exercises the real Tika path and
# gives the corpus至少 one multi-page document with real page numbers.
INCLUDE_SUFFIXES = (".md", ".pdf")

# Files whose content states the results of the benchmark that will run against
# this corpus, or that would inflate it with near-duplicates and broken files.
# (pattern, reason) so the manifest says why each file is out.
EXCLUDE_PATTERNS = (
    # States the frozen 25-question results and the arm table.
    ("retrieval-module-api.md", "states results under test"),
    ("storage-module-api.md", "states results under test"),
    ("reports/week4/", "states results under test"),
    # The week report PDFs are rendered from the same Markdown that is already
    # in the snapshot. Keeping them adds near-duplicate chunks, which inflates
    # every similarity score and makes the benchmark easier for no reason.
    ("reports/week1/week1_report.pdf", "duplicate of a markdown already included"),
    ("reports/week2/week2_report.pdf", "duplicate of a markdown already included"),
    ("reports/week3/W03_report.pdf", "duplicate of a markdown already included"),
    # Parser fixtures: one is truncated on purpose, one is zero bytes.
    ("packages/core_parsing/test/fixtures/", "deliberately broken fixture"),
)

# A PDF smaller than this is a fixture or a stub, not a document.
MIN_PDF_BYTES = 4096

# Below this many characters a file contributes almost nothing and mostly adds
# navigation boilerplate.
MIN_CHARS = 800


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _flat_name(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    return relative.replace("/", "__")


def _collect() -> tuple[list[Path], list[dict]]:
    """Return (selected files, skipped files with the reason)."""
    selected: list[Path] = []
    skipped: list[dict] = []
    for root_name in INCLUDE_ROOTS:
        root = ROOT / root_name
        if not root.exists():
            skipped.append({"path": root_name, "reason": "root missing"})
            continue
        candidates = [
            path
            for path in sorted(root.rglob("*"))
            if path.is_file() and path.suffix.lower() in INCLUDE_SUFFIXES
        ]
        for path in candidates:
            relative = path.relative_to(ROOT).as_posix()
            excluded = [
                reason
                for pattern, reason in EXCLUDE_PATTERNS
                if pattern in relative
            ]
            if excluded:
                skipped.append({"path": relative, "reason": excluded[0]})
                continue
            if path.suffix.lower() == ".md":
                text = path.read_text(encoding="utf-8", errors="replace")
                size = len(text)
            else:
                size = path.stat().st_size
                if size < MIN_PDF_BYTES:
                    skipped.append(
                        {
                            "path": relative,
                            "reason": f"pdf too small ({size} < {MIN_PDF_BYTES} bytes)",
                        }
                    )
                    continue
            if path.suffix.lower() == ".md" and size < MIN_CHARS:
                skipped.append(
                    {"path": relative, "reason": f"too short ({size} < {MIN_CHARS})"}
                )
                continue
            selected.append(path)
    return selected, skipped


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--clean", action="store_true", help="wipe corpus_t0 first")
    args = parser.parse_args()

    selected, skipped = _collect()
    if not selected:
        print("No Markdown selected. Nothing to do.", file=sys.stderr)
        return 1

    total_chars = 0
    entries = []
    for path in selected:
        if path.suffix.lower() == ".md":
            text = path.read_text(encoding="utf-8", errors="replace")
            chars = len(text)
            lines = text.count("\n") + 1
        else:
            chars = path.stat().st_size
            lines = 0
        total_chars += chars
        entries.append(
            {
                "source": path.relative_to(ROOT).as_posix(),
                "snapshot": f"datasets/corpus_t0/{_flat_name(path)}",
                "sha256": _sha256(path),
                "chars": chars,
                "lines": lines,
                "kind": path.suffix.lower().lstrip("."),
            }
        )

    manifest = {
        "tier": "t0",
        "description": "Repository Markdown snapshot, flattened names, frozen for benchmark reuse.",
        "self_referential": True,
        "limitation": (
            "Every document describes this project. Questions derived from it are "
            "self-referential and must be reported separately from any external corpus."
        ),
        "include_roots": list(INCLUDE_ROOTS),
        "include_suffixes": list(INCLUDE_SUFFIXES),
        "excluded_patterns": [
            {"pattern": pattern, "reason": reason}
            for pattern, reason in EXCLUDE_PATTERNS
        ],
        "min_chars": MIN_CHARS,
        "files": entries,
        "skipped": skipped,
        "totals": {
            "files": len(entries),
            "chars": total_chars,
        },
    }

    print(f"selected={len(entries)} skipped={len(skipped)} chars={total_chars}")
    for entry in entries:
        print(f"  {entry['chars']:>7}  {entry['source']}")
    if skipped:
        print("skipped:")
        for item in skipped:
            print(f"  {item['reason']:<28} {item['path']}")

    if args.dry_run:
        print("\ndry-run: nothing written.")
        return 0

    if args.clean and CORPUS.exists():
        shutil.rmtree(CORPUS)
    CORPUS.mkdir(parents=True, exist_ok=True)
    for path, entry in zip(selected, entries, strict=True):
        target = ROOT / entry["snapshot"]
        if not target.exists() or _sha256(target) != entry["sha256"]:
            shutil.copyfile(path, target)
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print()
    print(f"corpus_dir={CORPUS}")
    print(f"manifest={MANIFEST}")
    print()
    print("next:")
    print(
        "  dart run packages/core_pipeline/bin/index_probe.dart "
        "--path datasets/corpus_t0 --prefix corpus_t0 "
        "--db reports/week5/.index/bench.sqlite"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
