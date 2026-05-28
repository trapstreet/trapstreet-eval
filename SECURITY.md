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

`install.sh` writes one file to a single user-owned directory:

```
~/.claude/skills/trapstreet-eval/
└── SKILL.md
```

In local mode it copies the sibling `SKILL.md` from the checkout. In
remote mode (`bash <(curl)`) it downloads `SKILL.md` from
`raw.githubusercontent.com/trapstreet/trapstreet-eval/main`.

It does **not**:

- Run `sudo` or escalate privileges.
- Modify shell startup files (`.zshrc`, `.bashrc`, `.profile`, …).
- Install launch agents, login items, cron jobs, or daemons.
- Touch any path outside `~/.claude/skills/trapstreet-eval/`.
- Send telemetry or analytics.

To uninstall:

```sh
rm -rf ~/.claude/skills/trapstreet-eval
```

## What the skill does at eval time

When invoked as `/trapstreet-eval [task-id]`, the skill (via Claude's
Bash tool, with the user's approval at each step) fetches:

1. `https://trapstreet.run/api/tasks/<task-id>` — task metadata, which
   contains the source repo (`traptask_ref`) on GitHub.
2. `raw.githubusercontent.com/<traptask_ref>/...` — the task's
   `traptask.yaml`, `judge.py`, and per-case `inputs/` + `expected/`
   files.
3. `judge.py` runs locally in the user's Python to score each case.
4. `tp submit` uploads the final report to trapstreet.run (the user
   already authenticated this CLI via `tp auth login`).

The skill does **not** evaluate models against arbitrary remote
endpoints. The only code that runs locally is the task's `judge.py`,
fetched from the public GitHub repo referenced by the trapstreet.run
task entry — the same code anyone running `tp run` against that task
would execute.

## Trust model

When you run the installer, you trust:

1. **GitHub** as the source-code host and TLS endpoint.
2. **The maintainers' GitHub credentials.** We enforce 2FA and protected
   branches; changes to `main` require code review.

When you run the skill, you additionally trust:

3. **trapstreet.run** to return a non-malicious `traptask_ref` for the
   task id you pass.
4. **The task's source repo on GitHub** (whatever `traptask_ref` points
   at) to host a non-malicious `judge.py`. Read it before running an
   unfamiliar task:
   ```sh
   cat /tmp/trapstreet-eval/judge.py   # after Step 3 in SKILL.md
   ```

## Trust-but-verify install path

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
- We do not auto-update installed skills. Upgrades are opt-in: re-run
  `install.sh`.
