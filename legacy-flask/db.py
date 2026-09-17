"""Shared database helpers, auth, and permission checks."""
import sqlite3
import os
import re
import secrets
import hashlib
import functools
from datetime import datetime, timedelta
from pathlib import Path

from flask import g, session, redirect, url_for, abort

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("TWITTER_DB") or (BASE_DIR / "instance" / "twitter.db"))

PERMISSION_KEYS = [
    "admin.access", "users.view", "users.suspend", "users.delete", "users.verify",
    "users.bot_followers", "users.roles", "users.permissions", "users.impersonate",
    "tweets.view",
    "tweets.delete", "tweets.pin", "reports.view", "reports.resolve",
    "settings.edit", "audit.view", "backup.export", "maintenance.run",
]

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{2,15}$")

# Follower counts everywhere add the admin-granted bonus so a profiled total
# matches the numbers shown on the user list and profile tabs.
FOLLOWER_COUNT_SQL = (
    "(SELECT COUNT(*) FROM follows f WHERE f.followee_id=u.id) + u.bonus_followers"
)


# ---------------------------------------------------------------- connection
def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


def close_db(exc=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def now():
    return datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")


# ---------------------------------------------------------------- passwords
def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000)
    return f"pbkdf2_sha256$200000${salt.hex()}${dk.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iters, salt_hex, hash_hex = stored.split("$")
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), int(iters))
        return secrets.compare_digest(dk.hex(), hash_hex)
    except (ValueError, AttributeError):
        return False


# ---------------------------------------------------------------- permissions
def user_permissions(user_id: int) -> set:
    rows = get_db().execute(
        """SELECT p.key FROM permissions p
           JOIN role_permissions rp ON rp.permission_id = p.id
           JOIN users u ON u.role_id = rp.role_id
           WHERE u.id = ?""",
        (user_id,),
    ).fetchall()
    return {r["key"] for r in rows}


def has_permission(user, key: str) -> bool:
    if not user:
        return False
    return key in g.get("permissions", set())


def permission_required(key: str):
    """Decorator: requires login plus a specific permission."""
    def decorator(view):
        @functools.wraps(view)
        def wrapper(*a, **kw):
            if not current_user():
                return redirect(url_for("login"))
            if not has_permission(current_user(), key):
                abort(403)
            return view(*a, **kw)
        return wrapper
    return decorator


def role_permissions(role_id: int) -> set:
    rows = get_db().execute(
        """SELECT p.key FROM permissions p
           JOIN role_permissions rp ON rp.permission_id = p.id
           WHERE rp.role_id = ?""",
        (role_id,),
    ).fetchall()
    return {r["key"] for r in rows}


def role_counts() -> dict:
    """Map permission key -> number of roles holding it (for the admin UI)."""
    rows = get_db().execute(
        """SELECT p.key, COUNT(rp.role_id) AS n FROM permissions p
           LEFT JOIN role_permissions rp ON rp.permission_id = p.id
           GROUP BY p.key"""
    ).fetchall()
    return {r["key"]: r["n"] for r in rows}


# ---------------------------------------------------------------- auth
def resolve_ban(row):
    """Return the active ban for a user row, or None.

    A timed ban that has already elapsed is lifted here so a banned account
    regains access on its own without an admin having to intervene.
    """
    if row is None or "is_banned" not in row.keys() or not row["is_banned"]:
        return None
    if not row["ban_permanent"]:
        expires = row["ban_expires_at"]
        if not expires:
            # A timed ban with no end date is treated as permanent.
            get_db().execute("UPDATE users SET ban_permanent = 1 WHERE id = ?", (row["id"],))
            get_db().commit()
            return {
                "reason": row["ban_reason"] or "",
                "permanent": True,
                "expires_at": None,
            }
        if expires <= now():
            get_db().execute(
                """UPDATE users SET is_banned = 0, ban_reason = '',
                          ban_permanent = 0, ban_expires_at = NULL WHERE id = ?""",
                (row["id"],),
            )
            get_db().commit()
            return None
    return {
        "reason": row["ban_reason"] or "",
        "permanent": bool(row["ban_permanent"]),
        "expires_at": row["ban_expires_at"],
    }


def current_user():
    if "_resolved_user" in g:
        return g._resolved_user
    g._resolved_user = None
    g.permissions = set()
    g.ban = None
    uid = session.get("user_id")
    if uid:
        row = get_db().execute(
            """SELECT u.*, r.name AS role_name, r.rank AS role_rank
               FROM users u JOIN roles r ON r.id = u.role_id
               WHERE u.id = ?""",
            (uid,),
        ).fetchone()
        if row and not row["is_suspended"]:
            g._resolved_user = row
            g.permissions = user_permissions(row["id"])
            # Banned accounts keep their session; the ban screen is shown
            # instead of the site so the reason and duration stay visible.
            g.ban = resolve_ban(row)
        elif row:
            # Account was suspended mid-session: drop the session entirely.
            session.clear()
    return g._resolved_user


def current_ban():
    """The active ban for the signed-in user, if any."""
    current_user()
    return g.get("ban")


def login_user(user_id: int):
    token = secrets.token_urlsafe(32)
    db = get_db()
    db.execute(
        "INSERT INTO sessions (token, user_id, expires_at) VALUES (?,?,?)",
        (token, user_id, (datetime.utcnow() + timedelta(days=30)).strftime("%Y-%m-%d %H:%M:%S")),
    )
    db.execute("UPDATE users SET last_login_at = ? WHERE id = ?", (now(), user_id))
    db.commit()
    session["user_id"] = user_id
    session.permanent = True


def logout_user():
    session.clear()
    g._resolved_user = None
    g.permissions = set()


def audit(actor_id, action, target="", detail=""):
    db = get_db()
    db.execute(
        "INSERT INTO audit_log (actor_id, action, target, detail) VALUES (?,?,?,?)",
        (actor_id, action, target, detail),
    )
    db.commit()


# ---------------------------------------------------------------- validation
def validate_username(username: str):
    if not username or not USERNAME_RE.match(username):
        return "Username must be 2-15 characters, letters/numbers/underscore only."
    if get_db().execute("SELECT 1 FROM users WHERE username = ?", (username,)).fetchone():
        return "That username is already taken."
    return None


def validate_email(email: str):
    if not email or "@" not in email or "." not in email.split("@")[-1]:
        return "Please enter a valid email address."
    if get_db().execute("SELECT 1 FROM users WHERE email = ?", (email,)).fetchone():
        return "That email is already registered."
    return None


def find_mentions(text: str):
    return {m.lower() for m in re.findall(r"@([A-Za-z0-9_]{2,15})", text or "")}


def find_hashtags(text: str):
    return {m.lower() for m in re.findall(r"#([A-Za-z0-9_]{1,50})", text or "")}


def get_setting(key: str, default: str = "") -> str:
    row = get_db().execute("SELECT value FROM site_settings WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default
