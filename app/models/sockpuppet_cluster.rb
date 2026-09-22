# Groups accounts that arrived together, so a run of duplicate accounts can be
# read as one picture instead of a page at a time.
#
# This is a hint generator, never a verdict. Every group it returns is a set of
# accounts that *share* a signup signal, not a set of accounts known to be one
# person, and the signals are shown next to the accounts so the operator weighs
# the evidence rather than trusting a score. Nothing here writes, bans or
# limits anything.
#
# The three signals are weighted by how much they actually imply. Only a shared
# mailbox name connects accounts through something a stranger cannot reproduce;
# a shared signup window and a shared handle shape both occur in innocent
# batches (a launch, a fandom) and only corroborate.
class SockpuppetCluster
  # A signup window this wide is the "created together" signal. Fifteen minutes
  # is short enough that a scripted run lands inside one window and long enough
  # that a shared announcement does not collapse into one bucket.
  SIGNUP_WINDOW = 15.minutes

  # The list is capped because the screen is a reading surface, not an export.
  MAX_CLUSTERS = 50
  MIN_SIZE = 2

  # A handle shape shorter than this is too generic to mean anything; it would
  # group every "the..." account on the site and the hint would be noise.
  MIN_SHAPE = 5

  SIGNAL_LABELS = {
    "mailbox" => "Shared mailbox name",
    "window"  => "Shared signup window",
    "handle"  => "Shared handle shape"
  }.freeze

  SIGNAL_WEIGHTS = { "mailbox" => 40, "window" => 25, "handle" => 10 }.freeze

  # One shared attribute and the accounts that carry it. `detail` is the value
  # that matched, kept verbatim so the operator reads the evidence.
  Signal = Struct.new(:key, :ids, :detail) do
    def label
      SIGNAL_LABELS.fetch(key)
    end

    def weight
      SIGNAL_WEIGHTS.fetch(key)
    end
  end

  Cluster = Struct.new(:accounts, :signals) do
    def size
      accounts.size
    end

    def ids
      accounts.map(&:id)
    end

    # Strongest evidence first, and one entry per kind: a cluster reached
    # through three windows reports the window signal once.
    def ordered_signals
      signals.uniq(&:key).sort_by { |signal| -signal.weight }
    end

    def score
      ordered_signals.sum(&:weight)
    end
  end

  # The comparable part of a mailbox: the local part with separators removed
  # and a +tag folded away, so bot1@, bot.2@ and bot+tag@ all read the same.
  # The domain is dropped deliberately - a shared host is every account on the
  # site, while the name is the part a person chooses.
  def self.mailbox_name(address)
    local = address.to_s.split("@").first.to_s.downcase
    local = local.split("+").first
    local = local.gsub(/[^a-z0-9]/, "")
    local.sub(/\d+\z/, "")
  end

  # The shape a handle shares with its relatives: separators and a trailing
  # number dropped. Families separate their names with a period or an
  # underscore and often add a digit, and all of those have to collapse to one
  # shape or the hint never fires.
  def self.handle_shape(username)
    username.to_s.downcase.gsub(/[^a-z0-9]/, "").sub(/\d+\z/, "")
  end

  attr_reader :clusters

  def initialize(scope)
    @accounts = scope.to_a
    @clusters = build
  end

  private

  def build
    return [] if @accounts.size < MIN_SIZE

    union = UnionFind.new(@accounts.map(&:id))
    signals = mailbox_signals + window_signals + handle_signals
    signals.each { |signal| union.union_all(signal.ids) }

    # Signals overlap - one pair can share a mailbox and a handle shape - so the
    # accounts are merged by membership first and each signal is filed under
    # whichever cluster its members ended up in. That is what stops the overlap
    # producing two rows saying the same thing.
    grouped = Hash.new { |hash, root| hash[root] = [] }
    signals.each { |signal| grouped[union.find(signal.ids.first)] << signal }

    members = Hash.new { |hash, root| hash[root] = [] }
    @accounts.each { |account| members[union.find(account.id)] << account }

    members.filter_map do |root, accounts|
      next if accounts.size < MIN_SIZE

      Cluster.new(accounts.sort_by { |a| [ a.created_at, a.id ] }, grouped[root].uniq(&:key))
    end.sort_by { |cluster| [ -cluster.score, -cluster.size, cluster.accounts.first.id ] }
        .first(MAX_CLUSTERS)
  end

  def mailbox_signals
    groups = Hash.new { |hash, name| hash[name] = [] }
    @accounts.each do |account|
      name = self.class.mailbox_name(account.email)
      groups[name] << account if name.present?
    end

    groups.filter_map do |name, accounts|
      next if accounts.size < MIN_SIZE

      Signal.new("mailbox", accounts.map(&:id), "#{accounts.size} accounts at #{name}")
    end
  end

  # A rolling window rather than a fixed calendar grid, so a run that straddles
  # an hour boundary is still one batch.
  def window_signals
    ordered = @accounts.select(&:created_at).sort_by(&:created_at)
    buckets = []
    ordered.each do |account|
      current = buckets.last
      if current && (account.created_at - current.first.created_at) <= SIGNUP_WINDOW
        current << account
      else
        buckets << [ account ]
      end
    end

    buckets.filter_map do |bucket|
      next if bucket.size < MIN_SIZE

      Signal.new("window", bucket.map(&:id),
                 "#{bucket.size} accounts created within #{(SIGNUP_WINDOW / 60).to_i} minutes")
    end
  end

  def handle_signals
    groups = Hash.new { |hash, shape| hash[shape] = [] }
    @accounts.each do |account|
      shape = self.class.handle_shape(account.username)
      groups[shape] << account if shape.size >= MIN_SHAPE
    end

    groups.filter_map do |shape, accounts|
      next if accounts.size < MIN_SIZE

      Signal.new("handle", accounts.map(&:id), "#{accounts.size} handles shaped like #{shape}")
    end
  end

  # Small union-find over account ids. It is the whole reason overlapping
  # signals merge cleanly: each signal joins the accounts it names, chains of
  # signals join their sets, and whatever is still connected is one cluster.
  class UnionFind
    def initialize(ids)
      @parent = ids.index_with { |id| id }
    end

    def find(id)
      parent = @parent[id]
      return id if parent.nil? || parent == id

      @parent[id] = find(parent)
    end

    def union_all(ids)
      ids.each_cons(2) { |left, right| union(left, right) }
    end

    private

    def union(left, right)
      left_root = find(left)
      right_root = find(right)
      return if left_root.nil? || right_root.nil? || left_root == right_root

      @parent[right_root] = left_root
    end
  end
end
