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

  # Which era of the client to run. Separate from the light/dark theme.
  patch "settings/design", to: "settings#design", as: :design

  # Protecting an account is a privacy setting rather than a moderation one.
  patch "settings/privacy", to: "settings#privacy", as: :privacy_settings

  # Saved posts. Private to the signed-in account, so the index is only ever
  # its own list.
  get    "bookmarks",            to: "bookmarks#index",   as: :bookmarks
  delete "bookmarks",            to: "bookmarks#clear",   as: :clear_bookmarks
  post   "tweet/:tweet_id/bookmark",   to: "bookmarks#create",  as: :bookmark_tweet
  delete "tweet/:tweet_id/bookmark",   to: "bookmarks#destroy"

  # Blocks and mutes. Both are relationships from the signed-in account to
  # another, so they share a controller.
  post   "u/:username/block",   to: "relationships#block",   as: :block_user
  delete "u/:username/block",   to: "relationships#unblock"
  post   "u/:username/mute",    to: "relationships#mute",    as: :mute_user
  delete "u/:username/mute",    to: "relationships#unmute"

  # Lists: curated timelines read without following the accounts in them.
  resources :lists, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    get    "members", to: "lists#members", as: :members
    post   "members", to: "lists#add_member"
    delete "members/:user_id", to: "lists#remove_member", as: :member
  end

  # Asks to follow a protected account, which the account approves or declines.
  get  "follow_requests",              to: "follow_requests#index",   as: :follow_requests
  post "follow_requests/:id/approve",  to: "follow_requests#approve", as: :approve_follow_request
  post "follow_requests/:id/reject",   to: "follow_requests#reject",  as: :reject_follow_request

  # Reporting from the client. A post or an account can be reported; both land
  # in the moderation queue the admin screen already reads.
  get  "report",              to: "reports#new",    as: :new_report
  post "report",              to: "reports#create", as: :report

  # Accounts connected to this browser. There is no account list page: the
  # switcher lives in the sidebar popover, so these two endpoints are all the
  # server needs to offer.
  post   "accounts/:id", to: "accounts#update",  as: :switch_account
  delete "accounts/:id", to: "accounts#destroy", as: :forget_account

  # The old account list address forwards to the switcher that replaced it, so
  # a bookmark or a stale link lands somewhere useful instead of a 404.
  get "accounts", to: "accounts#index", as: :accounts

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
  # Hiding a reply is the parent's author's decision, so it is addressed by the
  # reply's own id.
  post   "tweet/:id/hide",    to: "tweets#hide_reply",   as: :hide_reply
  delete "tweet/:id/hide",    to: "tweets#unhide_reply"
  # The per-post analytics screen ("View Tweet activity").
  get    "tweet/:id/activity", to: "tweets#activity", as: :tweet_activity
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
    post   "users/:id/tags",      to: "users#update_tags",     as: :user_tags
    post   "users/:id/warn",      to: "users#warn",            as: :user_warn
    post   "users/:id/warnings/:warning_id/revoke",
           to: "users#revoke_warning", as: :user_warning_revoke
    post   "users/:id/impersonate", to: "users#impersonate",   as: :user_impersonate

    get  "permissions", to: "permissions#index", as: :permissions
    post "permissions", to: "permissions#update"

    get  "settings", to: "settings#edit",   as: :settings
    post "settings", to: "settings#update"

    get    "tweets",     to: "tweets#index",   as: :tweets
    delete "tweets/:id", to: "tweets#destroy", as: :tweet
    post   "tweets/:id/pin",   to: "tweets#pin",   as: :tweet_pin
    post   "tweets/:id/unpin", to: "tweets#unpin", as: :tweet_unpin

    post "stop-impersonating", to: "users#stop_impersonating", as: :stop_impersonating

    get  "reports", to: "reports#index", as: :reports
    post "reports/:id/resolve", to: "reports#resolve", as: :report_resolve

    get "audit",  to: "audit#index",   as: :audit
    get "audit/export", to: "audit#export", as: :audit_export
    get "backup", to: "backup#export", as: :backup
    # Insights is read-only analytics over the existing tables, so it needs no
    # confirmation and destroys nothing.
    get "insights", to: "insights#index", as: :insights

    # The toolbar's own working surfaces. These are deliberately not the same
    # thing as the rail's queues: the rail says what is waiting, the toolbar
    # says what can be resolved once something specific is in hand.
    get  "lookup",  to: "lookup#index", as: :lookup

    get  "escalations", to: "escalations#index", as: :escalations

    get    "sessions",           to: "sessions#index",           as: :sessions
    delete "sessions/:id",       to: "sessions#destroy",         as: :session
    post   "sessions/user/:id",  to: "sessions#destroy_for_user", as: :session_revoke_user

    get "relations", to: "relations#index", as: :relations

    get   "lists",      to: "lists#index",  as: :lists
    patch "lists/:id",  to: "lists#update", as: :list

    # Maintenance. Every destructive action is a POST so it cannot be reached
    # by following a link, and each is confirmed and audited by the controller.
    get  "tools",                   to: "tools#show",              as: :tools
    post "tools/clear-follows",      to: "tools#clear_follows",      as: :tools_clear_follows
    post "tools/purge-tweets",       to: "tools#purge_tweets",       as: :tools_purge_tweets
    post "tools/clear-sessions",     to: "tools#clear_sessions",     as: :tools_clear_sessions
    post "tools/prune-orphans",      to: "tools#prune_orphans",      as: :tools_prune_orphans
    post "tools/clear-audit-log",    to: "tools#clear_audit_log",    as: :tools_clear_audit
    post "tools/reset-database",     to: "tools#reset_database",     as: :tools_reset
    post "tools/restore-database",   to: "tools#restore_database",   as: :tools_restore
    post "tools/clear-notifications", to: "tools#clear_notifications", as: :tools_clear_notifications
    post "tools/clear-messages",      to: "tools#clear_messages",      as: :tools_clear_messages
    post "tools/clear-views",         to: "tools#clear_views",         as: :tools_clear_views
    post "tools/clear-reports",       to: "tools#clear_reports",       as: :tools_clear_reports
    post "tools/clear-granted-followers",  to: "tools#clear_granted_followers",  as: :tools_clear_granted_followers
    post "tools/clear-granted-engagement", to: "tools#clear_granted_engagement", as: :tools_clear_granted_engagement
    post "tools/clear-all-sessions",  to: "tools#clear_all_sessions",  as: :tools_clear_all_sessions
    post "tools/vacuum",              to: "tools#vacuum",              as: :tools_vacuum

    post "sidebar/announcement", to: "sidebar#update_announcement", as: :sidebar_announcement

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