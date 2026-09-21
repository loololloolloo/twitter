class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  # Registered permission keys. Adding one here does not grant it to anyone;
  # see db/seeds.rb for the role grants.
  KEYS = {
    "admin.access"       => "Access the admin panel",
    "users.view"         => "View the user list",
    "users.suspend"      => "Suspend or reinstate users",
    "users.ban"          => "Ban or unban users",
    "users.delete"       => "Delete users",
    "users.verify"       => "Grant or revoke verified badge",
    "users.followers"    => "Set a user's follower count",
    "users.email"        => "Change a user's email address",
    "users.roles"        => "Assign roles to users",
    "users.tags"         => "Set operational tags on a user",
    "users.warn"         => "Issue and revoke warnings on a user",
    "users.notes"        => "Keep internal notes on a user",
    "users.permissions"  => "Edit role permissions",
    "users.impersonate"  => "Log in as another user",
    "tweets.view"        => "View all tweets",
    "tweets.delete"      => "Delete any tweet",
    "tweets.pin"         => "Pin tweets",
    "reports.view"       => "View reported content",
    "reports.resolve"    => "Resolve reports",
    "appeals.view"       => "View the appeals queue",
    "appeals.decide"     => "Decide member appeals",
    "verification.view"  => "View the verification request queue",
    "verification.decide" => "Approve or deny verification requests",
    "settings.edit"      => "Edit site settings",
    # The blocked-terms list is split from settings.edit because reading it is
    # harmless and useful to a moderator, while changing it alters what every
    # reader sees. The hide mode in particular removes posts site-wide.
    "settings.view"      => "View the site settings and content filters",
    "settings.blocked_terms" => "Manage the blocked terms list",
    "audit.view"         => "View the audit log",
    "backup.export"      => "Export a database backup",
    "maintenance.run"    => "Run maintenance tasks",
    # The lookup surfaces. These are read-only, but they expose raw account
    # records and session state, so they are granted deliberately rather than
    # folded into admin.access.
    "lookup.run"         => "Look up accounts and records by identifier",
    "escalations.view"   => "View the escalation and visibility-limit queue",
    "sessions.view"      => "View and revoke active sessions",
    "relations.view"     => "View the block and mute graph",
    "lists.view"         => "View and moderate member lists"
  }.freeze
end