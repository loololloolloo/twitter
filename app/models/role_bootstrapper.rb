# Installs the role ladder, the permission registry and the default site
# settings. Idempotent, so it is safe to run on every boot, on an existing
# database, and before each test.
module RoleBootstrapper
  ROLE_GRANTS = {
    "owner" => Permission::KEYS.keys,
    "admin" => %w[
      admin.access users.view users.suspend users.ban users.delete users.verify
      users.followers users.email users.tags users.warn users.notes
      tweets.view tweets.delete tweets.pin reports.view
      reports.resolve appeals.view appeals.decide
      verification.view verification.decide
      audit.view backup.export maintenance.run
      lookup.run escalations.view sessions.view relations.view lists.view
      settings.view settings.blocked_terms
    ],
    "moderator" => %w[admin.access users.view users.tags users.warn users.notes tweets.view reports.view reports.resolve appeals.view appeals.decide verification.view verification.decide lookup.run escalations.view settings.view],
    "user" => []
  }.freeze

  ROLE_DEFINITIONS = [
    [ "owner", "Instance owner. Full control over everything.", 100 ],
    [ "admin", "Administrator. Can moderate users and content.", 50 ],
    [ "moderator", "Moderator. Can review reports and content.", 25 ],
    [ "user", "Regular member.", 1 ]
  ].freeze

  SITE_SETTINGS = {
    "site_name" => "Twitter",
    "site_tagline" => "What's happening?",
    "max_tweet_length" => "280",
    "registration_open" => "1",
    "maintenance_message" => ""
  }.freeze

  def self.run
    ROLE_DEFINITIONS.each do |name, description, rank|
      role = Role.find_or_initialize_by(name: name)
      role.update!(description: description, rank: rank)
    end

    Permission::KEYS.each do |key, label|
      permission = Permission.find_or_initialize_by(key: key)
      permission.update!(label: label)
    end

    # A key that is no longer registered is dropped, along with the grants
    # pointing at it. Without this a retired permission lingers in the admin
    # editor as a checkbox that grants nothing.
    Permission.where.not(key: Permission::KEYS.keys).destroy_all

    ROLE_GRANTS.each do |role_name, keys|
      role = Role.find_by!(name: role_name)

      # The owner role always holds every registered permission, so a newly
      # added permission key cannot accidentally lock the operator out.
      wanted = role_name == Role::OWNER ? Permission.pluck(:id) : Permission.where(key: keys).pluck(:id)
      role.permission_ids = wanted
    end

    SITE_SETTINGS.each do |key, value|
      SiteSetting.find_or_create_by!(key: key) { |setting| setting.value = value }
    end

    { roles: Role.count, permissions: Permission.count, settings: SiteSetting.count }
  end
end