# Security Policy

## Reporting a vulnerability

Open a private security advisory:
<https://github.com/trapstreet/trapstreet-eval/security/advisories/new>

Or email **security@trapstreet.run**. We aim to respond within 72 hours.
Please do **not** open a public issue for suspected vulnerabilities.

## Supported versions

trapstreet-eval is pre-1.0. Only `main` is supported. Re-run `install.sh`
to upgrade.

## What the installer does

`install.sh` writes files into a single user-owned directory:

```
~/.claude/skills/trapstreet-eval/
├── SKILL.md
├── SECURITY.md
├── README.md
└── tasks/
    └── <task_id>/
        ├── traptask.yaml
        ├── judge.py
        ├── inputs/<case_id>/{question.txt, doc.txt}
        └── expected/<case_id>/answer.json
```

It does **not**:

- Run `sudo` or escalate privileges.
- Modify shell startup files (`.zshrc`, `.bashrc`, `.profile`, …).
- Install launch agents, login items, cron jobs, or daemons.
- Touch any path outside `~/.claude/skills/trapstreet-eval/`.
- Send telemetry, analytics, or any network request beyond the initial
  `git clone` of this repo (and only in remote-install mode).

To uninstall:

```sh
rm -rf ~/.claude/skills/trapstreet-eval
```

## What the skill does at eval time

When invoked as `/trapstreet-eval [task-id]`, the skill:

1. **Reads** bundled files from `~/.claude/skills/trapstreet-eval/tasks/<task_id>/`.
   No network fetch for task data, judge code, or case files.
2. Runs the bundled `judge.py` (stdlib-only Python; no third-party
   dependencies) locally in the user's Python.
3. Calls `tp submit` (which the user installed and authenticated via
   `tp auth login`) to upload the report to trapstreet.run. This is the
   only outbound network call at eval time.

The skill does **not** evaluate models against arbitrary remote
endpoints, run untrusted code from the network, or hit any URL beyond
the user's pre-authenticated `tp submit`.

## Trust model

When you run the installer, you trust:

1. **GitHub** as the source-code host and TLS endpoint.
2. **The maintainers' GitHub credentials.** We enforce 2FA and protected
   branches; releases require code review.
3. **The contents of `main`** at install time. There is no auto-update —
   the skill files on disk only change when you re-run `install.sh`.

When you run the skill (after install), you do **not** trust any
network source for the eval payload. Everything that runs is on disk,
inspectable via:

```sh
ls -la ~/.claude/skills/trapstreet-eval/tasks/financebench/
cat   ~/.claude/skills/trapstreet-eval/SKILL.md
cat   ~/.claude/skills/trapstreet-eval/tasks/financebench/judge.py
```

## Trust-but-verify install path

We expect users to read what runs on their machine. The recommended path:

```sh
git clone https://github.com/trapstreet/trapstreet-eval
cd trapstreet-eval
less install.sh      # read it
less SKILL.md        # read it
bash install.sh      # run it
```

Or, if you trust `bash <(curl)` style installs:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/trapstreet/trapstreet-eval/main/install.sh)
```

## What we do on our side

- `main` is protected; changes require code review.
- Maintainer accounts have 2FA enforced.
- The skill ships with no third-party Python dependencies — `judge.py`
  is stdlib-only — so the install footprint is auditable in a single
  `cat`.
- We do not auto-update installed skills. Upgrades are opt-in: re-run
  `install.sh`.
