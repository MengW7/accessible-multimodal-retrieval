"""Summarize and verify W06 D4 evidence using only the Python standard library."""

import argparse
import hashlib
import json
import math
from pathlib import Path


def digest(file):
    with file.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def snapshot(work):
    root = work / "fixtures"
    files = {
        file.relative_to(root).as_posix(): digest(file)
        for file in sorted(root.rglob("*"))
        if file.is_file()
    }
    assert len(files) == 9907
    groups = {}
    for size in (98, 1000, 5000, 10000):
        members = {
            name: sha for name, sha in files.items()
            if ("/" not in name and (size > 98 or name != "broken.docx"))
            or ("/" in name and int(Path(name).stem) < size - 98)
        }
        manifest = "\n".join(f"{name}\t{members[name]}" for name in sorted(members))
        groups[size] = {
            "files": len(members),
            "sha256": hashlib.sha256(manifest.encode()).hexdigest(),
        }
    return groups


def percentile(samples, expected=30):
    assert len(samples) == expected
    data = sorted(samples)
    return {
        "p50Ms": data[math.ceil(expected * 0.50) - 1],
        "p95Ms": data[math.ceil(expected * 0.95) - 1],
        "n": expected,
    }


def monitor(report, tag):
    data = json.loads((report / f"D4_{tag}.json.monitor.json").read_text(encoding="utf-8-sig"))
    assert data["status"] == 0 and data["memory"]
    assert data["peakWorkingSetBytes"] == max(row[1] for row in data["memory"])
    assert not data["childPidsStillRunning"]
    return {k: v for k, v in data.items() if k not in ("memory", "columns")}


def summarize(root):
    def load(tag):
        data = json.loads((root / f"D4_{tag}.json").read_text(encoding="utf-8-sig"))
        assert data["ok"], tag
        return data

    growth, before, after, lifecycle = map(load, ("growth", "before", "after", "lifecycle"))
    assert [x["size"] for x in growth["growth"]] == [1000, 5000, 10000]
    assert lifecycle["cleared"]
    assert before["query"] == after["query"] == "离线检索"
    reference = before["cold"][0]["sources"]
    assert len(reference) == 5
    for run in (before, after):
        assert len(run["cold"]) == 5
        assert all(item["sources"] == reference for item in run["cold"])
    assert before["ties"]["sources"] == after["ties"]["sources"]
    assert len(before["ties"]["sources"]) == 50

    def extract_hot(a, b):
        assert a["sources"] == b["sources"] and len(a["sources"]) == 5
        assert a["vector"]["sources"] == b["vector"]["sources"]
        return {
            key: {
                "pipeline": {field: percentile([x[field] for x in run["samples"]])
                             for field in ("totalMs", "encodeMs", "storeMs", "fuseMs")},
                "scan": percentile(run["vector"]["ms"]),
                "rssBytesAfterHot": run["rssBytes"],
            }
            for key, run in (("before", a), ("after", b))
        }

    cold = {}
    for label, run in (("before", before), ("after", after)):
        entries = run["cold"]
        model_keys = entries[0]["loadMs"].keys()
        assert len(model_keys) == 3
        cold[label] = {
            **{name: percentile([x[name] for x in entries], 5)
               for name in ("openMs", "indexMs", "firstSearchMs")},
            "loads": {name: percentile([x["loadMs"][name] for x in entries], 5)
                      for name in model_keys},
            "forward": {name: percentile(times) for name, times in entries[-1]["forwardMs"].items()},
        }
        assert set(cold[label]["forward"]) == set(model_keys)
    warm = {"98": {"all": extract_hot(before["cold"][-1]["hot"]["all"],
                                      after["cold"][-1]["hot"]["all"])}}
    for size in ("1000", "5000", "10000"):
        warm[size] = {key: extract_hot(before["scales"][size][key], after["scales"][size][key])
                      for key in ("all", "a/")}
    return {
        "topKExactParity": True,
        "growth": growth["growth"],
        "cold": cold,
        "hot": warm,
        "ties": {label: percentile(data["ties"]["ms"])
                 for label, data in (("before", before), ("after", after))},
        "process": {tag: monitor(root, tag) for tag in ("growth", "before", "after", "lifecycle")},
        "dartPeakRssBytes": {tag: data["peakRssBytes"] for tag, data in
                            (("growth", growth), ("before", before), ("after", after),
                             ("lifecycle", lifecycle))},
        "lifecycle": {k: lifecycle[k] for k in ("cancel", "resume", "restored", "cleared")},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["snapshot", "summary"])
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = snapshot(args.source) if args.mode == "snapshot" else summarize(args.source)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
