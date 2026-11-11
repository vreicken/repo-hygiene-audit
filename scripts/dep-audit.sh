#!/usr/bin/env bash
# dep-audit.sh — dependency/lockfile leg.
# usage: dep-audit.sh <run-dir> [target-repo]   (run AFTER mech-scan.sh; appends to its mech.jsonl)
# Auditors keyed off the manifests FOUND. A manifest whose auditor is not
# installed produces an UNAVAILABLE row — never silence, never "assumed ok".
set -u
RUNDIR="${1:-}"; TARGET="${2:-.}"
[ -d "$RUNDIR" ] || { echo "pass a mech-scan run dir as \$1 (it holds mech.jsonl)" >&2; exit 2; }
[ -d "$TARGET/.git" ] || TARGET=$PWD
cd "$TARGET" || exit 2
JSONL="$RUNDIR/mech.jsonl"; REPORT="$RUNDIR/run-report.md"
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

jsm=false
for m in package-lock.json pnpm-lock.yaml yarn.lock bun.lockb package.json; do [ -f "$m" ] && jsm=true; done
if $jsm; then
  command -v npm >/dev/null && run npm-audit "npm audit --json" || un npm-audit npm
fi
[ -f requirements.txt ] && { command -v pip-audit >/dev/null && run pip-audit-req "pip-audit -r requirements.txt --format json" || un pip-audit-req pip-audit; }
[ -f pyproject.toml ] && { command -v pip-audit >/dev/null && run pip-audit "pip-audit --format json" || un pip-audit pip-audit; }
[ -f go.mod ] && { command -v govulncheck >/dev/null && run govulncheck "govulncheck ./..." || un govulncheck govulncheck; }
[ -f composer.lock ] && { command -v composer >/dev/null && run composer-audit "composer audit --format=json" || un composer-audit composer; }
[ -f pom.xml ] && { command -v mvn >/dev/null && run mvn-owasp "mvn -B org.owasp:dependency-check-maven:check -DskipTests" || un mvn-owasp mvn; }
exit 0
