# _common.sh — sourced by the three legs. Portable to bash 3.2 (macOS);
# no GNU-only tools (du -b, md5sum, grep -z) — git does sizes and hashes.

# JSON string escape (no surrounding quotes). Filenames, branch names and
# paths are attacker-controlled data: never interpolate them raw into JSON.
js() {
  local s=$1
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

# Resolve a repo top-level. `.git` is a FILE in worktrees and submodules,
# so never test it with -d; ask git.
repo_root() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null; }

# Strip wc's leading padding (BSD wc right-aligns).
count() { wc -l | tr -d ' '; }
