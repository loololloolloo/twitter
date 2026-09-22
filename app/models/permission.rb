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
    "users.handle"       => "Release and rename a user's handle",
    "users.tags"         => "Set operational tags on a user",
    "users.bulk"         => "Run bulk actions on many accounts at once",
    "users.warn"         => "Issue and revoke warnings on a user",
    # Reversing a moderation action is its own grant. Lifting a ban or
    # suspension that another operator imposed changes the account's status
    # again, so it is trusted separately from the ability to impose one.
    "users.reverse"      => "Reverse a moderation action (ban, suspension, warning)",
    # Enforcement macros. Reading them rides on the action's own permission;
    # editing the shared wording changes what every operator records, so it is
    # its own grant rather than folded into users.warn.
    "users.templates"    => "Manage enforcement templates (macros)",
    "users.notes"        => "Keep internal notes on a user",
    "users.permissions"  => "Edit role permissions",
    "users.impersonate"  => "Log in as another user",
    "tweets.view"        => "View all tweets",
    "tweets.delete"      => "Delete any tweet",
    "tweets.pin"         => "Pin tweets",
    "reports.view"       => "View reported content",
    "reports.resolve"    => "Resolve reports",
    # Saved queue views. Reading them rides on reports.view; saving the filter an
    # operator works repeatedly is its own grant because it changes the queue
    # each operator arrives at, even though it only ever writes their own rows.
    "reports.views"      => "Save and manage personal queue views",
    "appeals.view"       => "View the appeals queue",
    "appeals.decide"     => "Decide member appeals",
    # Four-eyes approvals. Filing a request rides on the action's own
    # permission (users.ban, users.email, users.roles); this grant is the
    # second pair of eyes that lets an operator approve another's request.
    "approvals.decide"   => "Approve or reject four-eyes requests",
    # Cases are a layer above reports: opening one is a judgement that a set of
    # reports is one investigation, so opening, linking and deciding are three
    # separate grants rather than one. A front-line reviewer can read a case
    # without being trusted to close it.
    "cases.view"         => "View cases",
    "cases.open"         => "Open cases",
    "cases.link"         => "Link reports to a case",
    "cases.decide"       => "Decide cases",
    "verification.view"  => "View the verification request queue",
    "verification.decide" => "Approve or deny verification requests",
    "settings.edit"      => "Edit site settings",
    # The shift handover digest. It is a read-only roll-up, but it gathers the
    # live queues, the actions taken since the shift started and the accounts
    # needing a second pair of eyes onto one screen, so it is its own grant
    # rather than something every admin.access holder sees.
    "handover.view"      => "Read the shift handover digest",
    # The blocked-terms list is split from settings.edit because reading it is
    # harmless and useful to a moderator, while changing it alters what every
    # reader sees. The hide mode in particular removes posts site-wide.
    "settings.view"      => "View the site settings and content filters",
    "settings.blocked_terms" => "Manage the blocked terms list",
    "audit.view"         => "View the audit log",
    "backup.export"      => "Export a database backup",
    # Per-account evidence exports are a disclosure, not a read: the file
    # carries the account record, its posts and its enforcement history out of
    # the panel, and every run records the reason. That is why it is its own
    # grant rather than riding on users.view or audit.view.
    "exports.run"        => "Export per-account evidence for a legal hold or data request",
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