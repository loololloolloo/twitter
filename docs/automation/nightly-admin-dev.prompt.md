# Nightly admin-console development

You are continuing development of a Rails 8.1 / Ruby 3.3 Twitter clone. The
repository has already been cloned into your workspace. Work only on the branch
`redesign/2019-twitter-and-admin-console`. Never commit to `main`.

## Context to read first

1. `AGENTS.md` at the repository root - build commands, conventions, layout.
2. `docs/` - design notes and the admin research document.
3. `app/controllers/admin/` and `app/views/admin/` - what the console already
   has, so you extend it instead of duplicating it.

## Setup

The app uses SQLite and the test suite is the contract for every change:

```
bin/setup          # only if dependencies are missing
bin/rails test     # must end with 0 failures, 0 errors
```

If Ruby or the gems are missing, install them first. Do not skip the test run.

## What to build this run

Pick the **next unbuilt item** from the backlog below, in order. Build one
substantial feature (or finish a partially built one) - not several half-done
ones. If you finish early, start the next item.

Backlog, highest value first:

1. **Enforcement history ("rap sheet") on the account record.** A durable log of
   every moderation action taken against an account - warnings, suspensions,
   bans, verifications, role changes - with actor, reason, timestamp and
   duration. Read it from the existing `AuditLog` where possible rather than
   adding a parallel table, so the trail stays single-sourced.
2. **Warnings and a strike ladder.** A `warn` action that records a reason and
   notifies the member, plus a running strike count shown on the account record.
   Escalating consequences must be visible to the operator before they act.
3. **Internal staff notes on an account.** Private, timestamped, attributed
   notes that never reach the public site, distinct from the existing tag note.
4. **Appeals queue.** Members contest a ban or suspension; the appeal is a queue
   item an operator resolves with an outcome (upheld / reversed / modified) and
   a rationale. A reviewer other than the original actor should be able to take
   it - note the separation-of-duties rule in the code.
5. **Verification request queue.** Pending requests for the verified badge with
   approve/deny and a reason.
6. **Blocked terms / filters.** An operator-managed list of terms that flags or
   hides matching posts, with the effect stated plainly on the screen.
7. **Bulk actions on the accounts list.** Select many accounts and apply one
   action, with a confirmation step that states the exact blast radius, because
   bulk destructive actions are hard to reverse.
8. **Case linking.** Let an operator open a case for an account or post, link
   related reports to it, and record a decision.

## Rules that must not be broken

* **The owner account is untouchable from the outside.** `may_manage?` in
  `AdminController` is the central guard - every mutating action must honour it.
  Do not weaken or bypass it.
* **Every mutating action is audited** through `audit!` with a meaningful target
  and detail.
* **Every new page declares its permission key** and is registered in
  `Permission::KEYS` plus the role grants in `RoleBootstrapper`, so a moderator
  only reaches what they hold.
* **Destructive actions are POST** and confirmed, never a bare link.
* **The panel keeps its own stylesheet** (`admin-ops.css`) and does not load the
  consumer timeline's CSS.
* Follow the existing code style: comments explain *why*, not *what*; no
  redundant comments.

## Tests

Every feature ships with tests in `test/integration/`. Cover the happy path and
the guard: who is refused, and what the database looks like afterwards. Add new
pages to `OWNER_PAGES` in `admin_pages_test.rb`.

Run the full suite before committing. If a test fails, fix the code - never
delete or weaken an assertion to make it pass.

## Finish

1. `bin/rails test` - must be green.
2. Commit with a descriptive message explaining the why, ending with:
   `Co-authored-by: openhands <openhands@all-hands.dev>`
3. Push to `redesign/2019-twitter-and-admin-console` using `$GITHUB_TOKEN`:
   `git push https://${GITHUB_TOKEN}@github.com/loololloolloo/twitter.git HEAD:redesign/2019-twitter-and-admin-console`
   If the push is rejected as non-fast-forward, another run committed first:
   `git pull --rebase` and push again. Resolve any conflict by keeping both
   features working, then re-run the tests.
   If the token is unavailable, stop after committing locally and report that
   the push failed - do not force anything.
4. Report: what you built, the test counts, and the commit sha.
