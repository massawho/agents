---
name: git-commit
description: Stage and commit git changes with a structured commit message. Use when the user wants to commit changes or save work ("commit this", "let's commit", "commit"), or after completing code changes worth saving. Never commit without loading this skill.
---

# Git Commit

A good commit message answers three questions: **why** the change was
necessary, **how** it addresses the issue, and **what** side effects it has.
Work the steps in order; the Format section is the single source of truth for
every rule.

## Steps

1. **Scope the stage.** Run `git status` and `git diff`. Stage only files
   within the task's scope — confirm nothing unrelated is included.

2. **Write the message to a file.** Resolve the git directory, which works in
   normal repos and worktrees alike:
   ```bash
   git rev-parse --absolute-git-dir
   ```
   Compose the message per the Format below and write it with the Write tool
   to `<that path>/COMMIT_EDITMSG`. This file always exists, is never tracked,
   and needs no cleanup. Never invent a `.tmp/` path.

3. **Verify, then commit.** Before committing, confirm every rule in Format
   holds — title ≤50 chars, body wrapped at 72, blank lines between
   paragraphs, no em dashes. Then commit from the file:
   ```bash
   git commit -F <that path>/COMMIT_EDITMSG
   ```
   Do NOT use `git commit -m` — agents mis-wrap multi-line messages inside
   shell quoting. Always commit from the file.

   A `PreToolUse` guard (`scripts/commit-guard.sh`) runs on this commit and
   may block it: it re-checks the message format and runs the project's
   detected checks (format, lint, type, test). If it blocks, fix exactly what
   it reports — for a formatter failure, run the fixer and re-stage — then
   commit again. Do not bypass it with `--no-verify`.

4. **Report.** Tell the user the commit title. Do not push; wait for the user
   to confirm. Never add `Co-Authored-By: Claude` or any AI-assisted note.

## Format

**Title** (required): ≤50 characters, capitalized, imperative verb (Add, Fix,
Remove, Drop), no trailing period. Blank line after.

**Problem** (required): 1–2 sentences on what was broken, missing, or painful
before this change.

**Solution** (required unless the change is obvious): always open with a prose
sentence on what was done. If the change has multiple distinct parts, follow
with a bullet list; if it is a single cohesive thing, prose alone is fine.

**Side effects** (optional): breaking changes, migration notes, behavior
changes consumers must know about, or intentional omissions. A long list is
fine when the commit is genuinely atomic (all changes serve a single purpose);
the warning sign is unrelated items, not the count.

**Trailing references** (optional): ticket/card URL and/or a link to the spec
or plan that drove the change, each on its own line at the end.

Mechanical rules:
- Body lines wrap at 72 characters; blank line between every paragraph.
- Bullets use a hyphen and single space: `- item`.
- No em dashes (`—`) or double hyphens (`--`). Use commas, parentheses, or
  separate sentences.

## Examples

Bug fix, prose solution with a side effect:

```
Fix double-charge on network timeout during checkout

When the payment provider timed out, the client retried the request
without an idempotency key, occasionally resulting in two charges for
the same order. This affected roughly 1 in 8,000 transactions.

This change generates a stable idempotency key from the order ID
before calling the payment provider and passes it on every attempt.
It also caches the provider's response so retries return the cached
result instead of making a new charge.

The fix requires a one-time backfill to populate keys for orders
created in the past 30 days.
```

Feature, bullet solution with a trailing reference:

```
Add nightly report delivery via email

The reporting module had no scheduled delivery mechanism, requiring
users to log in and export reports manually each morning.

This change introduces a background job that:
- Queries active subscriptions and their configured report filters.
- Renders each report as a PDF attachment.
- Delivers it via the existing mailer, retrying 3 times before
  marking the job as failed.

Jobs are enqueued at 06:00 UTC by default, configurable per tenant
via the admin panel.

https://linear.app/team/issues/PROJ-42
```

## Cross-repo commits

When committing in a repo that is NOT the current working directory, use
`git -C <path>` for every git call, including the path resolution:

```bash
# Good — resolve and commit inside <path>
git -C ~/.dotfiles add ai/skills/git-commit/
git -C ~/.dotfiles rev-parse --absolute-git-dir   # -> message file location
git -C ~/.dotfiles commit -F <that path>/COMMIT_EDITMSG

# Bad — cd triggers permission prompts
cd ~/.dotfiles && git commit -m "..."
```

## The commit guard

`scripts/commit-guard.sh` is a Claude Code `PreToolUse` hook that fires only
on the agent's commits (never the user's own terminal commits). It validates
the message format and runs the project's checks in check mode, blocking the
commit on any failure. It auto-detects Elixir, Node, Rust, Python, and Go, and
defers to an existing pre-commit framework (Husky, lefthook, `pre-commit`).

To adapt a project — most importantly to run checks inside a container — drop
a `.commit-guard.sh` at the repo root. See `scripts/commit-guard.example.sh`
for every knob; the common one is `RUNNER`:

```bash
# .commit-guard.sh
RUNNER="docker compose exec -T app"
```
