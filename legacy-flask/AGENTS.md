# AGENTS.md

## Project
Classic Twitter web client. Flask + SQLite, no ORM, no build step.
Lives in `/workspace/project`. Serves on port 12000.

## Commands
- Run: `python app.py` (background: `(python app.py > /tmp/server.log 2>&1 &)`)
- Restart after edits: templates and code are cached, so a restart is required.
  A bare `pkill -f "python app.py"` also kills the isolated test instance, so kill
  the exact PID instead: `ps -o pid,args -C python` then `kill <pid>`. To find
  which process holds a port or database, read `/proc/<pid>/environ` for
  `PORT`/`TWITTER_DB`.
- Rebuild DB: `python -c "import sqlite3,pathlib; c=sqlite3.connect('instance/twitter.db'); c.executescript(pathlib.Path('schema.sql').read_text()); c.commit()"`
- Inspect: `python -c "import sqlite3; c=sqlite3.connect('instance/twitter.db'); c.row_factory=sqlite3.Row; ..."`

## Architecture
- `app.py` — routes + Jinja globals (`icon`, `pic`, `bird`) + `linkify` filter
- `db.py` — `get_db()` (per-request `g.db`), PBKDF2 hashing, session handling,
  `permission_required()` decorator, validation helpers
- `schema.sql` — source of truth for schema and role/permission seeding

## Conventions and gotchas
- **Icons are inlined in Python, not via `<img>`.** The `icon()` global reads
  `static/assets/icons/<name>.svg` and injects the SVG so CSS can colour it.
  Use `{{ icon('heart') }}` directly. Do NOT reintroduce a Jinja macro file for
  these — Flask caches templates when debug is off, and macros defined via
  `{% import %}` were not visible inside error handlers.
- Every template gets `icon`, `pic`, `bird`, `me`, `my_permissions`,
  `site_name`, `max_len`, `my_tweet_count` from the context processor.
- `sessions` is a real table but login state is carried in a signed Flask cookie;
  `current_user()` caches on `g._resolved_user`. Always access via `D.current_user()`,
  never `g.user`.
- **Bans.** `users` carries `is_banned`, `ban_reason`, `ban_permanent`,
  `ban_expires_at`. `D.resolve_ban()` auto-lifts a timed ban whose expiry has
  passed, so reads through `current_user()`/`current_ban()` self-heal. The
  app-level `enforce_ban` gate redirects every non-exempt endpoint to `/banned`
  (`BAN_GATE_EXEMPT` lists the few that must stay reachable: login, logout,
  signup, static, and `/banned` itself). Admins cannot ban themselves or peers
  at/above their own rank.
- **Follower counts.** Every counted total adds `users.bonus_followers`
  (admin-granted, via `users.bot_followers`) to the real `follows` rows. Use
  `D.FOLLOWER_COUNT_SQL` in new queries so lists and profile tabs agree; it
  assumes the users table is aliased `u`.
- Additive columns are folded in by the `ensure_columns` before-request hook, so
  editing `schema.sql` is not required for an existing database to keep working.
- Column aliases matter: joining roles yields `role_rank` (and `role_name`); some
  older queries in `admin_delete_user` alias `rank` directly. Read the alias you wrote.
- `SECRET_KEY` is persisted in `instance/secret.key` so logins survive restarts;
  a random per-process key silently logs everyone out.
- Permission model: `permission_required("<key>")` on admin routes. Rank guards in
  `admin_set_role`/`admin_suspend`/`admin_delete_user` prevent escalation. Owner role
  permissions are intentionally immutable.

## Assets
Real SVGs only. Font Awesome 6.7.2 for UI icons and the classic Larry bird brand
(`brands/twitter`), simple-icons 9.21.0 as an alternate bird. Never hand-draw or
approximate these. Palette: `#1DA1F2` blue, `#14171A` dark, `#657786` gray,
`#AAB8C2` light gray, `#E1E8ED` extra light.

## Testing style
No test suite. Verify against the running server with `curl` cookie jars plus direct
SQLite queries, then confirm rendering in the browser. Check for 500s via
`grep -c " 500 " /tmp/server.log`.