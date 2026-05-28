# trapstreet-eval

Claude Code skill for closed-book model eval on trapstreet tasks.

`/trapstreet-eval [task-id]` → fetches case files from the task's repo
(question + reference doc), hands each case to Claude in the current
session with **no tools and no outside knowledge**, scores answers
locally via the task's `judge.py`, then uploads the run to
[trapstreet.run](https://trapstreet.run) via `tp submit`.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/trapstreet/trapstreet-eval/main/install.sh)
# or, from a local clone:
bash install.sh
```

That writes `SKILL.md` to `~/.claude/skills/trapstreet-eval/`. Claude
Code picks it up next session.

## Prerequisites

- `tp` CLI ≥ 0.4.0 — `uv tool install trapstreet-cli` and
  `tp auth login`.
- For the public-repo rule: nothing extra; this skill's source repo
  satisfies the requirement.

## Usage

```
/trapstreet-eval                  # defaults to task `financebench`
/trapstreet-eval mbti-profile     # any registered trapstreet task
```

Set `CLAUDE_MODEL=claude-sonnet-4-7` in your shell before invoking to
pin which Claude is being benchmarked — otherwise the leaderboard
engine column shows `claude-code-skill-unknown`.

## How it works

1. Calls `https://trapstreet.run/api/tasks/<task-id>` to resolve the
   task's GitHub repo (`traptask_ref`).
2. Pulls `traptask.yaml` + `judge.py` + per-case `inputs/` and
   `expected/` files from raw.githubusercontent.com.
3. For each case, reads the question + doc, computes the answer
   closed-book, writes the bare answer to stdout, runs `judge.py`
   locally.
4. Builds a standard trap `report.json` and calls
   `tp submit <task-id> --report <path>`.

See [SKILL.md](SKILL.md) for the full per-step prompt.
