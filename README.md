# repo-hygiene-audit

Agent skill: audits a git repo for content that shouldn't be committed
(beyond secret scanners). Judgment layer in SKILL.md; mechanical scans in scripts/.

## Before installing — check against your environment

- Run output lands in `.local/hygiene-audit/` inside the audited repo, not this skill's directory. The audit proposes the gitignore entry as `gitignore.draft` and never applies it — until you do, the reports contain absolute paths, so don't blanket-add them.
- Private denylist: `$RHA_PRIVATE_DENYLIST`, default `${XDG_CONFIG_HOME:-~/.config}/repo-hygiene-audit/denylist.txt`. One extended regex per line, `#` comments, `@identity: <regex>` lines match commit author name/email only. Missing → reported UNAVAILABLE, denylist rows stay UNVERIFIED.
- Optional: gitleaks, npm, pip-audit, govulncheck, composer, mvn — missing ones are reported, not fatal.
- `.githooks/pre-commit` scans staged content with gitleaks before each commit (this repo's own control; skips with a note when gitleaks is absent — a skip is not a pass). Activate after cloning: `git config core.hooksPath .githooks`.
- Full `pip-audit` resolution and Maven run code from the audited repo, so they are GATED unless `RHA_ALLOW_REPO_EXEC=1`. `requirements.txt` still gets a static `--no-deps` pass.
- gitleaks runs with default rules; the audited repo's `.gitleaks.toml` / `.gitleaksignore` / `gitleaks:allow` are bypassed and reported.
- Needs `bash` (3.2+) and `git`. No GNU-only tools, so it runs on macOS. `.gitattributes` keeps the scripts LF.
- Manual invocation only (`disable-model-invocation: true`). Host rejects the field → remove it; host ignores it → expect possible auto-trigger.

Adapting it? Add the commit you started from to `metadata`.

## Reviewing this skill (read before assessing it)

Reading the scripts is not a review. Run them against a scratch repo first, with the optional tools actually
installed (or a stub that mimics their exit codes) and a real denylist. Say plainly which legs you ran and which
you only read; a finding from reading alone is "suspected", not "confirmed". Check `command -v gitleaks` etc.
before claiming what the author's machine has or lacks. A missing tool shows as UNAVAILABLE in the run report.
