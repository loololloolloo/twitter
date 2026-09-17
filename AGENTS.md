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
- Seeded population is 5,000 bot accounts plus whatever humans sign up.
- Generated bot avatars are written to `public/uploads/avatars/bot_<seed>.svg`.

## Commands

- Test everything: `./bin/bundle exec rails test`
- One test file: `./bin/bundle exec rails test test/integration/<name>_test.rb`
- Ruby one-off: `./bin/bundle exec rails runner script.rb`
  - Put the script in a file. Inline `runner` strings with quotes or `#{}` are
    fragile in this shell and often fail to parse.
- Console: `./bin/bundle exec rails console`

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
- **Bot avatars are intentionally partial.** `AvatarGenerator.generate` returns
  nil for roughly a third of accounts (rng > 0.68) so the population looks
  real; ~3,400 of 5,000 bots have a picture. Nil `avatar_path` is expected and
  renders the default egg, not a bug.
- **Remote avatar import.** `RemoteAvatar` fetches pictures from DiceBear,
  Robohash, or Picsum for accounts that have none. It is the only place the app
  makes an outbound request driven by admin input, so it resolves the host and
  refuses private/loopback/link-local addresses, only follows one redirect to a
  pre-declared host, caps size and time, and sniffs the leading bytes before
  saving (SVG is rejected because it can carry script). Do not add a provider
  by interpolating a URL from user input; add it to `RemoteAvatar::PROVIDERS`
  with a `build` lambda and an explicit host allowlist.
  - Admin UI is gated on the `users.avatar` permission; `bots:avatars` is the
    bulk equivalent for a shell. Both default to accounts with no picture, so
    re-running is safe and idempotent.
  - Assigning a picture removes the file it replaced via `Uploads.remove`,
    which refuses any path that resolves outside `public/uploads`.

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
- Bots act on their own schedule (`BotEngine.tick`) and may follow, reply to,
  like, and retweet humans. A human account must never be driven to act by the
  engine, and signing up must not auto-follow anyone.
- Seed data should never give a human account follows it did not perform.