Rails.application.routes.draw do
  # Authentication
  get  "login",  to: "sessions#new"
  post "login",  to: "sessions#create"
  get  "logout", to: "sessions#destroy"
  delete "logout", to: "sessions#destroy"

  get  "signup", to: "registrations#new"
  post "signup", to: "registrations#create"

  get "banned", to: "banned#show"

  # Core
  get "home",          to: "timelines#home"
  # New timeline entries since a given time, polled by the open home page.
  get "home/feed",     to: "timelines#feed", as: :home_feed
  get "explore",       to: "timelines#explore"
  get "users",         to: "people#index"
  get "notifications", to: "notifications#index"

  get   "settings", to: "settings#edit"
  patch "settings", to: "settings#update"
  post  "settings", to: "settings#update"

  patch "settings/password", to: "settings#password", as: :password
  post  "settings/password", to: "settings#password"

  patch "settings/theme", to: "settings#theme", as: :theme

  # Accounts connected to this browser, and switching between them.
  get    "accounts",     to: "accounts#index",   as: :accounts
  post   "accounts/:id", to: "accounts#update",  as: :switch_account
  delete "accounts/:id", to: "accounts#destroy", as: :forget_account

  # Removes every message the signed-in member has sent. Not an admin action:
  # it only ever touches your own messages.
  delete "settings/messages", to: "settings#clear_messages", as: :clear_messages

  # Removes every tweet the signed-in member has posted. Not an admin action:
  # it only ever touches your own tweets.
  delete "settings/tweets", to: "settings#clear_tweets", as: :clear_tweets

  post "compose", to: "tweets#create"

  get  "messages",     to: "messages#index"
  get  "messages/:id", to: "messages#show",   as: :conversation
  post "messages/:id", to: "messages#create"

  # Profiles and the social graph
  get    "u/:username",           to: "profiles#show",      as: :profile
  get    "u/:username/following", to: "profiles#following", as: :following
  get    "u/:username/followers", to: "profiles#followers", as: :followers
  post   "u/:username/follow",    to: "follows#create",     as: :follow_user
  delete "u/:username/follow",    to: "follows#destroy"

  # Tweets
  get    "tweet/:id",         to: "tweets#show",   as: :tweet
  post   "tweet/:id/like",    to: "likes#create",  as: :like_tweet
  delete "tweet/:id/like",    to: "likes#destroy"
  post   "tweet/:id/favorite",   to: "likes#create",  as: :favorite_tweet, defaults: { kind: "favourite" }
  delete "tweet/:id/favorite",   to: "likes#destroy", defaults: { kind: "favourite" }
  post   "tweet/:id/retweet", to: "tweets#retweet", as: :retweet_tweet
  # Engagement for the open permalink, polled so its counts keep moving.
  get    "tweet/:id/stats",   to: "tweets#stats",   as: :tweet_stats
  post   "tweet/:id/delete",  to: "tweets#destroy"
  delete "tweet/:id",         to: "tweets#destroy"

  # Admin
  namespace :admin do
    get "users",     to: "users#index", as: :users
    get "users/:id", to: "users#show",  as: :user

    post   "users/:id/ban",       to: "users#ban",             as: :user_ban
    post   "users/:id/unban",     to: "users#unban",           as: :user_unban
    post   "users/:id/suspend",   to: "users#suspend",         as: :user_suspend
    delete "users/:id",           to: "users#destroy",         as: :user_destroy
    post   "users/:id/role",      to: "users#update_role",     as: :user_role
    post   "users/:id/verified",  to: "users#toggle_verified", as: :user_verified
    post   "users/:id/followers", to: "users#set_followers",   as: :user_followers
    post   "users/:id/email",     to: "users#update_email",    as: :user_email

    get  "avatars",             to: "avatars#index", as: :avatars
    post "avatars",             to: "avatars#bulk"
    post "avatars/batch",       to: "avatars#batch"
    get  "users/:user_id/avatars", to: "avatars#show",  as: :user_avatars
    post "users/:user_id/avatars", to: "avatars#apply", as: :user_avatar_apply

    get  "permissions", to: "permissions#index", as: :permissions
    post "permissions", to: "permissions#update"

    get  "settings", to: "settings#edit",   as: :settings
    post "settings", to: "settings#update"

    get    "tweets",     to: "tweets#index",   as: :tweets
    delete "tweets/:id", to: "tweets#destroy", as: :tweet

    get "audit",  to: "audit#index",   as: :audit
    get "backup", to: "backup#export", as: :backup

    post "sidebar/announcement", to: "sidebar#update_announcement", as: :sidebar_announcement
    post "sidebar/bots",         to: "sidebar#toggle_bots",         as: :sidebar_bots

    # The bot runner is a separate process; these control it.
    get  "bots",         to: "bots#show",    as: :bots
    post "bots/start",   to: "bots#start",   as: :start_bots
    post "bots/stop",    to: "bots#stop",    as: :stop_bots
    post "bots/restart", to: "bots#restart", as: :restart_bots

    root to: "dashboard#index"
  end

  # Static pages linked from the footer.
  get "about",   to: "pages#show", defaults: { page: "about" },   as: :about
  get "help",    to: "pages#show", defaults: { page: "help" },    as: :help
  get "tos",     to: "pages#show", defaults: { page: "tos" },     as: :tos
  get "privacy", to: "pages#show", defaults: { page: "privacy" }, as: :privacy

  # A slug the controller does not know about is a genuine 404.
  get "pages/:page", to: "pages#show", as: :page

  root "timelines#root"

  match "/404", to: "errors#not_found",      via: :all, as: :not_found
  match "/403", to: "errors#forbidden",      via: :all, as: :forbidden
  match "/422", to: "errors#unprocessable",  via: :all, as: :unprocessable
  match "/500", to: "errors#internal_error", via: :all, as: :internal_error

  # Anything still unmatched is a 404 in its own right, so an unknown URL gets
  # the app's own page rather than the framework's routing-error screen. This
  # has to stay last: routes are matched in order, so every real route above
  # wins, and only the leftovers land here.
  #
  # Rails' own development-only endpoints are excluded so the routing inspector
  # and mailer previews keep working.
  match "*path", to: "errors#not_found", via: :all,
        constraints: ->(request) { !request.path.start_with?("/rails/") && request.path != "/rails" }
end