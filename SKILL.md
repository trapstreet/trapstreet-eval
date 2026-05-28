---
name: trapstreet-eval
description: Closed-book model eval. Looks up a trapstreet task, fetches its case files (question + reference doc), hands each case to Claude (your current session) with NO tools and NO outside knowledge, runs the task's judge.py locally to score, then uploads the run to trapstreet.run via `tp submit`. Use when the user types `/trapstreet-eval [task-id]` (defaults to `financebench`), or asks to "run a trapstreet eval", "test Claude on financebench", "closed-book eval", and similar.
---

# Trapstreet eval — closed-book model eval

When the user invokes `/trapstreet-eval [task-id]`:

**Default**: `task-id = financebench` if the user didn't pass one.

This is a **closed-book** eval: for each case you get a question + a
reference doc (typically a 10-K excerpt or similar). You must answer
using **ONLY** the content of the reference doc. No web search, no tool
calls, no outside knowledge — even if you know the answer from training,
pretend you don't.

After grading, this skill **uploads the run** to trapstreet.run by
shelling out to the `tp` CLI (which the user already authenticated via
`tp auth login`). No bespoke HTTP from the skill — `tp submit` owns the
upload contract.

## Step 1 — Greet

One short block. Tell the user the task id you're running and that
you'll be evaluated closed-book. Example:

```
Trapstreet eval — task: financebench
Mode: closed-book (no tools, only the reference doc per case).
Fetching cases…
```

## Step 2 — Resolve the task on trapstreet.run

Use Bash to look up the task and derive the GitHub raw URL for its
files:

```bash
TASK_ID="${TASK_ID:-financebench}"
WORK=/tmp/trapstreet-eval
rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"

curl -fsSL "https://trapstreet.run/api/tasks/${TASK_ID}" > task.json

TRAPTASK_REF=$(python3 -c "import json,sys; print(json.load(open('task.json'))['task']['traptask_ref'])")
# traptask_ref is "owner/repo" or "owner/repo/sub/path" — split into the two pieces
OWNER_REPO=$(echo "$TRAPTASK_REF" | cut -d/ -f1-2)
SUBPATH=$(echo "$TRAPTASK_REF" | cut -d/ -f3-)
[ -n "$SUBPATH" ] && SUBPATH="/$SUBPATH"
GH_RAW_BASE="https://raw.githubusercontent.com/${OWNER_REPO}/main${SUBPATH}"

echo "task_id      = $TASK_ID"
echo "traptask_ref = $TRAPTASK_REF"
echo "raw base     = $GH_RAW_BASE"
```

If the curl fails, stop and tell the user the task id isn't on
trapstreet.run.

## Step 3 — Pull traptask.yaml + judge.py + the list of cases

```bash
curl -fsSL "$GH_RAW_BASE/traptask.yaml" -o traptask.yaml
curl -fsSL "$GH_RAW_BASE/judge.py" -o judge.py

# Extract case ids. Looks for lines like "  - id: foo_bar".
python3 - <<'PY' > cases.txt
import re, pathlib
text = pathlib.Path("traptask.yaml").read_text()
inside = False
for line in text.splitlines():
    if re.match(r"^cases:\s*$", line):
        inside = True
        continue
    if inside and re.match(r"^[A-Za-z_]", line):
        break
    m = re.match(r"^\s*-\s+id:\s*['\"]?([\w-]+)['\"]?\s*$", line)
    if m and inside:
        print(m.group(1))
PY

echo "cases to evaluate ($(wc -l < cases.txt | tr -d ' ')):"
cat cases.txt
```

## Step 4 — For each case: read → answer closed-book → grade

**Do this per case, sequentially**. For each `case_id` in `cases.txt`:

### 4a. Fetch the case's files

```bash
case_id="$1"
mkdir -p "$WORK/$case_id"
curl -fsSL "$GH_RAW_BASE/inputs/$case_id/question.txt" -o "$WORK/$case_id/question.txt"
curl -fsSL "$GH_RAW_BASE/inputs/$case_id/doc.txt"      -o "$WORK/$case_id/doc.txt"
curl -fsSL "$GH_RAW_BASE/expected/$case_id/answer.json" -o "$WORK/$case_id/answer.json"
```

(If `inputs/<case_id>/` contains files other than `question.txt` /
`doc.txt`, fetch those too. Inspect `$GH_RAW_BASE` via the GitHub
contents API if needed.)

### 4b. Read the two files yourself

Use the Read tool (or `cat`) on `$WORK/$case_id/question.txt` and
`$WORK/$case_id/doc.txt`. Read them **both fully**. Don't skim.

### 4c. Answer closed-book

Working from **only** the content of `doc.txt`:

- Compute / extract the answer to `question.txt`.
- Write **just the answer** (a number with appropriate units, or a
  short string) to `$WORK/$case_id/stdout`. **No reasoning. No
  preamble. No "The answer is …". Just the value.**

The judge picks the **first** number in the file, so any prose before
the number will throw off the match. Examples of acceptable formats:

- `5466`
- `5466.00`
- `$5466 million`
- `42.69`
- `-0.02`

Use Bash to write:

```bash
echo "<just the answer>" > "$WORK/$case_id/stdout"
```

### 4d. Run the judge

```bash
PAYLOAD=$(python3 -c "
import json, sys
case_id, work = sys.argv[1], sys.argv[2]
print(json.dumps({
  'inputs': {
    'question.txt': f'{work}/{case_id}/question.txt',
    'doc.txt':      f'{work}/{case_id}/doc.txt',
  },
  'outputs': {'stdout': f'{work}/{case_id}/stdout'},
  'expected': {'answer.json': f'{work}/{case_id}/answer.json'},
}))
" "$case_id" "$WORK")

TRAPTASK_PAYLOAD="$PAYLOAD" python3 judge.py | tee "$WORK/$case_id/metrics.json"
```

## Step 5 — Summary

After every case is graded:

```bash
python3 - <<'PY'
import json, pathlib
WORK = pathlib.Path("/tmp/trapstreet-eval")
ids = [l.strip() for l in (WORK / "cases.txt").read_text().splitlines() if l.strip()]
rows, correct = [], 0
for cid in ids:
    m = json.loads((WORK / cid / "metrics.json").read_text())
    rows.append((cid, m.get("correct"), m.get("agent_answer", "")[:30], m.get("expected_answer", "")))
    if m.get("correct"):
        correct += 1
print()
print(f"{'case':<40} {'ok':>4}  {'predicted':<30}  expected")
print("─" * 100)
for cid, ok, pred, exp in rows:
    mark = "✓" if ok else "✗"
    print(f"{cid:<40} {mark:>4}  {pred:<30}  {exp}")
print()
print(f"Score: {correct}/{len(ids)} = {100*correct/len(ids):.1f}%")
PY
```

## Step 6 — Build report.json and upload via `tp submit`

Build the standard trap wire-format report and hand it to the `tp` CLI.
`tp` reads `~/.config/trapstreet/auth.json` for the api_key (the user
already ran `tp auth login`), checks the public-repo rule, and POSTs.

The skill submits under a **different solution identity** than the user's
default `tp run` solution — closed-book in-session eval is a distinct
agent. Default name: `<existing-solution>-eval` (e.g. `zhuaiz-eval`).
Override via `TRAPSTREET_SOLUTION=my-name` in the user's shell before
invoking.

Important: do this **inside one Bash block** so the env vars carry
through. Bash calls from different SKILL steps don't share state.

```bash
# Auth + server URL from the stored login (tp auth login).
AUTH_FILE="$HOME/.config/trapstreet/auth.json"
if [ ! -f "$AUTH_FILE" ]; then
  echo "not logged in — run 'tp auth login' first"; exit 2
fi
API_KEY=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['api_key'])")
SERVER=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('server','https://trapstreet.run'))")

# Look up the caller's existing solution name so we can derive a
# distinct one for skill-driven runs.
EXISTING_SOLUTION=$(curl -fsSL -H "authorization: Bearer $API_KEY" "$SERVER/api/me" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['solution']['name'])")

# Solution name precedence: explicit TRAPSTREET_SOLUTION env > derived.
SOLUTION_NAME="${TRAPSTREET_SOLUTION:-${EXISTING_SOLUTION}-eval}"
MODEL="${CLAUDE_MODEL:-unknown}"

echo "engine          = claude-code-skill-${MODEL}"
echo "solution        = ${SOLUTION_NAME}"

# Build the report. Pass SOLUTION_NAME and MODEL through env explicitly
# so the python heredoc sees them.
SOLUTION_NAME="$SOLUTION_NAME" MODEL="$MODEL" python3 - <<'PY' > "$WORK/report.json"
import json, os, pathlib, datetime

WORK = pathlib.Path("/tmp/trapstreet-eval")
ids = [l.strip() for l in (WORK / "cases.txt").read_text().splitlines() if l.strip()]

cases = []
for cid in ids:
    metrics = json.loads((WORK / cid / "metrics.json").read_text())
    cases.append({
        "case_id": cid,
        "exit_code": 0,
        "duration": None,
        "metrics": metrics,
        "skipped": False,
    })

model = os.environ["MODEL"]
solution_name = os.environ["SOLUTION_NAME"]

# Source-of-truth repo for THIS skill (closed-book in-session executor).
# Lets the server's public-task rule pass and the leaderboard row link
# back to the skill source.
SKILL_REPO = "https://github.com/trapstreet/trapstreet-eval"

now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

with open(WORK / "task.json") as f:
    task_obj = json.load(f)
task_id = task_obj["task"]["id"]

report = {
    "task_id": task_id,
    # Top-level `solution` field — server's /api/submit/[task_id] reads
    # this and lookup-or-creates a solution under the authed user with
    # this name. Without it, server falls back to the api_key's default
    # solution (whatever `tp auth login` minted), which mixes skill runs
    # into your generic identity.
    "solution": solution_name,
    "cases": cases,
    "started_at": now,
    "finished_at": now,
    "metadata": {
        "engine": f"claude-code-skill-{model}",
        "repo": SKILL_REPO,
        "framework": "claude-code-skill",
        "strategy": "closed-book-in-session",
        "model": model,
    },
}
print(json.dumps(report, indent=2))
PY

echo "wrote report.json (solution=$SOLUTION_NAME):"
head -8 "$WORK/report.json"
```

Then submit. `tp submit --report` is the new flag (CLI ≥ 0.4.0) that
takes a hand-built report.json and skips the workspace lookup:

```bash
TASK_ID=$(python3 -c "import json; print(json.load(open('/tmp/trapstreet-eval/task.json'))['task']['id'])")
tp submit "$TASK_ID" --report "$WORK/report.json"
```

`tp` will print the leaderboard URL on success. If it errors:

- `not logged in` → tell the user to run `tp auth login`.
- `metadata.repo not publicly reachable` → the skill's source-repo URL
  isn't live yet; tell the user to wait or re-check the URL in this
  SKILL.md.
- Any other error → relay tp's message verbatim, don't paper over.

Then tell the user that's the local + uploaded result.

## What NOT to do

- ❌ Don't use web search, web fetch, or any tool other than reading
  the per-case files we already downloaded.
- ❌ Don't add explanations to the answer file. The judge picks the
  first number; prose breaks the match.
- ❌ Don't try to "be helpful" by correcting the gold answer — emit
  your honest reading of the doc and let the judge decide.
- ❌ Don't skip cases that look hard.
