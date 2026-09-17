# Twitter

A local implementation of the classic Twitter web client, built on Flask
and SQLite. The first account to sign up automatically becomes the instance
**owner** with every administrative permission.

## Running

```bash
python app.py          # serves on http://0.0.0.0:12000
```

The database lives at `instance/twitter.db`. If it does not exist, create it with:

```bash
python -c "import sqlite3,pathlib; \
c=sqlite3.connect('instance/twitter.db'); \
c.executescript(pathlib.Path('schema.sql').read_text()); c.commit()"
```

## First user becomes owner

`signup()` counts existing rows in `users`. When the count is zero the new account
is assigned the `owner` role, which holds every row in `permissions` (17). Every
later signup gets the `user` role with no administrative permissions. The event is
recorded in `audit_log`.

## Roles

| Role | Rank | Permissions |
| --- | --- | --- |
| owner | 100 | all 17, not editable |
| admin | 50 | 12 (moderation, not settings/roles) |
| moderator | 25 | 5 (review only) |
| user | 1 | none |

Privilege guards: an actor cannot assign a role at or above their own rank, cannot
suspend or delete a user whose rank is >= their own, and the owner account can
never be deleted. The owner role's permission set cannot be edited.

## Features

Timeline of followed accounts plus your own, compose with 140-character counter,
replies, retweets, likes, follows, notifications (like/reply/retweet/follow/mention),
direct messages, profiles with avatar and banner upload, search/discover, and a full
admin panel (dashboard, users, roles & permissions matrix, tweet moderation, audit
log, site settings, SQL backup export).

The backup export round-trips: the emitted SQL restores into an empty database with
roles, permissions and the owner intact.

## Assets

All icons are the genuine original SVGs, not redrawn approximations:

- `assets/icons/twitter-bird.svg` — Font Awesome 6.7.2 brand `twitter` (the classic Larry bird)
- `assets/icons/x-logo.svg` — Font Awesome 6.7.2 brand `x-twitter`
- `assets/icons/*.svg` — Font Awesome 6.7.2 solid icons (heart, retweet, comment, user,
  house, bell, envelope, magnifying-glass, gear, right-from-bracket, chart-simple,
  shield-halved, ellipsis, image)
- `assets/icons/twitter-bird-simple.svg` — simple-icons 9.21.0

Palette follows the official brand spec: Twitter Blue `#1DA1F2`, Dark Gray `#14171A`,
Medium Gray `#657786`, Light Gray `#AAB8C2`, Extra Light Gray `#E1E8ED`.

Icons are inlined by the `icon()` Jinja global (`app.py`), which reads the SVG file
and injects it, so they inherit CSS colour.

## Files

- `app.py` — Flask app and all routes
- `db.py` — connection, password hashing, sessions, permission helpers
- `schema.sql` — tables, roles, permissions, seed settings
- `templates/` — pages, `templates/admin/` — admin panel
- `static/css/twitter.css` — classic styling
- `static/js/twitter.js` — character counter and like buttons