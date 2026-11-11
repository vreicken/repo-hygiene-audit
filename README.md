# repo-hygiene-audit

Agent skill: audits a git repo for content that shouldn't be committed
(beyond secret scanners). Judgment layer in SKILL.md; mechanical scans in scripts/.

## Before installing — check against your environment

- Run output lands in `.local/hygiene-audit/` inside the audited repo, not this skill's directory. The audit proposes the gitignore entry as `gitignore.draft` and never applies it — until you do, the reports contain absolute paths, so don't blanket-add them.
- Private denylist: `$RHA_PRIVATE_DENYLIST`, default `~/.pi/rha-private/denylist.txt`. Missing → reported UNAVAILABLE, denylist rows stay UNVERIFIED.
- Optional: gitleaks, npm, pip-audit, govulncheck, composer, mvn — missing ones are reported, not fatal.
- Needs `bash`, `git`; scripts must stay LF.
- Manual invocation only (`disable-model-invocation: true`). Host rejects the field → remove it; host ignores it → expect possible auto-trigger.

Adapting it? Add the commit you started from to `metadata`.
