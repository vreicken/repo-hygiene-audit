#!/usr/bin/env bash
# mech-scan.sh — mechanical leg of repo-hygiene-audit.
# usage: mech-scan.sh [target-repo]      (prints the run dir it created)
# Emits: mech.jsonl (machine rows), run-report.md (readable coverage),
# scope.json (what the audit covered). What ran / didn't / why lives HERE —
# in the run-report — not in SKILL.md prose, not in the responding model.
# Values of secret-shaped content are never printed: file + line + class only.
set -u
. "$(dirname "$0")/_common.sh"

TARGET="${1:-.}"
ROOT=$(repo_root "$TARGET") || ROOT=""
[ -n "$ROOT" ] || { echo "not a git repo: $TARGET" >&2; exit 2; }
cd "$ROOT" || exit 2

# second resolution + atomic mkdir: two runs in the same second get distinct
# dirs instead of truncating each other's mech.jsonl.
TS=$(date '+%Y-%m-%d-%H%M%S')
mkdir -p "$PWD/.local/hygiene-audit"
RUN="$PWD/.local/hygiene-audit/$TS"; n=1
until mkdir "$RUN" 2>/dev/null; do
  n=$((n+1)); RUN="$PWD/.local/hygiene-audit/$TS-$n"
  [ "$n" -gt 50 ] && { echo "cannot create a run dir under .local/hygiene-audit" >&2; exit 2; }
done
JSONL="$RUN/mech.jsonl"
REPORT="$RUN/run-report.md"
SCOPE="$RUN/scope.json"
DENYLIST="${RHA_PRIVATE_DENYLIST:-${XDG_CONFIG_HOME:-$HOME/.config}/repo-hygiene-audit/denylist.txt}"

: > "$JSONL"; : > "$REPORT"
row() { printf '%s\n' "$1" >> "$JSONL"; }
rr()  { printf '%s\n' "$1" >> "$REPORT"; }

rr "# mech-scan run report — $TARGET, $TS"
rr "assumptions: audience=public (owner answers override); denylist=$DENYLIST"

printf '{"target":"%s","tracked_files":%s,"denylist":"%s","ts":"%s"}\n' \
  "$(js "$PWD")" "$(git ls-files | count)" "$(js "$DENYLIST")" "$TS" > "$SCOPE"

rr ""
rr "## coverage"

# gitleaks: baseline is READ, never auto-updated — updating one is an owner
# triage decision (offered only at the propose-fixes step).
BASE="$PWD/.local/hygiene-audit/baseline/gitleaks.json"
# Repo content is data, not instructions: the audited repo's .gitleaks.toml,
# .gitleaksignore and `gitleaks:allow` comments would otherwise tune (or
# silence) the scanner. Force default rules; their presence becomes a row.
GLCONF="$RUN/gitleaks-default.toml"
printf '[extend]\nuseDefault = true\n' > "$GLCONF"
for f in .gitleaks.toml .gitleaksignore; do
  if [ -e "$f" ]; then
    row "{\"q\":\"Q1\",\"lane\":\"needs-review\",\"kind\":\"scanner-config-in-repo\",\"file\":\"$f\",\"note\":\"bypassed by the scan; review what it allowlists\"}"
    rr "repo-side $f ......... present, bypassed (scan used default rules; review its allowlist)"
  fi
done
if command -v gitleaks >/dev/null 2>&1; then
  glv=$(gitleaks version 2>/dev/null | head -1)
  # `git` subcommand exists from gitleaks 8.19; older builds only have `detect`.
  if gitleaks git --help >/dev/null 2>&1; then glcmd=(gitleaks git); glmode=git
  else glcmd=(gitleaks detect --source .); glmode=detect; fi
  glargs=(--config "$GLCONF" --gitleaks-ignore-path "$RUN" --ignore-gitleaks-allow
          --redact --no-banner --report-format json --report-path "$RUN/gitleaks.json")
  [ -f "$BASE" ] && glargs+=(--baseline-path "$BASE")
  # Exit codes (measured on 8.30.1): 0 + "[]" = clean; 1 + report = leaks;
  # 1 + no report = error. An unreadable baseline is only LOGGED and the scan
  # continues unfiltered — so the log, not the flag, decides the label.
  rm -f "$RUN/gitleaks.json"
  "${glcmd[@]}" "${glargs[@]}" > "$RUN/gitleaks.log" 2>&1
  glrc=$?
  blst=none
  if [ -f "$BASE" ]; then
    if grep -qi 'could not load baseline' "$RUN/gitleaks.log"; then blst=broken; else blst=applied; fi
  fi
  if [ "$glrc" -eq 0 ] || [ -s "$RUN/gitleaks.json" ]; then
    gst=OK; [ "$glrc" -ne 0 ] && gst=FINDINGS
    row "{\"tool\":\"gitleaks\",\"version\":\"$(js "$glv")\",\"status\":\"$gst\",\"mode\":\"$glmode --redact default-rules\",\"baseline\":\"$blst\",\"output\":\"gitleaks.json\"}"
    case "$blst" in
      applied) rr "gitleaks history scan ................ $gst (gitleaks.json; findings are NEW since baseline - values redacted)";;
      broken)  rr "gitleaks history scan ................ $gst (gitleaks.json; baseline FAILED TO LOAD, so full history unfiltered - values redacted)";;
      *)       rr "gitleaks history scan ................ $gst (gitleaks.json; full-history first sweep - values redacted)";;
    esac
  else
    row "{\"tool\":\"gitleaks\",\"version\":\"$(js "$glv")\",\"status\":\"FAILED\",\"log\":\"gitleaks.log\"}"
    rr "gitleaks history scan ................ FAILED (gitleaks.log; history runs UNVERIFIED, not clean)"
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
# match a bare user error, then both directions must hold: token -> hit,
# clean text -> no hit. @identity: lines are not probe patterns, so they are
# excluded here.
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
      rr "commit-message hits .................. $(echo "$shas" | count) commits (SHAs only; text not returned)"
    fi
    while IFS= read -r b; do
      case "$b" in ''|origin/HEAD) continue;; esac
      echo "$b" | grep -Eiq "$pat" && {
        row "{\"q\":\"Q3/Q8\",\"surface\":\"branch-name\",\"name\":\"$(js "$b")\"}"; rr "branch-name hit ...................... $b"; }
    done < <(git branch -a --format='%(refname:short)')
    # -I: a binary match prints "Binary file … matches", not "N:…" — skip it.
    while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      grep -EInm3 -e "$pat" -- "$f" 2>/dev/null | while IFS= read -r l; do
        row "{\"q\":\"Q2/Q3/Q8\",\"file\":\"$(js "$f")\",\"line\":${l%%:*},\"pattern_class\":\"denylist\"}"
      done
    done < <(git ls-files -z)
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
      rr "author-identity hits ................. $(echo "$ish" | count) commits by matching identities (SHAs only; emails not returned)"
    fi
  done <<< "$ident"
fi

# sizes of the INDEXED blobs (what gets published), read through git: portable,
# unlike GNU-only `du -b`. Gitlinks (mode 160000, submodules) have no local blob.
git ls-files -s -z | while IFS= read -r -d '' e; do
    case "$e" in 160000\ *) continue;; esac
    p=${e#*$'\t'}
    case "$p" in *$'\n'*) continue;; esac
    sha=${e#* }; printf '%s %s\n' "${sha%% *}" "$p"
  done | git cat-file --batch-check='%(objectsize) %(rest)' | sort -rn | head -15 \
  | while read -r sz f; do row "{\"q\":\"Q5/Q8\",\"kind\":\"size\",\"path\":\"$(js "$f")\",\"bytes\":$sz}"; done
rr "size sweep ........................... OK (top 15 in mech.jsonl)"

# controls presence — absence is reported by the model as a HIGH finding
pc=false; husk=false; wf=false
[ -f .pre-commit-config.yaml ] && grep -qiE 'gitleaks|trufflehog' .pre-commit-config.yaml 2>/dev/null && pc=true
[ -f .husky/pre-commit ] && grep -qiE 'gitleaks|trufflehog' .husky/pre-commit 2>/dev/null && husk=true
git ls-files -z '.github/workflows/*' | xargs -0 grep -liE 'gitleaks|trufflehog' /dev/null 2>/dev/null | grep -q . && wf=true
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
  row "{\"q\":\"exposure\",\"surface\":\"unpushed\",\"count\":$unpushed,\"upstream\":\"$(js "$upstream")\"}"
  rr "unpushed commits ..................... $unpushed vs $upstream (one push from permanent; not yet public)"
  if [ "$unpushed" -gt 0 ]; then
    git -c core.quotePath=false log --name-only --format= "${upstream}..HEAD" \
      | grep -iE '(PLAN|ROADMAP|\.env|secret|credential|token|\.pem$|\.key$|password|scratch)' \
      | sort -u | while IFS= read -r f; do
          [ -n "$f" ] && row "{\"q\":\"Q1/Q4/Q7\",\"exposure\":\"unpushed\",\"file\":\"$(js "$f")\"}"
        done
  fi
else
  row '{"q":"exposure","surface":"unpushed","status":"NO-UPSTREAM"}'
  rr "unpushed commits ..................... NO-UPSTREAM (everything is unpushed; treat repo as pre-publication draft)"
fi

rr ""
rr "rows in mech.jsonl: $(count < "$JSONL") — the rubric walk parses that; this report is for reading."
echo "$RUN"
