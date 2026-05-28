# trapstreet-eval

Claude Code skill for closed-book model eval on trapstreet tasks.

`/trapstreet-eval [task-id]` → loads a **bundled** task from this skill
(question + reference doc + judge per case), hands each case to Claude
in the current session with **no tools and no outside knowledge**,
scores answers locally via the bundled `judge.py`, then uploads the
run to [trapstreet.run](https://trapstreet.run) via `tp submit`.

The skill is **self-contained**: every byte it needs to run the eval is
checked into this repo and copied to disk at install time. There is no
runtime fetch of task data — the only outbound call at eval time is
the final `tp submit` upload. See [SECURITY.md](SECURITY.md).

## Install

```bash
# Remote install (shallow git clones this repo, copies into ~/.claude/skills/):
bash <(curl -fsSL https://raw.githubusercontent.com/trapstreet/trapstreet-eval/main/install.sh)

# Or from a local clone:
git clone https://github.com/trapstreet/trapstreet-eval
cd trapstreet-eval
bash install.sh
```

That writes SKILL.md, SECURITY.md, README.md, and the entire `tasks/`
tree to `~/.claude/skills/trapstreet-eval/`. Claude Code picks up the
skill next session.

## Prerequisites

- `tp` CLI ≥ 0.4.0 — `uv tool install trapstreet-cli` and `tp auth login`.

## Usage

```
/trapstreet-eval                  # defaults to bundled task `financebench`
/trapstreet-eval <task-id>        # any task bundled under tasks/
```

Set `CLAUDE_MODEL=claude-sonnet-4-7` in your shell before invoking to
pin which Claude is being benchmarked — otherwise the leaderboard
engine column shows `claude-code-skill-unknown`.

Set `TRAPSTREET_SOLUTION=my-name` to override the leaderboard solution
identity. Default is `<your-existing-solution>-eval`.

## Layout

```
trapstreet-eval/
├── SKILL.md            # the Claude Code skill instructions
├── SECURITY.md         # what install.sh + the skill do/don't do
├── README.md
├── install.sh          # local + remote install logic
└── tasks/
    └── financebench/   # one bundled task
        ├── traptask.yaml
        ├── judge.py    # stdlib-only Python scorer
        ├── inputs/<case_id>/{question.txt, doc.txt}
        └── expected/<case_id>/answer.json
```

## How it works

1. Validates that `~/.claude/skills/trapstreet-eval/tasks/<task-id>/`
   exists. If not, lists what is bundled and stops.
2. Extracts case ids from the bundled `traptask.yaml`.
3. For each case: reads the bundled question + doc, asks Claude to
   answer using only the doc, writes the bare answer to stdout, runs
   the bundled `judge.py`.
4. Builds a standard trap `report.json` and calls
   `tp submit <task-id> --report <path>`.

## Adding a new task to the bundle

```bash
mkdir -p tasks/<task-id>/{inputs,expected}
# Drop in traptask.yaml, judge.py, and per-case inputs/<id>/ + expected/<id>/.
# Then re-run install.sh on every user that needs it.
```

Tasks are added in this repo by PR, not at the user's runtime. That's
deliberate — the eval is reproducible because the task definition is
pinned at install time, not at run time.
