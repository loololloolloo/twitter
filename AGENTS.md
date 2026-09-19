# AGENTS.md

Project memory for this repository. Read this first.

## What this is

A 1:1 replica of classic Twitter/X (roughly the 2014-2016 UI) built in Rails.
Real SQLite data: no placeholder users. The first account to sign up becomes
the owner and holds every permission.

## Layout

- Rails app at the repository root. Ruby 3.3, Rails 8.1, vendored bundle.
- Dev server: `http://localhost:12000`.
- App code lives under `app/`; DB under `storage/`.
- Uploaded avatars are written to `public/uploads/avatars/`.

## Commands

- Test everything: `./bin/bundle exec rails test`
- One test file: `./bin/bundle exec rails test test/integration/<name>_test.rb`
- Ruby one-off: `./bin/bundle exec rails runner script.rb`
  - Put the script in a file. Inline `runner` strings with quotes or `#{}` are
    fragile in this shell and often fail to parse.
- Console: `./bin/bundle exec rails console`
- Serve both ports: `./bin/serve`
  - This is the command to reach for. Both forwarded hosts (`work-1` on 12000,
    `work-2` on 12001) must be listening or the platform reports "Bad Gateway"
    on whichever one is down, so one port is not enough.
  - The script reinstalls Ruby if the reset removed it, then starts each port
    that is not already answering and waits until it responds.

## A fresh database has no roles until you seed it

`bin/setup` and `db:prepare` load the schema but never run `db/seeds.rb`, so a
database created after a reset has empty `roles`, `permissions`,
`role_permissions` and `site_settings` tables. Signup then dies in
`RegistrationsController#create` with
`ActiveRecord::RecordNotFound: Couldn't find Role with [WHERE "roles"."name" = ?]`,
because the lookup for the first account's owner role finds nothing.

Run `./bin/bundle exec rails db:seed` (idempotent, via `RoleBootstrapper`)
before anyone signs up. Symptom to recognise: every lookup that joins roles
fails and no account can be created.

## Ruby install can vanish on a session reset

A session reset removes the system Ruby: `env: 'ruby': No such file or
directory`, with `/usr/bin/ruby` and `/usr/lib/ruby` both gone. It has happened
more than once. The app's vendored gems (`vendor/bundle/ruby/3.3.0`) survive,
so only the interpreter needs reinstalling. `openhands` has passwordless sudo.

`./bin/serve` handles this automatically. To do it by hand:

```
sudo mkdir -p /var/lib/apt/lists/partial
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ruby3.3 ruby3.3-dev
```

The `mkdir` matters: the reset also removes `/var/lib/apt/lists/partial`, and
without it `apt-get update` fails with "List directory ... is missing".

Debian trixie ships 3.3.8, which matches the vendored bundle, and `bundler`
2.5.22 comes with it - the same version `bin/bundle` loads. After install,
`./bin/bundle check` should report the dependencies are satisfied and no
`bundle install` is needed.

## Parallel tests share files on disk, not just the database

`parallelize_setup` in `test/test_helper.rb` gives each worker its own database
and upload root. Two workers writing one file overwrite each other, and the
assertion then fails intermittently rather than always, which makes it easy to
dismiss as flake. Any new shared on-disk path a test writes to has to be
namespaced per worker there.

## Things that bite

- **Prefer real Rails integration tests over HTTP probe scripts.** A Python
  `requests` harness authenticating against the dev server is easy to get
  wrong: Rails masks CSRF tokens, so scraping `authenticity_token` out of the
  rendered HTML yields several distinct values and the POST fails with
  "Can't verify CSRF token authenticity." Tests in `test/integration/` use the
  framework's own session handling and are the reliable way to exercise POSTs.
- **HTTP probe scripts are one-shot.** The dev server caches and the DB moves
  under you; a retweet created after a page was fetched will not be in that
  fetch. Re-request after mutating data.
- **Foreign keys are enforced.** Deleting a user requires clearing, in order:
  `likes` (by `user_id` and by the user's `tweet_id`s), `notifications` (by
  `user_id`, `actor_id`, and `tweet_id`), `follows` (both columns),
  `dm_messages` (by `sender_id`, and by conversation), `dm_conversations`,
  `audit_logs.actor_id`, `sessions.user_id`, then the user's tweets.
  - `tweets.parent_id` and `tweets.retweet_of_id` are self-referencing, so
    tweets must be deleted leaves-first. `find_each` ignores `order`, so peel
    childless rows in a loop instead.
- **Assigning a picture removes the file it replaced.** `Uploads.remove` refuses
  any path that resolves outside `public/uploads`.

## Domain invariants

- `is_banned` + `ban_permanent` together mean a permanent ban. Timed bans have
  `ban_permanent: false` and a `ban_expires_at`, and clear themselves on read.
- A permanently banned profile is a notice, not a profile: show the
  permanent-ban label, force the default avatar, and hide display name, bio,
  location, website, verified badge, counts, and the follow/message actions.
  Its tweets are excluded by `Tweet.visible`, and its following/followers pages
  redirect back to the profile.
- The home feed shows original posts from everyone but retweets only from
  accounts the viewer follows. Retweets carry a "Retweeted by" flag naming the
  retweeter while the body stays credited to the original author.
- Signing up must not auto-follow anyone, and no account is ever driven to act
  on another's behalf.
- The owner account answers to nobody. `may_manage?` (in `AdminController`) is
  the single rule: an account with the owner role may only be changed by itself.
  Every mutating action in `Admin::UsersController` runs `require_may_manage!`,
  and the user page renders only the read-only card when it fails. Rank is not
  sufficient on its own — an admin outranks a plain member, so a rank-only role
  guard would let them demote the owner to `user` and take the instance.
- Internal staff notes (`StaffNote`) are private context, distinct from the
  single overwriting `users.tag_note`. They append, carry author and date, and
  change nothing about the account. Both the list and the form are gated on
  `users.notes` — do not gate only the form, or an operator holding `users.view`
  alone can read every note. Deleting a note is real, so the audit detail has
  to carry the text or the trail records a deletion with nothing to read.
- The browser tab says "Clever | Login" on every page and the favicon is the
  Clever mark, so the site does not announce itself in the tab strip, a
  bookmark list or a saved-session list. No view may set a page title of its
  own; the two layouts own it. A profile must not render "@user / Profile" and
  the panel must not render "Admin". `test/integration/browser_chrome_test.rb`
  sweeps both surfaces and fails if any view reintroduces `content_for :title`.
  The favicon files live in `public/clever-favicon*.png` and are linked
  directly rather than through the asset pipeline.
- Icons are inlined from `app/assets/images/icons` and recoloured with
  `fill: currentColor`, applied blanket-style to `.ico path/g/circle/rect` in
  all three sheets. A stroked icon that should stay hollow (the GIF box) must
  carry its own `style="fill:none"` on that element, because an inline style
  beats every stylesheet no matter which design is loaded.
- The composer's two media controls share a `.compose-tools` group which owns
  the `margin-right: auto`. Do not move that gap onto `.media-btn`, or the
  second control is pushed across to the Tweet button.
- Pushing: the `origin` URL originally embedded a token that has since died, so
  a bare `git push` stalled on a hidden password prompt and never landed the
  work. The remote is now the plain HTTPS URL with a `credential.helper` that
  reads `$GITHUB_TOKEN` at push time, so no secret is stored in `.git/config`.
  Use `GIT_TERMINAL_PROMPT=0 git push origin <branch>` and it either works or
  fails loudly. The automation clones fresh from `origin` each run, so anything
  left uncommitted is both invisible to the next run and lost on a reset -
  commit and push before finishing.
- Migrations must not be timestamped in the future: the sandbox clock can lag
  the date you would guess. A future timestamp makes `db:migrate` fail with
  `InvalidMigrationTimestampError`.