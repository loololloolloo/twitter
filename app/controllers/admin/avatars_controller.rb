# Admin screen for importing profile pictures from external providers.
#
# Works on one account at a time (preview, then apply) and in bulk. The bulk
# path is the useful one: it fills in the accounts that were left without a
# picture by AvatarGenerator, so a population that is mostly default eggs can be
# given faces without touching the ones that already have something.
module Admin
  class AvatarsController < AdminController
    before_action :require_avatar_permission!
    before_action :load_user, only: [ :show, :apply ]

    # How many accounts one bulk request will touch. Deliberately small: every
    # account is an outbound HTTP request, so this bounds the wall time of a
    # request and keeps a single click from hammering a provider.
    BULK_LIMIT = 25

    # A provider value that mixes all providers and styles, chosen per account.
    RANDOM_PROVIDER = "random"

    def index
      @providers = RemoteAvatar::PROVIDERS
      @provider = params[:provider].presence || "dicebear"
      @provider = "dicebear" unless @providers.key?(@provider) || @provider == RANDOM_PROVIDER
      @style = params[:style].presence

      @scope = params[:scope].presence || "missing"
      @candidates = candidate_scope.limit(BULK_LIMIT)
      @missing_count = User.bots.where(avatar_path: [ nil, "" ]).count
      @total_bots = User.bots.count
    end

    # A single account, giving the operator a preview and a choice of provider
    # before committing the picture to the account.
    def show
      @providers = RemoteAvatar::PROVIDERS
      @provider = params[:provider].presence || "dicebear"
      @provider = "dicebear" unless @providers.key?(@provider)
      @style = params[:style].presence
    end

    # Fetches for one account and stores the result on the user.
    def apply
      provider = params[:provider].to_s
      provider = "dicebear" unless RemoteAvatar::PROVIDERS.key?(provider)

      path = RemoteAvatar.fetch(seed: seed_for(@user), provider: provider, style: params[:style].presence)

      if path.nil?
        return redirect_to admin_user_avatars_path(@user, provider: provider),
                           alert: "Could not fetch a picture from #{provider}."
      end

      previous = @user.avatar_path
      @user.update!(avatar_path: path)
      discard(previous, keep: path)
      audit!("users.avatar", target: "user:#{@user.id}", detail: "imported avatar from #{provider}")
      redirect_to admin_user_path(@user), notice: "Profile picture imported from #{provider}."
    end

    # Fills in pictures for a batch of accounts that have none.
    def bulk
      provider = normalize_provider(params[:provider])
      @scope = params[:scope].presence || "missing"

      users, applied, failed = fetch_batch(candidate_scope, provider, params[:style].presence,
                                           after_id: 0, limit: BULK_LIMIT, salt: params[:salt])

      audit!("users.avatar", target: "bot_population", detail: "bulk imported #{applied} avatars from #{provider}")

      message = "Imported #{applied} profile picture(s) from #{provider}."
      message += " #{failed} could not be fetched and were left unchanged." if failed.positive?
      redirect_to admin_avatars_path(provider: provider, scope: params[:scope]), notice: message
    end

    # One slice of a pass over the whole population, for the in-page runner.
    # The browser walks the population by ascending id and calls this until it
    # reports the pass is finished, which keeps each request short and lets the
    # page show real progress instead of a request that hangs for half an hour.
    #
    # Walking by id also makes an interrupted or repeated pass safe: an account
    # that already has a picture drops out of the "missing" scope, so it is
    # never fetched twice.
    def batch
      provider = normalize_provider(params[:provider])
      scope = candidate_scope
      after_id = params[:after_id].to_i

      users, applied, failed = fetch_batch(scope, provider, params[:style].presence,
                                           after_id: after_id, limit: BULK_LIMIT, salt: params[:salt])

      last_id = users.last&.id || after_id
      remaining = scope.where("id > ?", last_id).count
      done = users.size < BULK_LIMIT || remaining.zero?

      if done && applied.positive?
        audit!("users.avatar", target: "bot_population",
                               detail: "bulk pass imported #{applied} avatars from #{provider} in the final batch")
      end

      render json: {
        applied: applied,
        failed: failed,
        processed: users.size,
        last_id: last_id,
        remaining: remaining,
        done: done
      }
    end

    private

    def require_avatar_permission!
      require_permission!("users.avatar")
    end

    def normalize_provider(value)
      provider = value.to_s
      return provider if RemoteAvatar::PROVIDERS.key?(provider)
      return RANDOM_PROVIDER if provider == RANDOM_PROVIDER

      "dicebear"
    end

    # Resolves the provider, style and seed for one account.
    #
    # "random" mixes all three providers and their styles, and derives the seed
    # from a salt the page generates once per run. That makes a run internally
    # consistent and repeatable for a given salt, while a fresh run reshuffles
    # everyone so the button can be pressed again for a different look.
    def look_for(user, provider, style, salt)
      return [ provider, style, seed_for(user) ] unless provider == RANDOM_PROVIDER

      rng = Random.new("#{seed_for(user)}:#{salt}".hash)
      chosen = RemoteAvatar::PROVIDERS.keys[rng.rand(RemoteAvatar::PROVIDERS.size)]
      styles = RemoteAvatar::PROVIDERS[chosen][:styles]

      [ chosen, styles[rng.rand(styles.size)], "#{seed_for(user)}-#{salt}-#{rng.rand(1 << 32)}" ]
    end

    # Fetches and assigns pictures for up to `limit` accounts after `after_id`.
    # Returns the rows it examined, the number it assigned, and the number the
    # provider could not supply.
    def fetch_batch(scope, provider, style, after_id:, limit:, salt: nil)
      users = scope.where("id > ?", after_id).limit(limit).to_a
      applied = 0
      failed = 0

      users.each do |user|
        chosen, chosen_style, seed = look_for(user, provider, style, salt)
        path = RemoteAvatar.fetch(seed: seed, provider: chosen, style: chosen_style)

        if path.nil?
          failed += 1
          next
        end

        previous = user.avatar_path
        user.update_columns(avatar_path: path)
        discard(previous, keep: path)
        applied += 1
      end

      [ users, applied, failed ]
    end

    def candidate_scope
      scope = User.bots.order(:id)
      @scope == "all" ? scope : scope.where(avatar_path: [ nil, "" ])
    end

    # A stable seed per account, so re-importing for the same person returns a
    # picture that suits them rather than a new stranger each time. The username
    # is the natural stable key; the id keeps it unique if two accounts somehow
    # share a handle.
    def seed_for(user)
      "#{user.username}-#{user.id}"
    end

    # Removes the file a replaced avatar used to point at. The new path is
    # checked because a re-import of the same seed returns the same file, and
    # deleting it would blank the picture that was just assigned.
    def discard(previous, keep:)
      return if previous.blank? || previous == keep

      Uploads.remove(previous)
    end

    def load_user
      @user = User.find_by(id: params[:id] || params[:user_id])
      return if @user

      render(plain: "Not found", status: :not_found)
    end
  end
end