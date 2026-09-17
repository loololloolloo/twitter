-- Twitter schema
PRAGMA foreign_keys = ON;

-- ---------------- Roles & permissions ----------------
CREATE TABLE IF NOT EXISTS roles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    rank        INTEGER NOT NULL DEFAULT 0   -- higher = more powerful
);

CREATE TABLE IF NOT EXISTS permissions (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    key   TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ---------------- Users ----------------
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
    display_name  TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    bio           TEXT NOT NULL DEFAULT '',
    location      TEXT NOT NULL DEFAULT '',
    website       TEXT NOT NULL DEFAULT '',
    avatar_path   TEXT,
    banner_path   TEXT,
    role_id       INTEGER NOT NULL REFERENCES roles(id),
    is_suspended  INTEGER NOT NULL DEFAULT 0,
    is_verified   INTEGER NOT NULL DEFAULT 0,
    is_banned     INTEGER NOT NULL DEFAULT 0,
    ban_reason    TEXT    NOT NULL DEFAULT '',
    ban_permanent INTEGER NOT NULL DEFAULT 0,
    ban_expires_at TEXT   DEFAULT NULL,
    bonus_followers INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    last_login_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role_id);

CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL
);

-- ---------------- Tweets ----------------
CREATE TABLE IF NOT EXISTS tweets (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body           TEXT NOT NULL DEFAULT '',
    parent_id      INTEGER REFERENCES tweets(id) ON DELETE CASCADE,  -- replies
    retweet_of_id  INTEGER REFERENCES tweets(id) ON DELETE CASCADE,  -- retweets
    media_path     TEXT,
    is_deleted     INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_tweets_user   ON tweets(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tweets_parent ON tweets(parent_id);
CREATE INDEX IF NOT EXISTS idx_tweets_rt     ON tweets(retweet_of_id);

CREATE TABLE IF NOT EXISTS likes (
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tweet_id   INTEGER NOT NULL REFERENCES tweets(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, tweet_id)
);

CREATE TABLE IF NOT EXISTS follows (
    follower_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (follower_id, followee_id),
    CHECK (follower_id <> followee_id)
);

-- ---------------- Direct messages ----------------
CREATE TABLE IF NOT EXISTS dm_conversations (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_a     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_a, user_b),
    CHECK (user_a < user_b)
);

CREATE TABLE IF NOT EXISTS dm_messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES dm_conversations(id) ON DELETE CASCADE,
    sender_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body            TEXT NOT NULL,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ---------------- Notifications ----------------
CREATE TABLE IF NOT EXISTS notifications (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,
    kind       TEXT NOT NULL,          -- like | retweet | reply | follow | mention | admin
    tweet_id   INTEGER REFERENCES tweets(id) ON DELETE CASCADE,
    body       TEXT NOT NULL DEFAULT '',
    is_read    INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, created_at DESC);

-- ---------------- Admin / audit ----------------
CREATE TABLE IF NOT EXISTS audit_log (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_id   INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action     TEXT NOT NULL,
    target     TEXT NOT NULL DEFAULT '',
    detail     TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS site_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- ---------------- Seed roles & permissions (no users) ----------------
INSERT OR IGNORE INTO roles (name, description, rank) VALUES
    ('owner',   'Instance owner. Full control over everything.', 100),
    ('admin',   'Administrator. Can moderate users and content.',  50),
    ('moderator','Moderator. Can review reports and content.',     25),
    ('user',    'Regular member.',                                  1);

INSERT OR IGNORE INTO permissions (key, label) VALUES
    ('admin.access',          'Access the admin panel'),
    ('users.view',            'View the user list'),
    ('users.suspend',         'Suspend or reinstate users'),
    ('users.ban',             'Ban or unban users'),
    ('users.delete',          'Delete users'),
    ('users.verify',          'Grant or revoke verified badge'),
    ('users.bot_followers',   'Set a user''s follower count'),
    ('users.roles',           'Assign roles to users'),
    ('users.permissions',     'Edit role permissions'),
    ('users.impersonate',     'Log in as another user'),
    ('tweets.view',           'View all tweets'),
    ('tweets.delete',         'Delete any tweet'),
    ('tweets.pin',            'Pin tweets'),
    ('reports.view',          'View reported content'),
    ('reports.resolve',       'Resolve reports'),
    ('settings.edit',         'Edit site settings'),
    ('audit.view',            'View the audit log'),
    ('backup.export',         'Export a database backup'),
    ('maintenance.run',       'Run maintenance tasks');

-- owner gets every permission
INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
    SELECT (SELECT id FROM roles WHERE name='owner'), id FROM permissions;

-- admin gets a broad but non-owner subset
INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
    SELECT (SELECT id FROM roles WHERE name='admin'), id FROM permissions
    WHERE key IN ('admin.access','users.view','users.suspend','users.ban','users.delete',
                  'users.verify','users.bot_followers','tweets.view','tweets.delete','tweets.pin',
                  'reports.view','reports.resolve','audit.view','backup.export');

-- moderator gets a narrow subset
INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
    SELECT (SELECT id FROM roles WHERE name='moderator'), id FROM permissions
    WHERE key IN ('admin.access','users.view','tweets.view','reports.view','reports.resolve');

INSERT OR IGNORE INTO site_settings (key, value) VALUES
    ('site_name', 'Twitter'),
    ('site_tagline', 'What''s happening?'),
    ('registration_open', '1'),
    ('max_tweet_length', '140');
