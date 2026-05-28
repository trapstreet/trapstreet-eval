#!/usr/bin/env python3
"""FinanceBench per-case judge — runs once per case in trap's judge protocol.

Reads:
  - the agent's captured stdout (the model's answer to this case's question)
  - the case's gold answer from expected/answer.json

Compares with 1% relative tolerance for numerics; falls back to exact / substring
string match. Adapted from the original `grade.py` in the trapstreet-eval-demo
skill (https://github.com/AntiNoise-ai/trapstreet-eval-demo).

Outputs a JSON object to stdout that trap stores as the case's `metrics`.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

REL_TOL = 0.01

# Numeric-magnitude suffix table — handles "1.2 billion", "$1.2B", "12K", etc.
SCALE = [
    ("trillion", 1e12), ("trillions", 1e12), ("tn", 1e12), ("t", 1e12),
    ("billion", 1e9),  ("billions", 1e9),  ("bn", 1e9),  ("b", 1e9),
    ("million", 1e6),  ("millions", 1e6),  ("mn", 1e6),  ("mm", 1e6), ("m", 1e6),
    ("thousand", 1e3), ("thousands", 1e3), ("k", 1e3),
]

NUMBER_RE = re.compile(r"\(?-?\$?\s*[\d,]+(?:\.\d+)?\)?")


def parse_number(text: str) -> float | None:
    """Extract the first number-like token from `text`. Handles $, commas,
    accounting parentheses for negatives, % suffix, and magnitude suffixes.
    Returns None if no number found."""
    if not text:
        return None
    s = text.strip().lower()
    is_pct = "%" in s or " percent" in s
    m = NUMBER_RE.search(s)
    if not m:
        return None
    raw, sign = m.group(0), 1
    if raw.startswith("(") and raw.endswith(")"):
        raw, sign = raw[1:-1], -1
    raw = raw.replace("$", "").replace(",", "").replace(" ", "").strip()
    try:
        value = float(raw) * sign
    except ValueError:
        return None
    tail = s[m.end():].lstrip()
    for unit, mult in SCALE:
        if re.match(rf"\b{unit}\b", tail):
            value *= mult
            break
    if is_pct:
        value /= 100.0
    return value


def numeric_close(a: float, b: float) -> bool:
    if a == b:
        return True
    if a == 0 or b == 0:
        return abs(a - b) < 1e-9
    return abs(a - b) / max(abs(a), abs(b)) <= REL_TOL


def normalize_string(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower()).strip(".!?,;:")


def score_one(pred: str, gold: str) -> tuple[float, str]:
    """Return (score in {0.0, 1.0}, human-readable reason)."""
    if not pred.strip():
        return 0.0, "empty prediction"

    p_num = parse_number(pred)
    g_num = parse_number(gold)
    if p_num is not None and g_num is not None:
        if numeric_close(p_num, g_num):
            return 1.0, f"numeric match (pred={p_num:.6g} gold={g_num:.6g})"
        return 0.0, f"numeric mismatch (pred={p_num:.6g} gold={g_num:.6g})"

    if normalize_string(pred) == normalize_string(gold):
        return 1.0, "string exact match"
    if len(gold) <= 40 and normalize_string(gold) in normalize_string(pred):
        return 1.0, "substring match"
    return 0.0, f"string mismatch (pred={pred[:80]!r} gold={gold[:80]!r})"


def main() -> int:
    payload: dict[str, Any] = json.loads(os.environ["TRAPTASK_PAYLOAD"])

    # Solver writes its answer to stdout; trap captures into `outputs.stdout`.
    pred_path = payload.get("outputs", {}).get("stdout")
    pred = Path(pred_path).read_text() if pred_path else ""

    gold_path = payload["expected"]["answer.json"]
    gold_obj = json.loads(Path(gold_path).read_text())
    gold = gold_obj["gold"]

    s, reason = score_one(pred, gold)
    print(json.dumps({
        "score": s,
        "correct": s == 1.0,
        # Truncate at 500 chars so we don't store entire LLM monologues.
        "agent_answer": pred.strip()[:500],
        "expected_answer": gold,
        "reason": reason,
        "company": gold_obj.get("company"),
        "doc": gold_obj.get("doc"),
        "financebench_id": gold_obj.get("financebench_id"),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
