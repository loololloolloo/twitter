# Bootstraps the role ladder, permission registry and default site settings.
# Safe to run repeatedly on any database; see RoleBootstrapper for the details.
summary = RoleBootstrapper.run
puts "roles: #{summary[:roles]}, permissions: #{summary[:permissions]}, settings: #{summary[:settings]}"
