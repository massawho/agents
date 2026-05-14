---
name: git-commit
description: Stage and commit git changes following a structured commit message workflow. Use when the user wants to commit changes, save their work, or says things like "commit this", "commit these changes", "let's commit", or simply "commit". Also activates when completing a task that produced code changes worth saving. Never commit without loading this skill.
---

# Git Commit Workflow

Stage relevant changes and write a commit message that answers three questions:
why this change was necessary, how it addresses the issue, and what side effects
it has.

## Commit Message Structure

**Title** (required): ≤50 characters, capitalized, imperative verb ("Add",
"Fix", "Remove", "Drop"), no period. Followed by a blank line.

**Problem paragraph** (required): 1–2 sentences on what was broken, missing,
or painful before this change. This tells reviewers what to expect.

**Solution paragraph** (required unless the change is obvious): what was done
to address it. Always open with a prose sentence. If the change has multiple
distinct parts, follow it with a bullet list — bullets give a faster, more
objective read than a long paragraph. If the change is a single cohesive
thing, prose alone is fine.

**Side effects paragraph** (optional): breaking changes, migration notes,
behavior changes consumers must know about, or intentional omissions. Use
this paragraph to be honest about scope. A long list is fine when the commit
is genuinely atomic — all changes serve a single purpose. The warning sign
is unrelated items appearing here, not the count.

**Trailing references** (optional): ticket/card URL and/or a link to the spec
or plan that drove the change. Each on its own line at the end.

### Format rules

- Body lines wrap at 72 characters.
- Blank line between every paragraph.
- Bullets use a hyphen and single space: `- item`.
- No em dashes (`—`) or double hyphens (`--`). Use commas, parentheses, or
  separate sentences instead.

## Examples

### Feature with bullet solution

```
Add nightly report delivery via email

The reporting module had no scheduled delivery mechanism, requiring
users to log in and export reports manually each morning.

This change introduces a background job that:
- Queries active subscriptions and their configured report filters.
- Renders each report as a PDF attachment.
- Delivers it via the existing mailer with a retry policy of 3
  attempts before marking the job as failed.

Jobs are enqueued at 06:00 UTC by default. The schedule is
configurable per tenant via the admin panel.

https://linear.app/team/issues/PROJ-42
```

### Larger refactor with side effects

```
Migrate authentication from session cookies to JWT

The cookie-based session store was incompatible with the new mobile
client, which cannot share cookies across subdomains.

This change replaces the session-based auth middleware with a JWT
pipeline using short-lived access tokens and rotating refresh tokens.
It updates all protected routes to verify the token from the
Authorization header and removes the legacy session plug.

- Add TokenStore context with issue/verify/revoke functions
- Replace SessionPlug with JWTPlug across the router
- Update login and logout controllers for token exchange flow
- Remove session migration helper introduced in v1.3

Existing sessions are invalidated on deploy. Users will need to log
in again. The mobile client must send `Authorization: Bearer <token>`
on all authenticated requests.
```

### Bug fix with prose solution

```
Fix double-charge on network timeout during checkout

When the payment provider timed out, the client retried the request
without an idempotency key, occasionally resulting in two charges for
the same order. This affected roughly 1 in 8,000 transactions.

This change generates a stable idempotency key from the order ID
before calling the payment provider and passes it on every attempt.
It also stores the provider's response against the key so retries
return the cached result instead of making a new charge.

The fix requires a one-time backfill to populate keys for orders
created in the past 30 days.
```

### Refactor with multiple parts

```
Extract pagination logic into shared helper

Pagination was implemented identically across the orders, products,
and invoices controllers. Any change to the default page size, the
per-page cap, or the response shape required updating three places,
and they had already drifted slightly.

This change introduces lib/pagination.py with a single paginate
function that accepts a SQLAlchemy query and the request object.

- Replace the nine-line inline block in each list controller
- Cap per-page at 100 via the helper rather than per-controller
```

### Simple single-change refactor

```
Extract rate limiting into a dedicated plug

Rate limiting logic was duplicated across three controllers with
slightly different thresholds, making it easy to miss when updating
limits or adding new endpoints.

This commit extracts the logic into RateLimiter.Plug and wires it
into the router pipeline. The per-route thresholds are unchanged.
```

## Cross-Repo Commits

When committing in a repo that is NOT the current working directory,
use `git -C <path>` to stay in place:

```bash
# Good
git -C ~/.dotfiles add ai/skills/git-commit/
git -C ~/.dotfiles commit -m "..."

# Bad — triggers permission prompts
cd ~/.dotfiles && git commit -m "..."
```

## Committing via Terminal

Pass each paragraph as a separate `-m` flag:

```bash
git commit \
  -m "Title here" \
  -m "Problem paragraph." \
  -m "Solution paragraph." \
  -m "Side effects paragraph."
```

Or use `$'...'` syntax for inline newlines in zsh/bash:

```bash
git commit -m $'Title here\n\nProblem.\n\nSolution.'
```

## After Committing

- Tell the user what the commit title was.
- Do not push. Wait for the user to confirm before pushing.
- Do not include `Co-Authored-By: Claude` or any indication that AI
  assisted in writing the commit or message.
