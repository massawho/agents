#!/usr/bin/env bash
# commit-guard.sh — Claude Code PreToolUse guard for `git commit`.
#
# Fires ONLY on the agent's commits (a PreToolUse hook never sees your own
# terminal commits). It does two jobs and BLOCKS the commit (exit 2) on any
# failure, handing the agent an actionable message:
#   1. Validates the commit-message format (the countable rules the model
#      drifts on in long contexts: <=50 title, blank line 2, <=72 body, no
#      em dash).
#   2. Runs the project's detected checks (format / lint / type / test /
#      analysis) in CHECK mode — it never edits files, so the staged tree
#      can't drift. A failure tells the agent which fixer to run.
#
# Per-project execution pattern (e.g. docker): drop a `.commit-guard.sh` at
# the repo root. See commit-guard.example.sh for every knob (RUNNER, SKIP,
# DIALYZER, CHECKS, EXTRA_CHECKS, SKIP_SANITIZE).

set -uo pipefail

input="$(cat)"
tool="$(jq -r '.tool_name    // ""' <<<"$input" 2>/dev/null)"
cmd="$(jq  -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)"
cwd="$(jq  -r '.cwd          // ""' <<<"$input" 2>/dev/null)"

# Only guard real `git commit` invocations made via the Bash tool.
[ "$tool" = "Bash" ] || exit 0
printf '%s' "$cmd" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -Eq -- '--dry-run' && exit 0

# Resolve the repo directory, honouring `git -C <path>`.
repo="$cwd"
cpath="$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p')"
[ -n "$cpath" ] && repo="${cpath/#\~/$HOME}"
[ -d "$repo" ] || repo="$cwd"
cd "$repo" 2>/dev/null || exit 0
top="$(git rev-parse --show-toplevel 2>/dev/null)" && { cd "$top" || exit 0; repo="$top"; }

# ---- per-project config -----------------------------------------------------
RUNNER=""          # prefix prepended to every detected command (e.g. docker)
SKIP=""            # space list of categories/names to skip: fmt lint type test
DIALYZER=0         # 1 to enable the slow Elixir dialyzer check
SKIP_SANITIZE=0    # 1 to run only the message check, no project checks
declare -a CHECKS=()        # "name|cmd" entries that REPLACE auto-detection
declare -a EXTRA_CHECKS=()  # "name|cmd" entries ADDED to auto-detection
for cfg in "$repo/.commit-guard.sh" "$repo/.claude/commit-guard.sh"; do
  # shellcheck disable=SC1090
  [ -f "$cfg" ] && source "$cfg"
done

# ---- 1. message format ------------------------------------------------------
declare -a msgerr=()
if [[ "$SKIP" != *msg* ]]; then
  msgfile="$(printf '%s' "$cmd" | sed -nE 's/.*-F[[:space:]]+([^[:space:]"'"'"']+).*/\1/p')"
  [ -n "$msgfile" ] && [ "${msgfile:0:1}" != "/" ] && msgfile="$repo/$msgfile"
  if [ -n "$msgfile" ] && [ -f "$msgfile" ]; then
    mapfile -t L < "$msgfile"
    title="${L[0]:-}"
    tlen=${#title}
    [ "$tlen" -gt 50 ] && msgerr+=("Title is $tlen chars (max 50): \"$title\"")
    [[ "$title" == *. ]] && msgerr+=("Title must not end with a period.")
    [[ "$title" =~ ^[a-z] ]] && msgerr+=("Capitalize the title.")
    [ "${#L[@]}" -gt 1 ] && [ -n "${L[1]:-}" ] && msgerr+=("Line 2 must be blank (blank line after the title).")
    i=0
    for line in "${L[@]}"; do
      i=$((i + 1))
      case "$line" in *"—"*) msgerr+=("Line $i has an em dash (—); use commas/parentheses.");; esac
      case "$line" in *" -- "*) msgerr+=("Line $i has a double hyphen (--).");; esac
      if [ "$i" -ge 3 ] && [ "${#line}" -gt 72 ] && [[ "$line" == *" "* ]] && [[ "$line" != *"://"* ]]; then
        msgerr+=("Line $i exceeds 72 chars (${#line}).")
      fi
    done
  fi
fi

# ---- 2. project checks (detect, run in CHECK mode) --------------------------
declare -a planned=()  # "category|name|command"
add() { planned+=("$1|$2|$3"); }

# Defer to an existing hook framework — it already sanitizes on commit.
deferred=0
{ [ -f .pre-commit-config.yaml ] || [ -d .husky ] || [ -f lefthook.yml ] || [ -f .lefthook.yml ]; } && deferred=1

if [ "$SKIP_SANITIZE" != "1" ] && [ "$deferred" = "0" ]; then
  if [ "${#CHECKS[@]}" -gt 0 ]; then
    for c in "${CHECKS[@]}"; do planned+=("custom|$c"); done
  else
    if [ -f mix.exs ]; then
      add fmt  "mix format" "mix format --check-formatted"
      grep -q ':credo' mix.exs 2>/dev/null && add lint "credo" "mix credo --strict"
      add test "mix test"   "mix test"
      [ "$DIALYZER" = "1" ] && add analysis "dialyzer" "mix dialyzer"
    fi
    if [ -f package.json ]; then
      pm=npm
      [ -f pnpm-lock.yaml ] && pm=pnpm
      [ -f yarn.lock ] && pm=yarn
      [ -f bun.lockb ] && pm=bun
      hs() { jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null 2>&1; }
      hs "format:check" && add fmt  "format:check" "$pm run format:check"
      hs lint           && add lint "lint"         "$pm run lint"
      for ts in typecheck type-check tsc; do hs "$ts" && { add type "$ts" "$pm run $ts"; break; }; done
      hs test           && add test "test"         "$pm run test"
    fi
    if [ -f Cargo.toml ]; then
      add fmt  "cargo fmt" "cargo fmt --check"
      add lint "clippy"    "cargo clippy --all-targets -- -D warnings"
      add test "cargo test" "cargo test"
    fi
    if [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f tox.ini ]; then
      pg() { grep -hq "$1" pyproject.toml setup.cfg tox.ini 2>/dev/null; }
      pg ruff   && { add fmt "ruff format" "ruff format --check ."; add lint "ruff" "ruff check ."; }
      pg black  && add fmt  "black" "black --check ."
      pg mypy   && add type "mypy"  "mypy ."
      pg pytest && add test "pytest" "pytest -q"
    fi
    if [ -f go.mod ]; then
      add fmt  "gofmt"   "gofmt -l ."
      add lint "go vet"  "go vet ./..."
      add test "go test" "go test ./..."
    fi
  fi
fi
[ "${#EXTRA_CHECKS[@]}" -gt 0 ] && for c in "${EXTRA_CHECKS[@]}"; do planned+=("custom|$c"); done

declare -a checkfail=()
if [ "${#planned[@]}" -gt 0 ]; then
  for entry in "${planned[@]}"; do
    IFS='|' read -r cat name ccmd <<<"$entry"
    case " $SKIP " in *" $cat "*|*" $name "*) continue;; esac
    full="$ccmd"; [ -n "$RUNNER" ] && full="$RUNNER $ccmd"
    out="$(eval "$full" 2>&1)"; rc=$?
    [ "$name" = "gofmt" ] && [ -n "$out" ] && rc=1     # gofmt -l lists, exits 0
    [ "$rc" -eq 127 ] && continue                       # tool absent here: skip, don't false-block
    if [ "$rc" -ne 0 ]; then
      checkfail+=("[$name] failed — fix with: $ccmd")
      checkfail+=("$(printf '%s\n' "$out" | tail -n 12 | sed 's/^/    /')")
    fi
  done
fi

# ---- verdict ----------------------------------------------------------------
if [ "${#msgerr[@]}" -eq 0 ] && [ "${#checkfail[@]}" -eq 0 ]; then
  exit 0
fi
{
  echo "Commit blocked by git-commit guard."
  if [ "${#msgerr[@]}" -gt 0 ]; then
    echo; echo "Message format:"
    for e in "${msgerr[@]}"; do echo "  - $e"; done
  fi
  if [ "${#checkfail[@]}" -gt 0 ]; then
    echo; echo "Project checks (run the fixer, re-stage, then commit again):"
    for e in "${checkfail[@]}"; do echo "  $e"; done
  fi
} >&2
exit 2
