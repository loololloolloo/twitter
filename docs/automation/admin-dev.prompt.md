# Nightly admin-console development

You are continuing development of a Rails 8.1 / Ruby 3.3 Twitter clone. The
repository has already been cloned into your workspace. Work only on the branch
`redesign/2019-twitter-and-admin-console`. Never commit to `main`.

## Budget: this is the part that used to fail

Earlier runs of this automation died at the 30-minute wall with no commit,
because they tried to do setup, a feature, the whole test suite and a push, and
then started a second item. Every run was killed and the automation was
auto-paused for five consecutive failures.

Follow these rules so a run always lands something:

* Do the **setup and a quick sanity check first**, then build **exactly one**
  item from the backlog below. One.
* **Commit and push as soon as your one item is green.** Do not wait until the
  end to push, and do not start a second backlog item in the same run. A clean
  commit that lands beats a larger uncommitted change that gets killed.
* If you can see you are running low on time, stop adding scope, finish the
  tests for what you have, commit, and push. A partial feature that is green and
  committed is the correct outcome.
* Never leave the branch red. If you cannot make a test pass, revert that part
  and commit the rest.
* If setup itself eats the budget (missing Ruby, missing gems), just leave the
  workspace ready and report that - do not attempt a feature.

## Context to read first

1. `AGENTS.md` at the repository root - build commands, conventions, layout.
2. `docs/admin-panel-research.md` - the industry research behind this backlog.
3. `docs/2019-audit.md` - the consumer-site fidelity audit.
4. `app/controllers/admin/` and `app/views/admin/` - what the console already
   has, so you extend it instead of duplicating it.

## Setup

```
bin/setup          # only if dependencies are missing
bin/rails test     # must end with 0 failures, 0 errors
```

If Ruby or the gems are missing, install them first. Do not skip the test run.

## Backlog

Work them in order. Each item names the convention it comes from so you build
the realistic version rather than a generic CRUD screen.

### Already built - do not rebuild

The enforcement history, warnings with a strike ladder, and internal staff notes
are done. Read them before you touch the account record.

### Next up

1. **Appeals queue.** A member contests a ban or suspension; the appeal is a
   queue item an operator resolves as upheld / reversed / modified with a
   rationale. Enforce separation of duties: the operator who imposed the
   sanction cannot be the one who decides the appeal, and the screen must say so
   when the current operator is barred. Real appeals handling is a distinct
   second-level workstream, not a reopen of the first decision.

2. **Verification request queue.** Pending requests for the verified badge, with
   approve/deny and a reason. Approving is what grants the badge; show the
   requester's account signals next to the decision so it is not a blind click.

3. **Blunt-name account toggles.** The leaked 2020 Twitter Agent Tool showed
   exactly this style: **Search Blacklist**, **Trends Blacklist**, **Do Not
   Amplify**. Implement them as named toggles whose effect on the user is stated
   plainly on the screen, even when that effect is invisible to the member.
   These are per-account state, audited like any other change.

4. **Elevated-handling flag.** Meta's Cross-Check existed to mark "this account
   is handled differently". Add an explicit, visible flag on the account that
   routes it to elevated review, with a caution banner above the action
   controls - not below them - and a reason recorded when it is set.

5. **Blocked terms / filters.** An operator-managed list of terms that flags or
   hides matching posts. The screen must state the effect of each mode in plain
   words, because "flag" and "hide" are very different blast radii. Rebuild the
   matcher when the list changes; do not rescan the world on every request.

6. **Bulk actions on the accounts list.** Select many accounts and apply one
   action, with a confirmation step that states the exact blast radius
   ("this will suspend 37 accounts"). Bulk destructive actions are hard to
   reverse, so the confirmation is the feature, not a formality.

7. **Case linking.** Open a case for an account or post, link related reports to
   it, and record a decision. A case is what turns a pile of reports into one
   investigation.

8. **Four-eyes approval on the highest-impact actions.** Permanent suspension,
   email change, and handle release should require a **second operator** to
   approve: the initiator's request sits pending, a different operator approves
   or rejects it, and both actors are recorded. The four-eyes principle is a
   standard internal control precisely because a single insider with tool access
   was the 2020 failure mode. The approver must be a different user than the
   initiator - enforce that in the model, not just the UI.

9. **Search by raw contact data.** The 2020 attackers wanted registered email
   and phone. Operators legitimately need to look accounts up that way too, so
   support it - with the lookup audited, including who searched for what.

10. **Saved queue views.** Operators work the same slices repeatedly. Let them
    save a filter (state, category, age, risk) as a named view on the queue.
    Every operator seeing the same default view is a real source of wasted time.

11. **Evidence and data export.** Produce a per-account export for a legal hold
    or data request: the account record, its posts, and its enforcement history,
    as a downloadable file. Every export is audited with the requester and the
    reason. This is a recurring, real obligation, not a nicety.

12. **Enforcement templates (macros).** Canned action+reason combinations an
    operator applies in one step, so the same violation is always described the
    same way. Reduces inconsistent messaging more than training does.

13. **Reversal of a moderation action.** Any enforcement action should be
    reversible with a recorded reason, and the reversal should be visible in the
    history next to the original action - not a silent delete of the row.

14. **Sockpuppet / duplicate detection.** Surface accounts that share signup
    signals (email pattern, signup window, similar handles) so an operator can
    see a cluster. Show it as a hint with the underlying signals, never as an
    automatic verdict.

15. **Risk-ordered queue triage.** Reports and posts should carry a computed
    priority so the queue can be worked highest-risk-first rather than
    oldest-first, with the ordering factors visible to the operator.

16. **Shift handover digest.** One screen summarising what is open, what changed
    recently, and what needs attention next - the thing an operator reads when
    they sit down at the start of a shift.

17. **Moderator wellness controls.** Interactive blurring for sensitive media
    plus a working-hours/break reminder. Research on moderation tooling found
    blurring reduces harm exposure without hurting accuracy, and the research
    doc notes moderator safety tools as a category. Keep it honest: blurring is
    a default the operator can unblur deliberately, not a permanent block.

18. **Immutable audit integrity.** The audit trail is the control that makes
    broad tool access tolerable, so it should be tamper-evident. Add a hash
    chain (each row commits to the previous) and a verification screen that
    reports whether the chain is intact.

19. **Permission-change review.** Role and permission changes are the most
    sensitive thing in the panel, because they grant the tool access that
    everything else depends on. Give them their own review surface with the
    before/after capability diff.

20. **Appeal-rate and overturn metrics.** Which decisions get overturned, by
    category and by operator, shown as counts. Overturn rate is the standard
    quality signal for a moderation team; it must be visible without a data
    warehouse.

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
* **Separation of duties is enforced in code**, not by convention: an operator
  cannot approve their own request, decide their own appeal, or review a change
  they made.
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

## If the admin backlog is exhausted

Switch to 2019 Twitter web fidelity on the consumer site. Audit each page
(`home`, `explore`, `notifications`, `messages`, `bookmarks`, `lists`, profile,
`settings`) against the 2019 web client and fix what is inaccurate. Known gaps
to start from:

* The right rail has no "What's happening" heading above trends; 2019 titled it
  exactly that, with the trends list nested underneath.
* The rail search box sits in its own card; 2019 kept it as a sticky search bar
  at the top of the rail column, separate from the trends card.
* "Show more" in the trends card should link to the trends screen.
* The rail About card is a 2019 element only in condensed form: the footer
  links are correct, but the card should not carry prose.

Record each finding in `docs/2019-audit.md` with the page, what 2019 did, and
what the code does now, so the audit is resumable across runs.
