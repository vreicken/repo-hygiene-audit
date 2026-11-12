#!/usr/bin/env bash
# dep-audit.sh — dependency/lockfile leg.
# usage: dep-audit.sh <run-dir> [target-repo]   (run AFTER mech-scan.sh; appends to its mech.jsonl)
# Auditors keyed off the manifests FOUND. A manifest whose auditor is not
# installed produces an UNAVAILABLE row — never silence, never "assumed ok".
# Auditors that would EXECUTE code from the audited repo (pip install of its
# requirements/build backend, Maven plugins/extensions) are GATED: they run
# only with RHA_ALLOW_REPO_EXEC=1, otherwise they leave a GATED row.
set -u
. "$(dirname "$0")/_common.sh"
RUNDIR="${1:-}"; TARGET="${2:-.}"
[ -d "$RUNDIR" ] || { echo "pass a mech-scan run dir as \$1 (it holds mech.jsonl)" >&2; exit 2; }
ROOT=$(repo_root "$TARGET") || ROOT=""
[ -n "$ROOT" ] || { echo "not a git repo: $TARGET" >&2; exit 2; }
cd "$ROOT" || exit 2
JSONL="$RUNDIR/mech.jsonl"; REPORT="$RUNDIR/run-report.md"
EXEC="${RHA_ALLOW_REPO_EXEC:-0}"
row(){ printf '%s\n' "$1" >> "$JSONL"; }
rr() { printf '%s\n' "$1" >> "$REPORT"; }

rr ""
rr "## dep-audit (auditors keyed off manifests found)"
run(){ local n="$1"; shift
  rc=0
  eval "$* > \"$RUNDIR/dep-$n.out\"" 2>&1 || rc=$?
  case "$rc" in
    0)
      row "{\"tool\":\"$n\",\"status\":\"OK\",\"output\":\"dep-$n.out\"}"
      rr "$n ................................ OK (dep-$n.out)";;
    *)
      # auditors exit non-zero both when they FIND things (the useful row) and
      # when they break. Distinguish findings-shaped from error-shaped output;
      # unclassifiable lands in Needs Review (rubric).
      if grep -qiE '"vulnerab|"metadata"|CVE|advisory' "$RUNDIR/dep-$n.out" 2>/dev/null; then
        st="FINDINGS"
      else
        st="NONZERO-EXIT"
      fi
      row "{\"tool\":\"$n\",\"status\":\"$st\",\"output\":\"dep-$n.out\"}"
      rr "$n ................................ $st (classify per rubric)";;
  esac
}
un(){ row "{\"tool\":\"$1\",\"status\":\"UNAVAILABLE\"}"; rr "$1 .................... UNAVAILABLE ($2 not installed)"; }
gated(){ row "{\"tool\":\"$1\",\"status\":\"GATED\",\"reason\":\"$2\"}"
  rr "$1 .................... GATED ($2; RHA_ALLOW_REPO_EXEC=1 arms it — coverage UNVERIFIED)"; }

jsm=false
for m in package-lock.json pnpm-lock.yaml yarn.lock bun.lockb package.json; do [ -f "$m" ] && jsm=true; done
if $jsm; then
  command -v npm >/dev/null && run npm-audit "npm audit --json" || un npm-audit npm
fi
# requirements.txt: --disable-pip --no-deps reads pins statically (no install;
# unpinned/URL lines come back as skip_reason). Full resolution is literally
# `pip install -r` — measured: it ran a local setup.py — so it is gated.
if [ -f requirements.txt ]; then
  if ! command -v pip-audit >/dev/null; then un pip-audit-req pip-audit
  elif [ "$EXEC" = 1 ]; then run pip-audit-req "pip-audit -r requirements.txt --format json"
  else run pip-audit-req "pip-audit --disable-pip --no-deps -r requirements.txt --format json"
       rr "  (static pins only; full resolution GATED: it installs, i.e. runs, the requirements)"
  fi
fi
# pyproject.toml: bare `pip-audit` audits pip-audit's OWN environment, not the
# project; the project form (`pip-audit .`) builds it via its backend = repo code.
if [ -f pyproject.toml ]; then
  if ! command -v pip-audit >/dev/null; then un pip-audit pip-audit
  elif [ "$EXEC" = 1 ]; then run pip-audit "pip-audit --format json ."
  else gated pip-audit "builds the project, running its build backend"
  fi
fi
[ -f go.mod ] && { command -v govulncheck >/dev/null && run govulncheck "govulncheck ./..." || un govulncheck govulncheck; }
# --locked: read composer.lock, not vendor/; --no-plugins/--no-scripts: never
# load plugin or script code shipped with the repo.
[ -f composer.lock ] && { command -v composer >/dev/null && run composer-audit "composer audit --locked --no-plugins --no-scripts --no-interaction --format=json" || un composer-audit composer; }
# Maven loads build extensions (.mvn/extensions.xml, pom <extensions>) and
# repo-chosen plugins + .mvn/jvm.config — repo code on the JVM.
if [ -f pom.xml ]; then
  if ! command -v mvn >/dev/null; then un mvn-owasp mvn
  elif [ "$EXEC" = 1 ]; then run mvn-owasp "mvn -B org.owasp:dependency-check-maven:check -DskipTests"
  else gated mvn-owasp "Maven loads repo-declared extensions/plugins"
  fi
fi
exit 0
