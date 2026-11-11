#!/usr/bin/env bash
# sweep-delta.sh — sweep continuity leg.
# usage: sweep-delta.sh <run-dir> [target-repo]
# 1. grades .gitignore COVERAGE against tracked sensitive-class files
# 2. writes a content-hash manifest for sweep-over-sweep diffing — a file
#    "unchanged since last sweep" is verified by hash, never assumed
# 3. a missing .local/hygiene-audit gitignore entry becomes gitignore.draft
#    (a report proposal — never applied to the repo by us)
set -u
RUNDIR="${1:-}"; TARGET="${2:-.}"
[ -d "$RUNDIR" ] || { echo "pass a mech-scan run dir as \$1" >&2; exit 2; }
[ -d "$TARGET/.git" ] || TARGET=$PWD
cd "$TARGET" || exit 2
JSONL="$RUNDIR/mech.jsonl"; REPORT="$RUNDIR/run-report.md"
row(){ printf '%s\n' "$1" >> "$JSONL"; }
rr() { printf '%s\n' "$1" >> "$REPORT"; }

rr ""
rr "## sweep-delta"
slip=$(git ls-files | grep -iE '(\.env$|\.env\.|secret|credential|token|\.pem$|\.key$|password|\.scannerwork|^temp/|/coverage/|^dist/|^build/|\.idea/|\.vscode/)' || true)
if [ -n "$slip" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    row "{\"q\":\"Q1/Q5/Q8\",\"kind\":\"gitignore-coverage\",\"tracked\":\"$f\"}"
  done <<< "$slip"
  rr "gitignore-coverage slippages ......... $(echo "$slip" | wc -l) tracked files in sensitive-class names (mech.jsonl)"
else
  rr "gitignore-coverage slippages ......... none found"
fi

git ls-files -z | xargs -0 md5sum 2>/dev/null | sort > "$RUNDIR/sweep-manifest"
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

if ! grep -q 'hygiene-audit' .gitignore 2>/dev/null; then
  printf '.local/hygiene-audit/\n' > "$RUNDIR/gitignore.draft"
  rr "gitignore entry ...................... MISSING -> gitignore.draft written (owner applies)"
fi
exit 0
