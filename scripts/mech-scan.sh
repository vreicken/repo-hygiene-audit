#!/usr/bin/env bash
# mech-scan.sh — mechanical leg of repo-hygiene-audit.
# usage: mech-scan.sh [target-repo]      (prints the run dir it created)
# Emits: mech.jsonl (machine rows), run-report.md (readable coverage),
# scope.json (what the audit covered). What ran / didn't / why lives HERE —
# in the run-report — not in SKILL.md prose, not in the responding model.
# Values of secret-shaped content are never printed: file + line + class only.
set -u

TARGET="${1:-.}"
[ -d "$TARGET/.git" ] || { echo "not a git repo: $TARGET" >&2; exit 2; }
cd "$TARGET"

TS=$(date '+%Y-%m-%d-%H%M')
RUN="$PWD/.local/hygiene-audit/$TS"
mkdir -p "$RUN"
JSONL="$RUN/mech.jsonl"
REPORT="$RUN/run-report.md"
SCOPE="$RUN/scope.json"
DENYLIST="${RHA_PRIVATE_DENYLIST:-$HOME/.pi/rha-private/denylist.txt}"

: > "$JSONL"; : > "$REPORT"
row() { printf '%s\n' "$1" >> "$JSONL"; }
rr()  { printf '%s\n' "$1" >> "$REPORT"; }

rr "# mech-scan run report — $TARGET, $TS"
rr "assumptions: audience=public (owner answers override); denylist=$DENYLIST"

printf '{"target":"%s","tracked_files":%s,"denylist":"%s","ts":"%s"}\n' \
  "$PWD" "$(git ls-files | wc -l)" "$DENYLIST" "$TS" > "$SCOPE"

rr ""
rr "## coverage"

# gitleaks: baseline is READ, never auto-updated — updating one is an owner
# triage decision (offered only at the propose-fixes step).
BASE="$PWD/.local/hygiene-audit/baseline/gitleaks.json"
bl=""
[ -f "$BASE" ] && bl="--baseline-path $BASE"
if command -v gitleaks >/dev/null 2>&1; then
  # gitleaks exits non-zero both when it FINDS leaks and when it breaks.
  # A report file written => it ran to completion => findings, not failure.
  rm -f "$RUN/gitleaks.json"
  gitleaks git --redact --report-format json --report-path "$RUN/gitleaks.json" $bl >/dev/null 2>&1
  glrc=$?
  if [ "$glrc" -eq 0 ] || [ -s "$RUN/gitleaks.json" ]; then
    gst=OK; [ "$glrc" -ne 0 ] && gst=FINDINGS
    row "{\"tool\":\"gitleaks\",\"status\":\"$gst\",\"mode\":\"git --redact$([ -n "$bl" ] && echo ' --baseline')\",\"output\":\"gitleaks.json\"}"
    if [ -n "$bl" ]; then
      rr "gitleaks history scan ................ $gst (gitleaks.json; findings are NEW since baseline - values redacted)"
    else
      rr "gitleaks history scan ................ $gst (gitleaks.json; full-history first sweep - values redacted)"
    fi
  else
    row '{"tool":"gitleaks","status":"FAILED"}'
    rr "gitleaks history scan ................ FAILED (history runs UNVERIFIED, not clean)"
  fi
else
  row '{"tool":"gitleaks","status":"UNAVAILABLE"}'
  rr "gitleaks history scan ................ UNAVAILABLE (not on PATH)"
fi
if [ -f "$BASE" ]; then
  rr "baseline ............................. present (reads only; updates happen at the propose-fixes step, never automatically)"
else
  rr "baseline ............................. absent (no auto-creation — creation+triage happens at the propose-fixes step)"
fi

# arming canary: strip anchors from the first probe entry so the pattern CAN
# match a bare user error (see privacy-guard's measured pitfall), then both
# directions must hold: token -> hit, clean text -> no hit. @identity: lines
# are not probe patterns, so they are excluded here.
armed="UNAVAILABLE"
if [ -s "$DENYLIST" ]; then
  tok=$(grep -Ev '^[[:space:]]*@identity:' "$DENYLIST" | grep -v '^[[:space:]#]' | head -1 \
      | sed -E 's/^\\b//; s/\\b$//; s/^\^//; s/\$$//')
  if [ -n "$tok" ]; then
    echo "$tok" | grep -Eq "$tok" && hit=1 || hit=0
    printf 'clean-text-without-token\n' | grep -Eq "$tok" && miss=0 || miss=1
    if [ "$hit" = 1 ] && [ "$miss" = 1 ]; then armed="PROBE-ARMED"; else armed="UNARMED"; fi
  fi
fi
row "{\"tool\":\"denylist-probes\",\"status\":\"$armed\"}"
rr "denylist probe arming ................ $armed"

plain=$(grep -Ev '^[[:space:]]*@identity:' "$DENYLIST" 2>/dev/null || true)

if [ -s "$DENYLIST" ] && [ "$armed" = "PROBE-ARMED" ]; then
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue;; esac
    shas=$(git log --all --format='%H|%s|%b' | grep -Ei "$pat" | cut -d'|' -f1 | sort -u || true)
    if [ -n "$shas" ]; then
      row "{\"q\":\"Q3/Q7\",\"surface\":\"commit-message\",\"pattern_class\":\"denylist\",\"commits\":[$(echo "$shas" | awk '{printf "\"%s\",",$1}' | sed 's/,$//')]}"
      rr "commit-message hits .................. $(echo "$shas" | wc -l) commits (SHAs only; text not returned)"
    fi
    while IFS= read -r b; do
      case "$b" in ''|origin/HEAD) continue;; esac
      echo "$b" | grep -Eiq "$pat" && {
        row "{\"q\":\"Q3/Q8\",\"surface\":\"branch-name\",\"name\":\"$b\"}"; rr "branch-name hit ...................... $b"; }
    done < <(git branch -a --format='%(refname:short)')
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -Enm3 -e "$pat" -- "$f" 2>/dev/null | while IFS= read -r l; do
        row "{\"q\":\"Q2/Q3/Q8\",\"file\":\"$f\",\"line\":${l%%:*},\"pattern_class\":\"denylist\"}"
      done
    done < <(git ls-files -z | xargs -0 -n1 echo 2>/dev/null)
  done <<< "$plain"
elif [ "$armed" = "UNARMED" ]; then
  rr "denylist probes ...................... UNARMED: denylist rows are emitted as UNVERIFIED"
  row '{"tool":"denylist-probes","status":"UNARMED","note":"denylist rows emitted as UNVERIFIED"}'
elif [ "$armed" = "UNAVAILABLE" ]; then
  rr "denylist probes ...................... UNAVAILABLE (no denylist at $DENYLIST)"
fi

# identity pass: @identity: lines are checked against commit AUTHOR
# identities only — emails/usernames surface as Q7 rows mechanically.
ident=$(grep -E '^[[:space:]]*@identity:[[:space:]]*.' "$DENYLIST" 2>/dev/null | sed -E 's/^[[:space:]]*@identity:[[:space:]]*//' || true)
if [ -n "$ident" ] && [ "$armed" = "PROBE-ARMED" ]; then
  while IFS= read -r ipat; do
    case "$ipat" in ''|\#*) continue;; esac
    ish=$(git log --all --format='%H|%an|%ae' | grep -Ei "$ipat" | cut -d'|' -f1 | sort -u || true)
    if [ -n "$ish" ]; then
      row "{\"q\":\"Q7\",\"surface\":\"author-identity\",\"pattern_class\":\"denylist\",\"commits\":[$(echo "$ish" | awk '{printf "\"%s\",",$1}' | sed 's/,$//')]}"
      rr "author-identity hits ................. $(echo "$ish" | wc -l) commits by matching identities (SHAs only; emails not returned)"
    fi
  done <<< "$ident"
fi

( git ls-files -z | xargs -0 du -b 2>/dev/null | sort -rn | head -15 ) \
  | while read -r sz f; do row "{\"q\":\"Q5/Q8\",\"kind\":\"size\",\"path\":\"$f\",\"bytes\":$sz}"; done
rr "size sweep ........................... OK (top 15 in mech.jsonl)"

# controls presence — absence is reported by the model as a HIGH finding
pc=false; husk=false; wf=false
[ -f .pre-commit-config.yaml ] && grep -qiE 'gitleaks|trufflehog' .pre-commit-config.yaml 2>/dev/null && pc=true
[ -f .husky/pre-commit ] && grep -qiE 'gitleaks|trufflehog' .husky/pre-commit 2>/dev/null && husk=true
git ls-files '.github/workflows/*' | xargs grep -liE 'gitleaks|trufflehog' 2>/dev/null | grep -q . && wf=true
if $pc || $husk || $wf; then
  row '{"control":"pre-commit-secret-scanner","present":true}'
  rr "pre-commit secret scanner ............ present"
else
  row '{"control":"pre-commit-secret-scanner","present":false,"evidence":"no gitleaks/trufflehog in .pre-commit-config.yaml, .husky/, or workflows"}'
  rr "pre-commit secret scanner ............ ABSENT (rubric: report as HIGH absence-of-control)"
fi

# unpushed-commits layer — exposure rung between worktree and public.
# Upstream resolution: @{u} requires tracking config, which a plain
# `git push origin HEAD` does not set — fall back to origin/<branch>.
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  [ -n "$branch" ] && git rev-parse --verify -q "refs/remotes/origin/$branch" >/dev/null 2>&1 && upstream="origin/$branch"
fi
if [ -n "$upstream" ]; then
  unpushed=$(git rev-list --count "${upstream}..HEAD")
  row "{\"q\":\"exposure\",\"surface\":\"unpushed\",\"count\":$unpushed,\"upstream\":\"$upstream\"}"
  rr "unpushed commits ..................... $unpushed vs $upstream (one push from permanent; not yet public)"
  if [ "$unpushed" -gt 0 ]; then
    git log --name-only --format= "${upstream}..HEAD" \
      | grep -iE '(PLAN|ROADMAP|\.env|secret|credential|token|\.pem$|\.key$|password|scratch)' \
      | sort -u | while IFS= read -r f; do
          [ -n "$f" ] && row "{\"q\":\"Q1/Q4/Q7\",\"exposure\":\"unpushed\",\"file\":\"$f\"}"
        done
  fi
else
  row '{"q":"exposure","surface":"unpushed","status":"NO-UPSTREAM"}'
  rr "unpushed commits ..................... NO-UPSTREAM (everything is unpushed; treat repo as pre-publication draft)"
fi

rr ""
rr "rows in mech.jsonl: $(wc -l < "$JSONL") — the rubric walk parses that; this report is for reading."
echo "$RUN"
