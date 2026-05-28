---
name: trapstreet-eval
description: Closed-book model eval. Runs a bundled trapstreet task (default `financebench`) against Claude in the current session with NO tools and NO outside knowledge — every question, reference doc, and judge.py is shipped inside this skill bundle, no network fetch at eval time. After grading, uploads the run to trapstreet.run via `tp submit`. Use when the user types `/trapstreet-eval [task-id]`, or asks to "run a trapstreet eval", "test Claude on financebench", "closed-book eval", and similar.
---

# Trapstreet eval — closed-book model eval

When the user invokes `/trapstreet-eval [task-id]`:

**Default**: `task-id = financebench` if the user didn't pass one.

This is a **closed-book** eval: for each case you get a question + a
reference doc (typically a 10-K excerpt or similar). You must answer
using **ONLY** the content of the reference doc. No web search, no tool
calls, no outside knowledge — even if you know the answer from training,
pretend you don't.

**All eval data is bundled inside this skill** —
`~/.claude/skills/trapstreet-eval/tasks/<task-id>/`. No `curl` from
github at eval time. The only network call is the final `tp submit`
upload to trapstreet.run.

After grading, this skill **uploads the run** by shelling out to the
`tp` CLI (which the user already authenticated via `tp auth login`). No
bespoke HTTP from the skill — `tp submit` owns the upload contract.

## Step 1 — Greet

One short block. Tell the user the task id you're running and that
you'll be evaluated closed-book. Example:

```
Trapstreet eval — task: financebench
Mode: closed-book (no tools, only the bundled reference doc per case).
Loading cases from ~/.claude/skills/trapstreet-eval/tasks/financebench/…
```

## Step 2 — Locate the bundled task

Use Bash to set up the workspace and validate the task exists in the
bundle:

```bash
TASK_ID="${TASK_ID:-financebench}"
SKILL_DIR="$HOME/.claude/skills/trapstreet-eval"
TASK_DIR="$SKILL_DIR/tasks/$TASK_ID"
WORK=/tmp/trapstreet-eval
rm -rf "$WORK" && mkdir -p "$WORK"

if [ ! -d "$TASK_DIR" ]; then
  echo "task '$TASK_ID' is not bundled in this skill."
  echo "available tasks:"
  ls "$SKILL_DIR/tasks/" 2>/dev/null || echo "  (none — skill install is broken)"
  exit 1
fi

echo "task_id      = $TASK_ID"
echo "task_dir     = $TASK_DIR"
echo "work_dir     = $WORK"
```

If the directory check fails, stop and tell the user the task id isn't
bundled. (Adding a new task = drop a new directory under `tasks/`,
re-run `install.sh`. It's not the skill's job to discover tasks at
runtime.)

## Step 3 — Extract the case list from the bundled traptask.yaml

```bash
# Same case-id extractor as before, but reads from disk instead of curl.
python3 - <<PY > "$WORK/cases.txt"
import re, pathlib
text = pathlib.Path("$TASK_DIR/traptask.yaml").read_text()
inside = False
for line in text.splitlines():
    if re.match(r"^cases:\s*$", line):
        inside = True
        continue
    if inside and re.match(r"^[A-Za-z_]", line):
        break
    m = re.match(r"^\s*-\s+id:\s*['\"]?([\w-]+)['\"]?\s*\$", line)
    if m and inside:
        print(m.group(1))
PY

echo "cases to evaluate ($(wc -l < "$WORK/cases.txt" | tr -d ' ')):"
cat "$WORK/cases.txt"
```

## Step 4 — For each case: read → answer closed-book → grade

**Do this per case, sequentially**. For each `case_id` in
`$WORK/cases.txt`:

### 4a. Read the case files (they're already on disk — no fetch)

The bundle layout mirrors the task's source repo exactly:

```
$TASK_DIR/
├── traptask.yaml
├── judge.py
├── inputs/<case_id>/{question.txt, doc.txt}
└── expected/<case_id>/answer.json
```

Use the Read tool on `$TASK_DIR/inputs/<case_id>/question.txt` and
`$TASK_DIR/inputs/<case_id>/doc.txt`. Read them **both fully**. Don't
skim.

(If `inputs/<case_id>/` contains files other than `question.txt` /
`doc.txt`, read those too.)

### 4b. Answer closed-book

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
mkdir -p "$WORK/$case_id"
echo "<just the answer>" > "$WORK/$case_id/stdout"
```

### 4c. Run the judge

```bash
PAYLOAD=$(python3 -c "
import json, sys
case_id, task_dir, work = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
  'inputs': {
    'question.txt': f'{task_dir}/inputs/{case_id}/question.txt',
    'doc.txt':      f'{task_dir}/inputs/{case_id}/doc.txt',
  },
  'outputs': {'stdout': f'{work}/{case_id}/stdout'},
  'expected': {'answer.json': f'{task_dir}/expected/{case_id}/answer.json'},
}))
" "$case_id" "$TASK_DIR" "$WORK")

TRAPTASK_PAYLOAD="$PAYLOAD" python3 "$TASK_DIR/judge.py" \
  | tee "$WORK/$case_id/metrics.json"
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
# TASK_ID was set in Step 2; carry it forward here for the report.
TASK_ID="${TASK_ID:-financebench}"

echo "engine          = claude-code-skill-${MODEL}"
echo "solution        = ${SOLUTION_NAME}"
echo "task_id         = ${TASK_ID}"

# Build the report. Pass everything the heredoc needs through env explicitly
# so the python heredoc sees them.
SOLUTION_NAME="$SOLUTION_NAME" MODEL="$MODEL" TASK_ID="$TASK_ID" \
python3 - <<'PY' > /tmp/trapstreet-eval/report.json
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
task_id = os.environ["TASK_ID"]

# Source-of-truth repo for THIS skill (closed-book in-session executor).
# Lets the server's public-task rule pass and the leaderboard row link
# back to the skill source.
SKILL_REPO = "https://github.com/trapstreet/trapstreet-eval"

now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

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
head -8 /tmp/trapstreet-eval/report.json

tp submit "$TASK_ID" --report /tmp/trapstreet-eval/report.json
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
  the bundled case files. They're already on disk under
  `~/.claude/skills/trapstreet-eval/tasks/<task_id>/`.
- ❌ Don't `curl` task data from github at runtime. If a task isn't in
  the bundle, fail clean and ask the user to update the skill —
  silently going to the network breaks reproducibility.
- ❌ Don't add explanations to the answer file. The judge picks the
  first number; prose breaks the match.
- ❌ Don't try to "be helpful" by correcting the gold answer — emit
  your honest reading of the doc and let the judge decide.
- ❌ Don't skip cases that look hard.
