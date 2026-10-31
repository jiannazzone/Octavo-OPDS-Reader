#!/usr/bin/env python3
"""Continuity table (Markdown) from fold-run.py output.

    summarize.py runs/*.jsonl

Verdict per move:
- back to closed: `exact` (start CFI equals the origin's), else `drift`.
- open / half: `contains` (the page contains the origin's start, by CFI
  order, and its first words), `contains (CFI only)` / `contains (text only)`
  when the two checks disagree, else `lost`.
A fold-gap failure (text touching the fold region while open) is flagged.
"""
import json
import sys


def verdict(step):
    if step["step"] == "origin":
        return "origin"
    if step.get("timedOut"):
        return "timed out"
    if step["posture"] == "closed":
        return "exact" if step["exact"] else "drift"
    if step["contains"] and step["words"]:
        return "contains"
    if step["contains"]:
        return "contains (CFI only)"
    if step["words"]:
        return "contains (text only)"
    return "lost"


def main(paths):
    rows, totals = [], {}
    for path in paths:
        steps = [json.loads(line) for line in open(path) if line.strip()]
        if not steps:
            continue
        origin = steps[0]
        rows.append(f"| **{origin['label']}** | {origin['book']} | origin | {origin['columns']} | `{origin['cfi']}` | {origin['first']} | origin | |")
        for step in steps[1:]:
            v = verdict(step)
            totals[v] = totals.get(v, 0) + 1
            gap = ""
            if step["posture"] in ("open", "halfOpen"):
                fold = step.get("fold")
                ok = step.get("crossing") == 0
                gap = (f"{'clear' if ok else 'TEXT ON FOLD'}: text to {step['leftPageRight']:.0f}, fold {fold[0]:.1f}–{fold[1]:.1f}, text from {step['rightPageLeft']:.0f}"
                       if fold and step.get("leftPageRight") is not None and step.get("rightPageLeft") is not None
                       else f"crossing {step.get('crossing')}")
                if not ok:
                    totals["text on fold"] = totals.get("text on fold", 0) + 1
            rows.append(f"| | | {step['step']} → {step['posture']} | {step['columns']} | `{step['cfi']}` | {step['first']} | {v} | {gap} |")
    print("| Run | Book | Move → posture | Cols | Start CFI | First words | Verdict | Fold gap (x, pt) |")
    print("|---|---|---|---|---|---|---|---|")
    print("\n".join(rows))
    print()
    print("Totals: " + ", ".join(f"{k} {v}" for k, v in sorted(totals.items())))


if __name__ == "__main__":
    main(sys.argv[1:])
