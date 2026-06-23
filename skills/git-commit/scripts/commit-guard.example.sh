# .commit-guard.sh — drop this at a repo root to teach the commit guard how
# THIS project runs its checks. It is sourced by commit-guard.sh. Every knob
# is optional; with no file, checks run bare on the host with auto-detection.

# Prepend a runner to every detected command. This is the docker case:
# `mix format --check-formatted` becomes
# `docker compose exec -T app mix format --check-formatted`.
# RUNNER="docker compose exec -T app"

# Skip categories or named checks (space separated): fmt lint type test msg
# SKIP="test"

# Enable the slow Elixir dialyzer check (off by default).
# DIALYZER=1

# Run only the message-format check, no project checks at all.
# SKIP_SANITIZE=1

# Replace auto-detection entirely. Each entry is "name|command" and is run
# through RUNNER like the detected ones. Use this for monorepos or anything
# the sniffer gets wrong.
# CHECKS=(
#   "format|mix format --check-formatted"
#   "credo|mix credo --strict"
#   "test|mix test --warnings-as-errors"
# )

# Add checks on top of auto-detection (same "name|command" shape).
# EXTRA_CHECKS=(
#   "typecheck|pnpm run typecheck"
# )
