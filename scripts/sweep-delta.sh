#!/usr/bin/env bash
# sweep-delta.sh — sweep continuity leg.
# usage: sweep-delta.sh <run-dir> [target-repo]
# 1. grades .gitignore COVERAGE against tracked sensitive-class files
# 2. writes a content-hash manifest for sweep-over-sweep diffing — a file
#    "unchanged since last sweep" is verified by hash, never assumed
# 3. a missing .local/hygiene-audit gitignore entry becomes gitignore.draft
#    (a report proposal — never applied to the repo by us)
set -u
. "$(dirname "$0")/_common.sh"
RUNDIR="${1:-}"; TARGET="${2:-.}"
[ -d "$RUNDIR" ] || { echo "pass a mech-scan run dir as \$1" >&2; exit 2; }
ROOT=$(repo_root "$TARGET") || ROOT=""
[ -n "$ROOT" ] || { echo "not a git repo: $TARGET" >&2; exit 2; }
cd "$ROOT" || exit 2
JSONL="$RUNDIR/mech.jsonl"; REPORT="$RUNDIR/run-report.md"
row(){ printf '%s\n' "$1" >> "$JSONL"; }
rr() { printf '%s\n' "$1" >> "$REPORT"; }

rr ""
rr "## sweep-delta"
# -z: without it git C-quotes non-ASCII/odd names ("\303\244"), which then
# neither match the regex reliably nor survive into JSON.
re='(\.env$|\.env\.|secret|credential|token|\.pem$|\.key$|password|\.scannerwork|^temp/|/coverage/|^dist/|^build/|\.idea/|\.vscode/)'
shopt -s nocasematch
nslip=0
while IFS= read -r -d '' f; do
  if [[ $f =~ $re ]]; then
    row "{\"q\":\"Q1/Q5/Q8\",\"kind\":\"gitignore-coverage\",\"tracked\":\"$(js "$f")\"}"
    nslip=$((nslip+1))
  fi
done < <(git ls-files -z)
shopt -u nocasematch
if [ "$nslip" -gt 0 ]; then
  rr "gitignore-coverage slippages ......... $nslip tracked files in sensitive-class names (mech.jsonl)"
else
  rr "gitignore-coverage slippages ......... none found"
fi

# worktree content hashes via git (portable; md5sum is GNU-only).
# Names containing a newline can't go through --stdin-paths; they are skipped.
git ls-files -z | while IFS= read -r -d '' f; do
    case "$f" in *$'\n'*) continue;; esac
    [ -f "$f" ] && printf '%s\n' "$f"
  done > "$RUNDIR/.sweep-paths"
git hash-object --stdin-paths < "$RUNDIR/.sweep-paths" \
  | paste -d' ' - "$RUNDIR/.sweep-paths" | sort > "$RUNDIR/sweep-manifest"
rm -f "$RUNDIR/.sweep-paths"
mkdir -p "$PWD/.local/hygiene-audit/baseline"
# stable path: run dirs are timestamped, so a per-run prev can never be found
prev="$PWD/.local/hygiene-audit/baseline/sweep-manifest.prev"
if [ -f "$prev" ]; then
  if diff -q "$prev" "$RUNDIR/sweep-manifest" >/dev/null 2>&1; then
    rr "sweep vs previous .................... unchanged (hash-verified)"
  else
    rr "sweep vs previous .................... CHANGED (diff the two manifest files)"
  fi
else
  rr "sweep vs previous .................... first sweep (baseline stored)"
fi
cp "$RUNDIR/sweep-manifest" "$prev"

# ask git whether the run dir is ignored — a broader rule (.local/, *.local)
# covers it just as well as a literal "hygiene-audit" line.
if ! git check-ignore -q --no-index ".local/hygiene-audit/x"; then
  printf '.local/hygiene-audit/\n' > "$RUNDIR/gitignore.draft"
  rr "gitignore entry ...................... MISSING -> gitignore.draft written (owner applies)"
fi
exit 0
