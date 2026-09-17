# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# jQuery is vendored under vendor/assets/javascripts rather than pulled from a
# CDN so the app works with no network access.
Rails.application.config.assets.paths << Rails.root.join("vendor", "assets", "javascripts")
Rails.application.config.assets.precompile += %w[twitter.css twitter.js jquery.min.js]

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path
