"""Classic Twitter web client."""
import os
import re
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

from flask import (
    Flask, render_template, request, redirect, url_for, session,
    g, abort, flash, jsonify, send_from_directory, make_response,
)

import db as D

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_ROOT = BASE_DIR / "static" / "uploads"

app = Flask(__name__)

# Persist the secret key so logins survive a restart.
_secret_file = BASE_DIR / "instance" / "secret.key"
if os.environ.get("TWITTER_SECRET"):
    _secret = os.environ["TWITTER_SECRET"]
elif _secret_file.exists():
    _secret = _secret_file.read_text().strip()
else:
    _secret_file.parent.mkdir(parents=True, exist_ok=True)
    _secret = os.urandom(32).hex()
    _secret_file.write_text(_secret)
    os.chmod(_secret_file, 0o600)
app.config["SECRET_KEY"] = _secret
app.config["PERMANENT_SESSION_LIFETIME"] = 30 * 24 * 3600
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024
app.teardown_appcontext(D.close_db)

ALLOWED_IMAGE_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp"}


@app.before_request
def ensure_columns():
    """Add columns introduced after a database was first created.

    schema.sql is applied by hand, so existing databases need the additive
    columns folded in on startup rather than being rebuilt from scratch.
    """
    if getattr(app, "_columns_ready", False):
        return None
    db = D.get_db()
    existing = {r["name"] for r in db.execute("PRAGMA table_info(users)")}
    if "bonus_followers" not in existing:
        db.execute("ALTER TABLE users ADD COLUMN bonus_followers INTEGER NOT NULL DEFAULT 0")
        db.commit()
    app._columns_ready = True
    return None


@app.template_filter("display_url")
def display_url(url):
    """Trim a URL for display, the way the classic client did."""
    return re.sub(r"^https?://(www\.)?", "", url or "").rstrip("/")


@app.template_filter("joined")
def joined(value):
    """'Joined March 2012' rather than a bare timestamp."""
    try:
        dt = datetime.strptime(str(value)[:19], "%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        return value
    return dt.strftime("%B %Y")


@app.template_filter("linkify")
def linkify(text):
    """Escape HTML, then link @mentions and #hashtags."""
    from markupsafe import Markup, escape
    out = str(escape(text or ""))
    out = re.sub(r"@([A-Za-z0-9_]{2,15})",
                 r'<a class="mention" href="/u/\1">@\1</a>', out)
    out = re.sub(r"#([A-Za-z0-9_]{1,50})",
                 r'<a class="hashtag" href="/explore?q=%23\1">#\1</a>', out)
    return Markup(out)


def _icon(name):
    """Inline a real SVG from static/assets/icons (Font Awesome 6.7.2)."""
    from markupsafe import Markup
    path = BASE_DIR / "static" / "assets" / "icons" / f"{name}.svg"
    if not path.exists():
        return Markup("")
    svg = path.read_text()
    svg = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    svg = svg.replace("<svg ", '<svg class="ico" ', 1)
    return Markup(svg)


def _pic(path, size=48):
    """Avatar image, or the user glyph when no picture is set."""
    from markupsafe import Markup
    if path:
        return Markup(f'<img class="avatar avatar-{size}" '
                      f'src="/static/uploads/{path}" alt="">')
    return Markup(f'<span class="avatar avatar-{size} avatar-empty">{_icon("user")}</span>')


def _bird():
    from markupsafe import Markup
    return Markup('<img src="/static/assets/icons/twitter-bird.svg" alt="Twitter">')


app.jinja_env.globals.update(icon=_icon, pic=_pic, bird=_bird)


# ------------------------------------------------------------------ helpers
def top_trends(limit=8):
    """Most-used hashtags across recent tweets."""
    rows = D.get_db().execute(
        "SELECT body FROM tweets WHERE is_deleted=0 AND body LIKE '%#%' ORDER BY id DESC LIMIT 500"
    ).fetchall()
    counts = {}
    for r in rows:
        for tag in D.find_hashtags(r["body"]):
            counts[tag] = counts.get(tag, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:limit]


def humanize_until(expires_at):
    """Render a ban end date as 'in 2 days' / 'in about 3 hours'."""
    if not expires_at:
        return ""
    fmt = "%Y-%m-%d %H:%M:%S"
    try:
        end = datetime.strptime(expires_at[:19], fmt)
    except ValueError:
        return expires_at
    delta = end - datetime.utcnow()
    # Round up so a ban set for "3 days" reads as 3 days rather than 2 days
    # 23:59:59 from the fraction of a second that elapses before rendering.
    secs = int(delta.total_seconds() + 0.999)
    if secs <= 0:
        return "moments from now"
    days, rem = divmod(secs, 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    if days:
        return f"{days} day{'s' if days != 1 else ''}"
    if hours:
        return f"{hours} hour{'s' if hours != 1 else ''}"
    if minutes:
        return f"{minutes} minute{'s' if minutes != 1 else ''}"
    return "less than a minute"


@app.context_processor
def inject_globals():
    user = D.current_user()
    counts = {"tweets": 0, "following": 0, "followers": 0}
    if user:
        db = D.get_db()
        counts["tweets"] = db.execute(
            "SELECT COUNT(*) AS n FROM tweets WHERE user_id=? AND is_deleted=0 AND parent_id IS NULL",
            (user["id"],)).fetchone()["n"]
        counts["following"] = db.execute(
            "SELECT COUNT(*) AS n FROM follows WHERE follower_id=?", (user["id"],)).fetchone()["n"]
        counts["followers"] = db.execute(
            "SELECT COUNT(*) AS n FROM follows WHERE followee_id=?",
            (user["id"],)).fetchone()["n"] + (user["bonus_followers"] or 0)
    return {
        "me": user,
        "my_tweet_count": counts["tweets"],
        "my_counts": counts,
        "trends": top_trends(),
        "my_permissions": g.get("permissions", set()),
        "site_name": D.get_setting("site_name", "Twitter"),
        "max_len": int(D.get_setting("max_tweet_length", "140")),
    }


BAN_GATE_EXEMPT = {"banned", "logout", "static", "login"}


@app.before_request
def enforce_ban():
    """Hold banned accounts on the ban screen instead of signing them out.

    Every other page redirects to /banned so the reason, duration and the log
    out button are always reachable.
    """
    if request.endpoint in BAN_GATE_EXEMPT or request.endpoint is None:
        return None
    if D.current_ban():
        return redirect(url_for("banned"))
    return None


def require_login():
    if not D.current_user():
        return redirect(url_for("login"))
    return None


def users_where(search="", role_filter="", status=""):
    sql = f"""SELECT u.*, r.name AS role_name, r.rank AS role_rank,
                    (SELECT COUNT(*) FROM tweets t WHERE t.user_id=u.id AND t.is_deleted=0) AS tweet_count,
                    {D.FOLLOWER_COUNT_SQL} AS follower_count,
                    (SELECT COUNT(*) FROM follows f WHERE f.follower_id=u.id) AS following_count
             FROM users u JOIN roles r ON r.id=u.role_id WHERE 1=1"""
    args = []
    if search:
        sql += " AND (u.username LIKE ? OR u.display_name LIKE ? OR u.email LIKE ?)"
        args += [f"%{search}%"] * 3
    if role_filter:
        sql += " AND r.name = ?"
        args.append(role_filter)
    if status == "suspended":
        sql += " AND u.is_suspended = 1"
    elif status == "banned":
        sql += " AND u.is_banned = 1"
    elif status == "active":
        sql += " AND u.is_suspended = 0 AND u.is_banned = 0"
    sql += " ORDER BY r.rank DESC, u.created_at ASC"
    return D.get_db().execute(sql, args).fetchall()


# ------------------------------------------------------------------ auth
@app.route("/")
def index():
    if not D.current_user():
        return redirect(url_for("login"))
    return redirect(url_for("home"))


@app.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        username = (request.form.get("username") or "").strip()
        display_name = (request.form.get("display_name") or "").strip() or username
        email = (request.form.get("email") or "").strip()
        password = request.form.get("password") or ""
        confirm = request.form.get("confirm") or ""

        errors = []
        err = D.validate_username(username)
        if err:
            errors.append(err)
        err = D.validate_email(email)
        if err:
            errors.append(err)
        if len(password) < 8:
            errors.append("Password must be at least 8 characters.")
        if password != confirm:
            errors.append("Passwords do not match.")

        if errors:
            for e in errors:
                flash(e, "error")
            return render_template("signup.html", form=request.form)

        db = D.get_db()
        # First account ever created becomes the owner with every permission.
        is_first = db.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"] == 0
        role_name = "owner" if is_first else "user"
        role_id = db.execute("SELECT id FROM roles WHERE name = ?", (role_name,)).fetchone()["id"]

        cur = db.execute(
            """INSERT INTO users (username, display_name, email, password_hash, role_id)
               VALUES (?,?,?,?,?)""",
            (username, display_name, email, D.hash_password(password), role_id),
        )
        uid = cur.lastrowid
        db.commit()

        D.audit(uid, "user.signup", f"user:{uid}",
                f"@{username} registered as {role_name}"
                + (" (first account - owner privileges granted)" if is_first else ""))

        if is_first:
            flash("Welcome, owner. You are the first account, so this instance is yours - "
                  "you have every administrative permission.", "success")
        else:
            flash(f"Welcome, @{username}.", "success")

        D.login_user(uid)
        return redirect(url_for("admin_panel") if is_first else url_for("home"))

    return render_template("signup.html", form={})


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        ident = (request.form.get("identifier") or "").strip()
        password = request.form.get("password") or ""
        row = D.get_db().execute(
            "SELECT * FROM users WHERE username = ? OR email = ?", (ident, ident)
        ).fetchone()
        if not row or not D.verify_password(password, row["password_hash"]):
            flash("Incorrect username or password.", "error")
            return render_template("login.html", form=request.form)
        if row["is_suspended"]:
            flash("This account has been suspended.", "error")
            return render_template("login.html", form=request.form)
        D.login_user(row["id"])
        return redirect(url_for("home"))
    if D.current_user():
        return redirect(url_for("home"))
    return render_template("login.html", form={})


@app.route("/banned")
def banned():
    me = D.current_user()
    if not me:
        return redirect(url_for("login"))
    ban = D.current_ban()
    if not ban:
        return redirect(url_for("home"))
    return render_template("banned.html", ban=ban,
                           until=humanize_until(ban["expires_at"]))


@app.route("/logout")
def logout():
    D.logout_user()
    return redirect(url_for("login"))


# ------------------------------------------------------------------ timeline
@app.route("/home")
def home():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    # Tweets from people I follow plus my own.
    rows = db.execute(
        """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                  ru.username AS rt_username, ru.display_name AS rt_display_name,
                  (SELECT COUNT(*) FROM likes l WHERE l.tweet_id = t.id) AS like_count,
                  (SELECT COUNT(*) FROM tweets c WHERE c.parent_id = t.id AND c.is_deleted=0) AS reply_count,
                  (SELECT COUNT(*) FROM tweets x WHERE x.retweet_of_id = t.id AND x.is_deleted=0) AS rt_count,
                  EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id = t.id AND l.user_id = ?) AS liked
           FROM tweets t
           JOIN users u ON u.id = t.user_id
           LEFT JOIN tweets rt ON rt.id = t.retweet_of_id
           LEFT JOIN users ru ON ru.id = rt.user_id
           WHERE t.is_deleted = 0
             AND (t.user_id = ? OR t.user_id IN
                  (SELECT followee_id FROM follows WHERE follower_id = ?))
           ORDER BY t.created_at DESC, t.id DESC
           LIMIT 60""",
        (me["id"], me["id"], me["id"]),
    ).fetchall()
    suggestions = db.execute(
        """SELECT u.* FROM users u
           WHERE u.id <> ? AND u.is_suspended = 0
             AND u.id NOT IN (SELECT followee_id FROM follows WHERE follower_id = ?)
           ORDER BY RANDOM() LIMIT 3""",
        (me["id"], me["id"]),
    ).fetchall()
    return render_template("home.html", tweets=rows, suggestions=suggestions,
                           heading="Home")


@app.route("/explore")
def explore():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    q = (request.args.get("q") or "").strip()
    db = D.get_db()
    # A bare token like "hello" should also match the hashtag form "#hello".
    like = f"%{q}%" if q.startswith("#") else f"%#{q}%"
    text_like = f"%{q}%"
    if q:
        rows = db.execute(
            """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                      (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                      (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count,
                      (SELECT COUNT(*) FROM tweets x WHERE x.retweet_of_id=t.id AND x.is_deleted=0) AS rt_count,
                      EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id=t.id AND l.user_id=?) AS liked
               FROM tweets t JOIN users u ON u.id=t.user_id
               WHERE t.is_deleted=0 AND t.parent_id IS NULL
                 AND (t.body LIKE ? OR t.body LIKE ? OR u.username LIKE ? OR u.display_name LIKE ?)
               ORDER BY t.created_at DESC LIMIT 60""",
            (me["id"], text_like, like, text_like, text_like),
        ).fetchall()
    else:
        rows = db.execute(
            """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                      (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                      (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count,
                      (SELECT COUNT(*) FROM tweets x WHERE x.retweet_of_id=t.id AND x.is_deleted=0) AS rt_count,
                      EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id=t.id AND l.user_id=?) AS liked
               FROM tweets t JOIN users u ON u.id=t.user_id
               WHERE t.is_deleted=0 AND t.parent_id IS NULL
               ORDER BY (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) DESC,
                        t.created_at DESC LIMIT 60""",
            (me["id"],),
        ).fetchall()
    return render_template("explore.html", tweets=rows, q=q)


@app.route("/notifications")
def notifications():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    rows = D.get_db().execute(
        """SELECT n.*, a.username AS actor_username, a.display_name AS actor_display_name,
                  a.avatar_path AS actor_avatar
           FROM notifications n LEFT JOIN users a ON a.id = n.actor_id
           WHERE n.user_id = ? ORDER BY n.created_at DESC, n.id DESC LIMIT 100""",
        (me["id"],),
    ).fetchall()
    D.get_db().execute("UPDATE notifications SET is_read=1 WHERE user_id=?", (me["id"],))
    D.get_db().commit()
    return render_template("notifications.html", items=rows)


@app.route("/messages")
def messages():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    convs = D.get_db().execute(
        """SELECT c.*,
                  CASE WHEN c.user_a=? THEN c.user_b ELSE c.user_a END AS other_id,
                  (SELECT body FROM dm_messages m WHERE m.conversation_id=c.id
                   ORDER BY m.id DESC LIMIT 1) AS last_body,
                  (SELECT created_at FROM dm_messages m WHERE m.conversation_id=c.id
                   ORDER BY m.id DESC LIMIT 1) AS last_at
           FROM dm_conversations c
           WHERE c.user_a=? OR c.user_b=?
           ORDER BY last_at DESC""",
        (me["id"], me["id"], me["id"]),
    ).fetchall()
    people = []
    for c in convs:
        u = D.get_db().execute("SELECT * FROM users WHERE id=?", (c["other_id"],)).fetchone()
        people.append({"conv": c, "user": u})
    return render_template("messages.html", people=people)


@app.route("/messages/<int:other_id>", methods=["GET", "POST"])
def conversation(other_id):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    other = db.execute("SELECT * FROM users WHERE id=?", (other_id,)).fetchone()
    if not other:
        abort(404)
    a, b = sorted((me["id"], other_id))
    conv = db.execute("SELECT * FROM dm_conversations WHERE user_a=? AND user_b=?", (a, b)).fetchone()
    if not conv:
        cur = db.execute("INSERT INTO dm_conversations (user_a,user_b) VALUES (?,?)", (a, b))
        db.commit()
        conv = db.execute("SELECT * FROM dm_conversations WHERE id=?", (cur.lastrowid,)).fetchone()
    if request.method == "POST":
        body = (request.form.get("body") or "").strip()
        if body:
            db.execute("INSERT INTO dm_messages (conversation_id,sender_id,body) VALUES (?,?,?)",
                       (conv["id"], me["id"], body))
            db.execute("INSERT INTO notifications (user_id,actor_id,kind,body) VALUES (?,?,?,?)",
                       (other_id, me["id"], "mention", "sent you a direct message"))
            db.commit()
        return redirect(url_for("conversation", other_id=other_id))
    msgs = db.execute(
        "SELECT * FROM dm_messages WHERE conversation_id=? ORDER BY id ASC", (conv["id"],)
    ).fetchall()
    return render_template("conversation.html", other=other, msgs=msgs)


# ------------------------------------------------------------------ tweets
@app.route("/compose", methods=["POST"])
def compose():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    body = (request.form.get("body") or "").strip()
    parent_id = request.form.get("parent_id") or None
    max_len = int(D.get_setting("max_tweet_length", "140"))
    if not body and not request.files.get("media"):
        flash("Your tweet is empty.", "error")
        return redirect(request.referrer or url_for("home"))
    if len(body) > max_len:
        flash(f"Tweets are limited to {max_len} characters.", "error")
        return redirect(request.referrer or url_for("home"))

    media_path = save_upload(request.files.get("media"), me["id"])
    db = D.get_db()
    cur = db.execute(
        "INSERT INTO tweets (user_id, body, parent_id, media_path) VALUES (?,?,?,?)",
        (me["id"], body, parent_id, media_path),
    )
    tweet_id = cur.lastrowid

    if parent_id:
        parent = db.execute("SELECT * FROM tweets WHERE id=?", (parent_id,)).fetchone()
        if parent and parent["user_id"] != me["id"]:
            db.execute("INSERT INTO notifications (user_id,actor_id,kind,tweet_id,body) VALUES (?,?,?,?,?)",
                       (parent["user_id"], me["id"], "reply", tweet_id, body[:120]))
    db.commit()

    for name in D.find_mentions(body):
        u = db.execute("SELECT id FROM users WHERE username = ?", (name,)).fetchone()
        if u and u["id"] != me["id"]:
            db.execute("INSERT INTO notifications (user_id,actor_id,kind,tweet_id,body) VALUES (?,?,?,?,?)",
                       (u["id"], me["id"], "mention", tweet_id, body[:120]))
    db.commit()

    if parent_id:
        return redirect(url_for("tweet_detail", tweet_id=parent_id))
    return redirect(request.referrer or url_for("home"))


def save_upload(file_storage, user_id):
    if not file_storage or not file_storage.filename:
        return None
    ext = Path(file_storage.filename).suffix.lower()
    if ext not in ALLOWED_IMAGE_EXT:
        return None
    import secrets as _s
    rel = f"media/{user_id}_{_s.token_hex(8)}{ext}"
    dest = UPLOAD_ROOT / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    file_storage.save(dest)
    return rel


@app.route("/tweet/<int:tweet_id>")
def tweet_detail(tweet_id):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    t = db.execute(
        """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified
           FROM tweets t JOIN users u ON u.id=t.user_id
           WHERE t.id=? AND t.is_deleted=0""", (tweet_id,)
    ).fetchone()
    if not t:
        abort(404)
    replies = db.execute(
        """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                  (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                  (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count,
                  0 AS rt_count,
                  EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id=t.id AND l.user_id=?) AS liked
           FROM tweets t JOIN users u ON u.id=t.user_id
           WHERE t.parent_id=? AND t.is_deleted=0 ORDER BY t.created_at ASC""",
        (me["id"], tweet_id),
    ).fetchall()
    like_count = db.execute("SELECT COUNT(*) AS n FROM likes WHERE tweet_id=?", (tweet_id,)).fetchone()["n"]
    rt_count = db.execute("SELECT COUNT(*) AS n FROM tweets WHERE retweet_of_id=? AND is_deleted=0", (tweet_id,)).fetchone()["n"]
    liked = db.execute("SELECT 1 FROM likes WHERE tweet_id=? AND user_id=?", (tweet_id, me["id"])).fetchone() is not None
    return render_template("tweet.html", tweet=t, replies=replies,
                           like_count=like_count, rt_count=rt_count, liked=liked)


@app.route("/tweet/<int:tweet_id>/delete", methods=["POST"])
def delete_tweet(tweet_id):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    t = db.execute("SELECT * FROM tweets WHERE id=?", (tweet_id,)).fetchone()
    if not t:
        abort(404)
    is_mine = t["user_id"] == me["id"]
    if not is_mine and not D.has_permission(me, "tweets.delete"):
        abort(403)
    db.execute("UPDATE tweets SET is_deleted=1 WHERE id=?", (tweet_id,))
    db.commit()
    D.audit(me["id"], "tweet.delete", f"tweet:{tweet_id}",
            "own tweet" if is_mine else "moderator action")
    return redirect(request.referrer or url_for("home"))


@app.route("/tweet/<int:tweet_id>/like", methods=["POST"])
def like_tweet(tweet_id):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    t = db.execute("SELECT * FROM tweets WHERE id=?", (tweet_id,)).fetchone()
    if not t:
        abort(404)
    existing = db.execute("SELECT 1 FROM likes WHERE user_id=? AND tweet_id=?",
                          (me["id"], tweet_id)).fetchone()
    if existing:
        db.execute("DELETE FROM likes WHERE user_id=? AND tweet_id=?", (me["id"], tweet_id))
    else:
        db.execute("INSERT INTO likes (user_id,tweet_id) VALUES (?,?)", (me["id"], tweet_id))
        if t["user_id"] != me["id"]:
            db.execute("INSERT INTO notifications (user_id,actor_id,kind,tweet_id,body) VALUES (?,?,?,?,?)",
                       (t["user_id"], me["id"], "like", tweet_id, ""))
    db.commit()
    if request.headers.get("Accept") == "application/json":
        n = db.execute("SELECT COUNT(*) AS n FROM likes WHERE tweet_id=?", (tweet_id,)).fetchone()["n"]
        return jsonify({"liked": not existing, "count": n})
    return redirect(request.referrer or url_for("home"))


@app.route("/tweet/<int:tweet_id>/retweet", methods=["POST"])
def retweet(tweet_id):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    t = db.execute("SELECT * FROM tweets WHERE id=?", (tweet_id,)).fetchone()
    if not t:
        abort(404)
    existing = db.execute(
        "SELECT 1 FROM tweets WHERE user_id=? AND retweet_of_id=? AND is_deleted=0",
        (me["id"], tweet_id)).fetchone()
    if existing:
        db.execute("UPDATE tweets SET is_deleted=1 WHERE user_id=? AND retweet_of_id=?",
                   (me["id"], tweet_id))
    else:
        db.execute("INSERT INTO tweets (user_id, body, retweet_of_id) VALUES (?,?,?)",
                   (me["id"], "", tweet_id))
        if t["user_id"] != me["id"]:
            db.execute("INSERT INTO notifications (user_id,actor_id,kind,tweet_id,body) VALUES (?,?,?,?,?)",
                       (t["user_id"], me["id"], "retweet", tweet_id, ""))
    db.commit()
    return redirect(request.referrer or url_for("home"))


# ------------------------------------------------------------------ profiles
@app.route("/u/<username>")
def profile(username):
    tab = request.args.get("tab", "tweets")
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    u = db.execute(
        "SELECT u.*, r.name AS role_name FROM users u JOIN roles r ON r.id=u.role_id WHERE u.username=?",
        (username,)).fetchone()
    if not u:
        abort(404)
    tweets = db.execute(
        """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                  (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                  (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count,
                  (SELECT COUNT(*) FROM tweets x WHERE x.retweet_of_id=t.id AND x.is_deleted=0) AS rt_count,
                  EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id=t.id AND l.user_id=?) AS liked
           FROM tweets t JOIN users u ON u.id=t.user_id
           WHERE t.user_id=? AND t.is_deleted=0 AND t.retweet_of_id IS NULL
           ORDER BY t.created_at DESC LIMIT 60""",
        (me["id"], u["id"])).fetchall()
    favorites = db.execute(
        """SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                  (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                  (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count,
                  (SELECT COUNT(*) FROM tweets x WHERE x.retweet_of_id=t.id AND x.is_deleted=0) AS rt_count,
                  EXISTS(SELECT 1 FROM likes l WHERE l.tweet_id=t.id AND l.user_id=?) AS liked
           FROM likes l JOIN tweets t ON t.id=l.tweet_id
           JOIN users u ON u.id=t.user_id
           WHERE l.user_id=? AND t.is_deleted=0
           ORDER BY l.created_at DESC LIMIT 60""",
        (me["id"], u["id"])).fetchall()
    media = db.execute(
        """SELECT * FROM tweets WHERE user_id=? AND is_deleted=0
             AND media_path IS NOT NULL AND media_path <> ''
           ORDER BY created_at DESC LIMIT 60""",
        (u["id"],)).fetchall()
    followers = db.execute(
        "SELECT COUNT(*) AS n FROM follows WHERE followee_id=?",
        (u["id"],)).fetchone()["n"] + (u["bonus_followers"] or 0)
    following = db.execute("SELECT COUNT(*) AS n FROM follows WHERE follower_id=?", (u["id"],)).fetchone()["n"]
    is_following = db.execute("SELECT 1 FROM follows WHERE follower_id=? AND followee_id=?",
                              (me["id"], u["id"])).fetchone() is not None
    return render_template("profile.html", u=u, tweets=tweets,
                           favorites=favorites, media=media,
                           active=tab, tweet_count=len(tweets),
                           favorites_count=len(favorites),
                           followers=followers, following=following,
                           is_following=is_following, is_me=(u["id"] == me["id"]))


def connection_rows(db, ids, me_id):
    """Hydrate user rows for the following/followers lists."""
    if not ids:
        return []
    marks = ",".join("?" * len(ids))
    sql = f"""SELECT u.*,
                     {D.FOLLOWER_COUNT_SQL} AS follower_count,
                     EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=? AND f.followee_id=u.id) AS i_follow
              FROM users u WHERE u.id IN ({marks})"""
    rows = {r["id"]: r for r in db.execute(sql, [me_id, *ids]).fetchall()}
    return [rows[i] for i in ids if i in rows]


@app.route("/u/<username>/following")
def following_list(username):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
    if not u:
        abort(404)
    ids = [x["followee_id"] for x in db.execute(
        "SELECT followee_id FROM follows WHERE follower_id=? ORDER BY created_at DESC", (u["id"],))]
    users = connection_rows(db, ids, me["id"])
    return render_template("connections.html", u=u, users=users, kind="following",
                           active="following")


@app.route("/u/<username>/followers")
def followers_list(username):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
    if not u:
        abort(404)
    ids = [x["follower_id"] for x in db.execute(
        "SELECT follower_id FROM follows WHERE followee_id=? ORDER BY created_at DESC", (u["id"],))]
    users = connection_rows(db, ids, me["id"])
    return render_template("connections.html", u=u, users=users, kind="followers",
                           active="followers")


@app.route("/u/<username>/follow", methods=["POST"])
def follow(username):
    r = require_login()
    if r:
        return r
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
    if not u:
        abort(404)
    if u["id"] == me["id"]:
        abort(400)
    existing = db.execute("SELECT 1 FROM follows WHERE follower_id=? AND followee_id=?",
                          (me["id"], u["id"])).fetchone()
    if existing:
        db.execute("DELETE FROM follows WHERE follower_id=? AND followee_id=?", (me["id"], u["id"]))
    else:
        db.execute("INSERT INTO follows (follower_id,followee_id) VALUES (?,?)", (me["id"], u["id"]))
        db.execute("INSERT INTO notifications (user_id,actor_id,kind,body) VALUES (?,?,?,?)",
                   (u["id"], me["id"], "follow", "followed you"))
    db.commit()
    return redirect(request.referrer or url_for("profile", username=username))


@app.route("/settings", methods=["GET", "POST"])
def settings():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    if request.method == "POST":
        display_name = (request.form.get("display_name") or "").strip() or me["username"]
        bio = (request.form.get("bio") or "").strip()[:160]
        location = (request.form.get("location") or "").strip()[:60]
        website = (request.form.get("website") or "").strip()[:200]
        db = D.get_db()
        avatar = save_upload(request.files.get("avatar"), me["id"]) or me["avatar_path"]
        banner = save_upload(request.files.get("banner"), me["id"]) or me["banner_path"]
        db.execute("""UPDATE users SET display_name=?, bio=?, location=?, website=?,
                      avatar_path=?, banner_path=? WHERE id=?""",
                   (display_name, bio, location, website, avatar, banner, me["id"]))
        db.commit()
        flash("Your profile has been updated.", "success")
        return redirect(url_for("settings"))
    return render_template("settings.html")


@app.route("/users")
def people():
    r = require_login()
    if r:
        return r
    me = D.current_user()
    rows = D.get_db().execute(
        f"""SELECT u.*, {D.FOLLOWER_COUNT_SQL} AS follower_count
           FROM users u WHERE u.is_suspended=0 AND u.id<>?
           ORDER BY follower_count DESC, u.username""",
        (me["id"],)).fetchall()
    return render_template("people.html", users=rows)


# ------------------------------------------------------------------ admin
@app.route("/admin")
@D.permission_required("admin.access")
def admin_panel():
    me = D.current_user()
    db = D.get_db()
    stats = {
        "users": db.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"],
        "suspended": db.execute("SELECT COUNT(*) AS n FROM users WHERE is_suspended=1").fetchone()["n"],
        "tweets": db.execute("SELECT COUNT(*) AS n FROM tweets WHERE is_deleted=0").fetchone()["n"],
        "likes": db.execute("SELECT COUNT(*) AS n FROM likes").fetchone()["n"],
        "follows": db.execute("SELECT COUNT(*) AS n FROM follows").fetchone()["n"],
        "notifications": db.execute("SELECT COUNT(*) AS n FROM notifications").fetchone()["n"],
    }
    role_rows = db.execute("SELECT * FROM roles ORDER BY rank DESC").fetchall()
    registry = []
    for r in role_rows:
        held = D.role_permissions(r["id"])
        registry.append({"role": r, "held": held})
    perms = db.execute("SELECT * FROM permissions ORDER BY id").fetchall()
    recent = db.execute(
        """SELECT a.*, u.username FROM audit_log a LEFT JOIN users u ON u.id=a.actor_id
           ORDER BY a.id DESC LIMIT 25""").fetchall()
    role_user_counts = {
        r["name"]: db.execute(
            "SELECT COUNT(*) AS n FROM users u JOIN roles ro ON ro.id=u.role_id WHERE ro.name=?",
            (r["name"],)).fetchone()["n"]
        for r in role_rows
    }
    return render_template("admin/dashboard.html", stats=stats, registry=registry,
                           perms=perms, roles=role_rows, recent=recent,
                           role_user_counts=role_user_counts)


@app.route("/admin/users")
@D.permission_required("users.view")
def admin_users():
    search = (request.args.get("q") or "").strip()
    role_filter = (request.args.get("role") or "").strip()
    status = (request.args.get("status") or "").strip()
    rows = users_where(search, role_filter, status)
    roles = D.get_db().execute("SELECT * FROM roles ORDER BY rank DESC").fetchall()
    return render_template("admin/users.html", users=rows, roles=roles,
                           search=search, role_filter=role_filter, status=status)


@app.route("/admin/users/<int:user_id>")
@D.permission_required("users.view")
def admin_user_detail(user_id):
    db = D.get_db()
    u = db.execute(
        """SELECT u.*, r.name AS role_name, r.rank AS role_rank
           FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=?""", (user_id,)).fetchone()
    if not u:
        abort(404)
    roles = db.execute("SELECT * FROM roles ORDER BY rank DESC").fetchall()
    held = D.role_permissions(u["role_id"])
    tweets = db.execute(
        "SELECT * FROM tweets WHERE user_id=? AND is_deleted=0 ORDER BY id DESC LIMIT 50",
        (user_id,)).fetchall()
    log = db.execute(
        """SELECT a.*, au.username AS actor_username FROM audit_log a
           LEFT JOIN users au ON au.id=a.actor_id
           WHERE a.target = ? OR a.actor_id = ? ORDER BY a.id DESC LIMIT 40""",
        (f"user:{user_id}", user_id)).fetchall()
    return render_template("admin/user_detail.html", u=u, roles=roles, held=held,
                           tweets=tweets, log=log, ban_choices=BAN_DURATION_CHOICES,
                           humanize_until=humanize_until,
                           real_followers=db.execute(
                               "SELECT COUNT(*) AS n FROM follows WHERE followee_id=?",
                               (user_id,)).fetchone()["n"],
                           perms=D.get_db().execute(
                               "SELECT * FROM permissions ORDER BY id").fetchall())


@app.post("/admin/users/<int:user_id>/role")
@D.permission_required("users.roles")
def admin_set_role(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT u.*, r.rank AS role_rank FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=?",
                   (user_id,)).fetchone()
    if not u:
        abort(404)
    role_name = request.form.get("role")
    role = db.execute("SELECT * FROM roles WHERE name=?", (role_name,)).fetchone()
    if not role:
        flash("Unknown role.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    # Cannot promote someone to a rank at or above your own, unless you are owner.
    if me["role_name"] != "owner" and role["rank"] >= me["role_rank"]:
        flash("You cannot assign a role at or above your own level.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    db.execute("UPDATE users SET role_id=? WHERE id=?", (role["id"], user_id))
    db.commit()
    D.audit(me["id"], "users.roles", f"user:{user_id}", f"set role to {role_name}")
    flash(f"Role updated to {role_name}.", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


@app.post("/admin/users/<int:user_id>/suspend")
@D.permission_required("users.suspend")
def admin_suspend(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT u.*, r.rank AS role_rank FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=?",
                   (user_id,)).fetchone()
    if not u:
        abort(404)
    # A user may step down or suspend themselves; otherwise rank must be strictly lower.
    if u["id"] != me["id"] and u["role_rank"] >= me["role_rank"]:
        flash("You cannot suspend a user at or above your own level.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    new = 0 if u["is_suspended"] else 1
    db.execute("UPDATE users SET is_suspended=? WHERE id=?", (new, user_id))
    if new:
        db.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))
    db.commit()
    D.audit(me["id"], "users.suspend", f"user:{user_id}", "suspended" if new else "reinstated")
    flash("User suspended." if new else "User reinstated.", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


BAN_DURATION_CHOICES = [
    ("1h", "1 hour"), ("1d", "1 day"), ("3d", "3 days"),
    ("7d", "7 days"), ("30d", "30 days"), ("365d", "1 year"),
]


def ban_expiry(choice):
    """Map a duration choice to an expiry timestamp, or None for permanent."""
    spans = {
        "1h": timedelta(hours=1), "1d": timedelta(days=1), "3d": timedelta(days=3),
        "7d": timedelta(days=7), "30d": timedelta(days=30), "365d": timedelta(days=365),
    }
    span = spans.get(choice)
    if not span:
        return None
    return (datetime.utcnow() + span).strftime("%Y-%m-%d %H:%M:%S")


@app.post("/admin/users/<int:user_id>/ban")
@D.permission_required("users.ban")
def admin_ban(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute(
        "SELECT u.*, r.rank AS role_rank FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=?",
        (user_id,)).fetchone()
    if not u:
        abort(404)
    if u["id"] == me["id"]:
        flash("You cannot ban your own account.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    if u["role_rank"] >= me["role_rank"]:
        flash("You cannot ban a user at or above your own level.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))

    reason = (request.form.get("reason") or "").strip()
    duration = request.form.get("duration", "permanent")
    if not reason:
        flash("A ban reason is required.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))

    expires = ban_expiry(duration)
    db.execute(
        """UPDATE users SET is_banned=1, ban_reason=?, ban_permanent=?,
                  ban_expires_at=? WHERE id=?""",
        (reason, 0 if expires else 1, expires, user_id))
    db.commit()
    label = humanize_until(expires) if expires else "permanent"
    D.audit(me["id"], "users.ban", f"user:{user_id}",
            f"banned for {label}: {reason}")
    flash(f"User banned ({label}).", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


@app.post("/admin/users/<int:user_id>/unban")
@D.permission_required("users.ban")
def admin_unban(user_id):
    me = D.current_user()
    db = D.get_db()
    db.execute(
        """UPDATE users SET is_banned=0, ban_reason='', ban_permanent=0,
                  ban_expires_at=NULL WHERE id=?""", (user_id,))
    db.commit()
    D.audit(me["id"], "users.ban", f"user:{user_id}", "unbanned")
    flash("User unbanned.", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


@app.post("/admin/users/<int:user_id>/followers")
@D.permission_required("users.bot_followers")
def admin_set_followers(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    if not u:
        abort(404)
    raw = (request.form.get("followers") or "").strip()
    if not raw.isdigit():
        flash("Follower count must be a whole number of 0 or more.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    value = int(raw)
    db.execute("UPDATE users SET bonus_followers=? WHERE id=?", (value, user_id))
    db.commit()
    D.audit(me["id"], "users.bot_followers", f"user:{user_id}",
            f"set follower count to {value}")
    flash(f"Follower count set to {value}.", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


@app.post("/admin/users/<int:user_id>/verified")
@D.permission_required("users.verify")
def admin_verify(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    if not u:
        abort(404)
    new = 0 if u["is_verified"] else 1
    db.execute("UPDATE users SET is_verified=? WHERE id=?", (new, user_id))
    db.commit()
    D.audit(me["id"], "users.verify", f"user:{user_id}",
            "granted verified badge" if new else "revoked verified badge")
    flash("Verified badge granted." if new else "Verified badge revoked.", "success")
    return redirect(url_for("admin_user_detail", user_id=user_id))


@app.post("/admin/users/<int:user_id>/delete")
@D.permission_required("users.delete")
def admin_delete_user(user_id):
    me = D.current_user()
    db = D.get_db()
    u = db.execute("SELECT u.*, r.rank AS rank, r.name AS rname FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=?",
                   (user_id,)).fetchone()
    if not u:
        abort(404)
    if u["id"] == me["id"]:
        flash("You cannot delete your own account from here.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    if u["rank"] >= me["role_rank"]:
        flash("You cannot delete a user at or above your own level.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    if u["rname"] == "owner":
        flash("The owner account cannot be deleted.", "error")
        return redirect(url_for("admin_user_detail", user_id=user_id))
    db.execute("DELETE FROM users WHERE id=?", (user_id,))
    db.commit()
    D.audit(me["id"], "users.delete", f"user:{user_id}", f"deleted @{u['username']}")
    flash(f"Deleted @{u['username']}.", "success")
    return redirect(url_for("admin_users"))


@app.route("/admin/permissions", methods=["GET", "POST"])
@D.permission_required("users.permissions")
def admin_permissions():
    me = D.current_user()
    db = D.get_db()
    if request.method == "POST":
        role_id = int(request.form.get("role_id"))
        role = db.execute("SELECT * FROM roles WHERE id=?", (role_id,)).fetchone()
        if not role:
            abort(404)
        if role["name"] == "owner":
            flash("The owner role always holds every permission and cannot be edited.", "error")
            return redirect(url_for("admin_permissions"))
        selected = set(request.form.getlist("perms"))
        db.execute("DELETE FROM role_permissions WHERE role_id=?", (role_id,))
        for key in selected:
            pid = db.execute("SELECT id FROM permissions WHERE key=?", (key,)).fetchone()
            if pid:
                db.execute("INSERT OR IGNORE INTO role_permissions (role_id, permission_id) VALUES (?,?)",
                           (role_id, pid["id"]))
        db.commit()
        D.audit(me["id"], "users.permissions", f"role:{role['name']}",
                f"{len(selected)} permissions granted")
        flash(f"Permissions updated for {role['name']}.", "success")
        return redirect(url_for("admin_permissions"))
    roles = db.execute("SELECT * FROM roles ORDER BY rank DESC").fetchall()
    perms = db.execute("SELECT * FROM permissions ORDER BY id").fetchall()
    matrix = {r["id"]: D.role_permissions(r["id"]) for r in roles}
    return render_template("admin/permissions.html", roles=roles, perms=perms, matrix=matrix)


@app.route("/admin/tweets")
@D.permission_required("tweets.view")
def admin_tweets():
    q = (request.args.get("q") or "").strip()
    sql = """SELECT t.*, u.username, u.display_name,
                    (SELECT COUNT(*) FROM likes l WHERE l.tweet_id=t.id) AS like_count,
                    (SELECT COUNT(*) FROM tweets c WHERE c.parent_id=t.id AND c.is_deleted=0) AS reply_count
             FROM tweets t JOIN users u ON u.id=t.user_id
             WHERE t.is_deleted=0"""
    args = []
    if q:
        sql += " AND (t.body LIKE ? OR u.username LIKE ?)"
        args += [f"%{q}%", f"%{q}%"]
    sql += " ORDER BY t.id DESC LIMIT 200"
    tweets = D.get_db().execute(sql, args).fetchall()
    return render_template("admin/tweets.html", tweets=tweets, q=q)


@app.post("/admin/tweets/<int:tweet_id>/delete")
@D.permission_required("tweets.delete")
def admin_delete_tweet(tweet_id):
    me = D.current_user()
    db = D.get_db()
    t = db.execute("SELECT * FROM tweets WHERE id=?", (tweet_id,)).fetchone()
    if not t:
        abort(404)
    db.execute("UPDATE tweets SET is_deleted=1 WHERE id=?", (tweet_id,))
    db.commit()
    D.audit(me["id"], "tweets.delete", f"tweet:{tweet_id}", "removed by moderator")
    flash("Tweet removed.", "success")
    return redirect(request.referrer or url_for("admin_tweets"))


@app.route("/admin/audit")
@D.permission_required("audit.view")
def admin_audit():
    rows = D.get_db().execute(
        """SELECT a.*, u.username FROM audit_log a
           LEFT JOIN users u ON u.id=a.actor_id ORDER BY a.id DESC LIMIT 300""").fetchall()
    return render_template("admin/audit.html", rows=rows)


@app.route("/admin/settings", methods=["GET", "POST"])
@D.permission_required("settings.edit")
def admin_settings():
    me = D.current_user()
    db = D.get_db()
    if request.method == "POST":
        for key in ("site_name", "site_tagline", "max_tweet_length"):
            if key in request.form:
                db.execute("INSERT INTO site_settings (key,value) VALUES (?,?) "
                           "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                           (key, request.form.get(key)))
        reg = "1" if request.form.get("registration_open") else "0"
        db.execute("INSERT INTO site_settings (key,value) VALUES ('registration_open',?) "
                   "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (reg,))
        db.commit()
        D.audit(me["id"], "settings.edit", "site", "updated site settings")
        flash("Settings saved.", "success")
        return redirect(url_for("admin_settings"))
    settings_rows = db.execute("SELECT * FROM site_settings").fetchall()
    return render_template("admin/settings.html", settings_rows=settings_rows)


@app.route("/admin/backup")
@D.permission_required("backup.export")
def admin_backup():
    me = D.current_user()
    D.audit(me["id"], "backup.export", "database", "downloaded SQL dump")
    db = D.get_db()
    out = []
    for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        if name.startswith("sqlite_"):
            continue
        ddl = db.execute("SELECT sql FROM sqlite_master WHERE name=?", (name,)).fetchone()[0]
        out.append(f"{ddl};")
        cols = [c[1] for c in db.execute(f"PRAGMA table_info({name})")]
        for row in db.execute(f"SELECT * FROM {name}"):
            vals = []
            for v in row:
                if v is None:
                    vals.append("NULL")
                elif isinstance(v, (int, float)):
                    vals.append(str(v))
                else:
                    vals.append("'" + str(v).replace("'", "''") + "'")
            out.append(f"INSERT INTO {name} ({','.join(cols)}) VALUES ({','.join(vals)});")
        out.append("")
    body = "\n".join(out)
    resp = make_response(body)
    resp.headers["Content-Type"] = "application/sql"
    resp.headers["Content-Disposition"] = 'attachment; filename="twitter-backup.sql"'
    return resp


@app.errorhandler(403)
def forbidden(e):
    return render_template("error.html", code=403,
                           message="You do not have permission to view this page."), 403


@app.errorhandler(404)
def notfound(e):
    return render_template("error.html", code=404,
                           message="That page does not exist."), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "12000")), debug=False)