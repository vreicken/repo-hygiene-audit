# What this audit cannot see (and how to read the report)

Read once, before trusting any line of a run report or verdicts file.

- Everything outside tracked files: untracked files present in the workdir
  are context, not findings — unless history shows they were ever committed
  (the `--diff-filter=A` facts decide that, not the file list).
- CI logs, issue bodies, release artifacts, fork states: their surface rows
  in the rubric's surface-binding table stay "unverified" unless the owner
  explicitly asks us to check them. Unverified is a row value, not a clean
  result.
- Obfuscated/novel patterns: the mechanical layer catches known shapes; the
  judgment layer catches human-definable context. What neither can define,
  neither finds. A passing audit does not mean the repo is **safe** — it
  means every rubric question got a deliberate answer on the files covered.
  A finding is not proof of malice either: finding ≠ hostile, clean ≠ safe.
- The repo's own scanner tuning: `.gitleaks.toml`, `.gitleaksignore` and
  `gitleaks:allow` comments are bypassed (default rules); their presence is
  a Needs Review row, since an allowlist can hide exactly what we look for.
- The future: an audit is a snapshot at a commit. When to re-run is owner's
  timing, not a warranty.
- Sweeps: a file "unchanged since last sweep" is verified by content hash in
  sweep-manifest, never trusted as a status. A "cleared" verdict whose file
  content changed is re-opened, not remembered.

## Status vocabulary (as the run reports use it)

- **OK** — check ran, result in the referenced file.
- **UNAVAILABLE** — tool or input missing (e.g. no denylist configured).
  Not-run and not-narrated: the row states the path/what-install-would-arm-it.
- **SKIPPED** — announced before, declined by the owner; explicitly never
  reported as a clean result.
- **GATED** — not run by default because the auditor would execute code
  from the audited repo; `RHA_ALLOW_REPO_EXEC=1` arms it. Coverage is
  UNVERIFIED, never clean.
- **FAILED** — ran and errored; whatever it would have covered is
  UNVERIFIED, not clean. (Dependency auditors don't use FAILED for
  "found things": dep-audit rows carry FINDINGS for that, and NONZERO-EXIT
  for the auditor-itself-broke case.)
- **UNVERIFIED** — derivable everywhere; means exactly "we didn't look".

## Value-blind rule

Leak findings are described by file, line, and pattern class — never by
quoting the matched content, even in reports written for the owner. The
report is part of the audited surface: if it names private hosts, ports,
machines, or absolute paths, it is itself a Q2/Q8 finding and belongs under
`.local/`, uncommitted.

## Existence-question disclaimer

Findings exist on a "what existence teaches a stranger" axis, not a
severity-of-harm axis. A section may read mundane and still be the biggest
information leak in the repo — that inversion is the point of the rubric.
