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
    "users.bot_followers" => "Set a user's follower count",
    "users.avatar"       => "Import profile pictures from external providers",
    "users.email"        => "Change a user's email address",
    "users.roles"        => "Assign roles to users",
    "users.permissions"  => "Edit role permissions",
    "users.impersonate"  => "Log in as another user",
    "tweets.view"        => "View all tweets",
    "tweets.delete"      => "Delete any tweet",
    "tweets.pin"         => "Pin tweets",
    "reports.view"       => "View reported content",
    "reports.resolve"    => "Resolve reports",
    "settings.edit"      => "Edit site settings",
    "audit.view"         => "View the audit log",
    "backup.export"      => "Export a database backup",
    "maintenance.run"    => "Run maintenance tasks"
  }.freeze
end