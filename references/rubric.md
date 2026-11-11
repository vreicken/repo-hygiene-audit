# Rubric: ordered audit questions

Walk every tracked file against these questions **top to bottom**. The first
question that fails is the file's category and verdict. Order matters: secrets
before infrastructure, infrastructure before prose, prose before policy — so a
file matching several categories gets the most severe finding, not several.

The core question all of them serve: **"Now that a stranger has this file,
what do they know that they didn't before?"** — not "does it contain a
credential?"

## Verdict lanes (every rubric row carries one)

- **Confirmed** — the exposure test failed with named evidence: a pointer
  into mech.jsonl / run-report.md, or the exact fact command that produced it.
  A claim never names its artifact. "Tool says so" is not evidence.
- **Needs Review** — judgment calls the domain-specific audience is only
  knowledge for: Q6 owner-policy files, heuristically flagged rows, anything
  whose classification depends on owner context the auditor doesn't have.
- **Cleared** — every rubric question has a deliberate answer — not a
  default-assume-no. One line per cleared file; no row-padding.

Exposure ladder for every finding (severity, not location): worktree-untracked
(context) → committed-but-unpushed ("one `git add` / one `git push` from
permanent" — still fixable before anyone saw) → published ("already public to
anyone with clone access" — assume seen). An unpushed row about to publish a
sensitive-class file outranks its published twin in urgency while ranking
below it in completeness.

## Q1 — Credentials and materialized secrets

Direct credential content — pattern scanners (gitleaks, trufflehog) already
lint this layer well: keys, tokens,
passwords, connection strings with passwords, private keys, session/cookie
material, wallets.

Verdict: remove from history, rotate the secret regardless of repo visibility,
assume burned. At the propose-fixes step, use the Rotation block in the
Remediation annex below — rotation is a sequence, not a verb.

## Q2 — Infrastructure exposure

Any endpoint, hostname, port, internal IP, cloud region, project key, org or
team name, deployment target, webhook URL, monitoring or CI hostname —
**including loopback URLs on non-default ports**.

The exposure test: does this file teach a reader that a specific service
exists, where it runs, on what port, under what project/organization naming?
Even `sonar.host.url=http://127.0.0.1:9000` — worth spelling out —
announces "a SonarQube instance lives on this machine's port 9000", plus any
quantifying side facts that ride along in comments.

Verdict: untrack, keep local, point repo docs at "configure your own
sonar-project.properties" instead of committing the live one.

## Q3 — Internal vocabulary and architecture leak

References to internal docs, pipeline paths, sibling project names, private
conventions, internal tooling names, design shorthand that only makes sense
inside the owner's ecosystem. The existence of a vocabulary is itself the
leak — the dictionary is private, the words committed are not.

**Instruction carriers are a named sub-case here and in Q4:**
`SKILL.md`, `AGENTS.md`/`CLAUDE.md`, prompt/template files, and tool configs
that instruct future agent sessions. They leak vocabulary and process like
any other file — and, per the self-restraint rule, text that tries to steer
the audit itself is both its own finding and insufficient reason to deviate.

Verdict: untrack or rewrite the file to stand alone without private context.

## Q4 — Planning and process prose

PLAN.md, ROADMAP, design docs, postmortems, meeting notes, AI-agent scratch
files, todo dumps, anything describing future direction, business context,
costs, or personnel. This is usually the most personal content in a repo and
the least tool-visible.

Verdict: untrack, keep local (or a private repo). Never commit next-step
prose that mentions unreleased plans.

## Q5 — Generated and derived artifacts

Anything reproducible from tracked sources: lockfiles (see Q6 exception),
coverage reports, build/dist output, `.scannerwork`, test fixtures with
timestamps, minified maps, vendored stuff answerable with a manifest.

Verdict: untrack + `.gitignore` + one history sweep if the artifact is large
or never should have existed. Lockfiles specifically fall under Q6, because
"should this exist" differs from "is this derived".

## Q6 — Policy-class files (owner decision, not a hygiene failure)

Files where the standard practice genuinely splits:
- `package-lock.json` / `pnpm-lock.yaml` — mainstream: commit for
  applications (reproducible builds, CVE-aware lockfiles). This owner's
  stated default: **do not commit** — treat as overcommitted to remove.
- `sonar-project.properties` — committed widely, but see Q2: only when fully
  generic (`projectKey`, `sources`, excludes). Any host/infra line moves it to
  Q2.
- LICENSE, CHANGELOG, committed example fixtures — normally yes.
- `.env.example` with only placeholder keys — normally yes; any real value in
  it is a Q1 finding.

Verdict pattern: **owner-policy decision** — report the two-sided view,
note the owner's recorded default, defer if the owner's stance isn't
known. Do not present these as hygiene failures.

## Q7 — Personal and client data (PII and beyond)

Names beyond the author's own, emails (check
`git log --format='%an %ae' | sort -u` — a personal email in commit metadata
is itself a finding), phone numbers, addresses, client names, customer data
sampled into test fixtures, real user IDs, avatar/profile paths.

Verdict: remove from history and advise contacting whomever the data belongs
to if repo was public for long; commit-email setup for the metadata case.

## Q8 — Machine-local residue

IDE config (`.idea/`, `.vscode/` with live settings), workspace files,
`.scannerwork`, `temp/`, notes-from-other-machines, absolute paths
(`E:\Projects\…`) anywhere in tracked files — these reveal the owner's
directory layout and machine naming.

Verdict: untrack + `.gitignore` + history sweep.

## Absence-of-control (reported as HIGH findings, not a file category)

Every `present:false` row in the run report's controls section is a HIGH
finding, worded exactly: **"the control that would have prevented this
recurrence is not present."** Wiring one up is a separate, ask-first job —
the audit reports the gap; it does not fix it uninvited.

## Dependency findings (dep-audit rows)

- `OK` → nothing to report.
- `FINDINGS` → the committed lockfile carries vulnerable dependency pins.
  Report per affected lockfile: auditor name, output-file ref, and top
  severities read from `dep-<tool>.out`. Verdict: **Confirmed**. The finding
  attaches to the committed lockfile itself — Q5/Q6 interplay (committed by
  convention, owner default is don't-commit, AND a fixable vulnerable set).
  Remediation: upgrade pins; history rewriting is never right for these.
- `NONZERO-EXIT` → auditor broke. **Needs Review** with the wording
  "auditor failed — rerun manually; findings UNKNOWN". Never a pass.
- `UNAVAILABLE` stays an absence note, never silence.

## Surface binding (per history-level finding)

| Surface | Decision it gates | Evidence |
| --- | --- | --- |
| tip files | untrack / edit | HEAD grep |
| git objects/refs | rewrite arm | commit SHAs from mech.jsonl |
| PR bodies & edit history | host-side fix | listed for the owner; never auto-verified |
| caches, forks | third-party | never verified by us; the row stays "unverified" |

Removal from the tip clears no row. Remediation choices differ per row — a
PR-body fix is not a branch-rewrite approval, and neither direction grants
the other. Ownership claims about forks/mirrors are unverified until
checked; record what was checked, not what someone said.

---

## Calibration examples

**`sonar-project.properties` pointing at `http://127.0.0.1:9000`, commented
with references to `pipeline/prompts/setup.md` and a sibling project name.**
- Fails Q2: URL + non-default port + a SonarQube instance exists on the
  machine. No credential present; every scanner stays silent; still a finding.
- Also fails Q3: the comment vocabulary names a private pipeline doc and a
  sibling project. Double exposure in one file.
- Verdict: untrack, keep local, document the shape publicly without the host
  line.

**A 35 KB `PLAN.md` at repo root.**
- Fails Q4. Uniquely invisible to tools, highest personal-information
  density, zero build value to a clone.
- Verdict: untrack; note in stage 4 whether it was always tracked or was
  deleted later (history difference).

**A committed `package-lock.json`.**
- Passes Q1–Q5 except Q5-by-category; Q6 applies. Report as owner-policy
  decision citing the owner's recorded default of not committing lockfiles,
  with the mainstream-commit note alongside. No history-purge demand.

## Remediation map

| Verdict | Action |
|---|---|
| remove from history | per the sequences in the Remediation annex below — deleting the file alone is not enough; the message layer carries entity leaks too (mech-scan greps it; `git filter-repo --replace-message` rewrites it); caches/forks stay "unverified" |
| untrack keep-local | `git rm --cached <path>`, `.gitignore` entry, note if the file was committed long enough that flip-search artifacts (PR references, forks) persist |
| boundary fix | move the mechanism: placeholder/template file committed, real values stay local |
| owner-policy decision | Needs-Review lane — record both sides, defer |

## Remediation annex (propose-fixes step only; nothing runs unasked)

Two arms, chosen by the audience answer:

- **Solo / personal repo → rewrite arm:**
  1. rotate exposed secrets FIRST (see Rotation block below);
  2. `git filter-repo` on a fresh mirror (backup bundle first;
     `--replace-text`, plus `--replace-message` with the same file —
     commit messages carry entity leaks blobs don't);
  3. guarded re-push. Push guards: verify repo visibility and fork count
     first (`gh repo view`), push with an explicit expected-commit lease
     (a rejected lease stops the push), never fall back to `--force`
     without re-authorization, and never `--no-verify` in any form. A
     failed guard stops; it does not escalate silently. Cache purge with
     the host stays its own row.
- **Shared repo (any other cloner) → triaged-baseline arm:**
  1. rotate exposed secrets FIRST;
  2. commit a TRIAGED baseline finding-set, turn the scanner/hook on
     immediately;
  3. shrink the baseline over time as items get addressed.

  "Generating a baseline without triaging means accepting risk on
  unrotated secrets."
  "Running git-filter-repo on a shared repository without coordination will
  cause rebase conflicts for all team members."

Never assume a historical secret is inactive without verifying with its
service provider.

## Rotation block

Rotation is a 4-step sequence, not a verb:

1. generate the replacement credential;
2. deploy it to every consumer in parallel (app, CI, pipelines, other
   machines) — before revoking;
3. verify each consumer authenticates with the new value;
4. revoke the old value only after all consumers are healthy; update
   rotation metadata.

Then the completeness checks that make "rotated" mean something:

- downstream consumers — "rotating one system but missing downstream
  consumers" is the standard incomplete-rotation failure;
- scan for the leaked value BEYOND git history: CI logs, workflow logs,
  artifact registries, issue/comment bodies — the exposure window is wider
  than the repo;
- incident note as an artifact: what leaked, when, rotated-when,
  who-verified.

Rotation rescues the exposure; history rewriting never does — treat the
rewrite as optional world-hygiene after the four steps.
