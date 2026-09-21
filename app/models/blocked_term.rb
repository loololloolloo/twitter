# An operator-managed term the site acts on. Each row carries its own mode,
# because "flag" and "hide" are not interchangeable: a flagged post stays up
# and is only marked in the panel, while a hidden post is removed from every
# timeline for every reader. Keeping the mode per term means one list can hold
# both, and the screen states which is which in plain words.
#
# The compiled matcher is cached and rebuilt whenever the list changes, so a
# request against the timeline pays for a pre-built SQL condition rather than
# for re-reading and re-parsing every term.
class BlockedTerm < ApplicationRecord
  MODES = {
    "hide" => "Hide - matching posts disappear from every timeline",
    "flag" => "Flag - matching posts stay up, marked for review in the panel"
  }.freeze

  CATEGORIES = {
    "abuse"  => "Abuse or harassment",
    "hate"   => "Hateful conduct",
    "spam"   => "Spam or platform manipulation",
    "safety" => "Safety",
    "other"  => "Something else"
  }.freeze

  MATCHER_CACHE_KEY = "blocked_terms/matcher/v1"
  MAX_TERM = 100

  validates :term, presence: true, length: { maximum: MAX_TERM }
  validates :mode, inclusion: { in: MODES.keys }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validate :term_is_unique_case_insensitively

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  after_commit :invalidate_matcher

  # The compiled list. One entry point so the timeline and the panel read the
  # same rules; a second matcher built elsewhere could disagree with this one.
  def self.matcher
    Rails.cache.fetch(MATCHER_CACHE_KEY) { compile_matcher }
  end

  def self.compile_matcher
    rows = active.order(:id).pluck(:term, :mode)
    Matcher.new(
      hide_terms: rows.select { |_, mode| mode == "hide" }.map(&:first),
      flag_terms: rows.select { |_, mode| mode == "flag" }.map(&:first)
    )
  end

  def self.invalidate_matcher!
    Rails.cache.delete(MATCHER_CACHE_KEY)
  end

  def mode_label
    MODES.fetch(mode, mode)
  end

  def category_label
    CATEGORIES.fetch(category, category)
  end

  # How many posts this term currently matches. Shown on the screen so an
  # operator sets a term knowing its blast radius rather than discovering it
  # afterwards. Deleted posts are excluded because hiding one changes nothing,
  # but hidden ones are not: a hide term has to be able to report the posts it
  # is already hiding, or the count would read zero the moment it took effect.
  def matching_post_count
    Tweet.where(is_deleted: false).matching_terms([ term ]).count
  end

  # The substring the SQL pattern needs, with the wildcards escaped so a term
  # containing a literal % or _ does not silently match more than it should.
  def self.like_escape(value)
    value.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
  end

  # A bound `body LIKE ...` condition over the given terms, or nil when there
  # is nothing to match. Shared so the timeline exclusion and the panel's
  # review list cannot drift apart.
  def self.like_condition(terms)
    terms = Array(terms).reject { |term| term.to_s.strip.empty? }
    return nil if terms.empty?

    clauses = terms.map { "tweets.body LIKE ? ESCAPE '\\'" }
    binds = terms.map { |term| "%#{like_escape(term)}%" }
    [ clauses.join(" OR "), binds ]
  end

  private

  def invalidate_matcher
    self.class.invalidate_matcher!
  end

  # Uniqueness is on the normalised term, because "Spam" and "spam" are the
  # same rule to everyone except the database.
  def term_is_unique_case_insensitively
    return if term.blank?

    clash = self.class.where("LOWER(term) = ?", term.strip.downcase)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:term, "is already on the list") if clash.exists?
  end

  # The compiled list, as the timeline and the panel see it. Immutable once
  # built: it is handed to request threads from the cache, so it must not carry
  # mutable state that one request could change under another.
  class Matcher
    attr_reader :hide_terms, :flag_terms

    def initialize(hide_terms:, flag_terms:)
      @hide_terms = hide_terms.freeze
      @flag_terms = flag_terms.freeze
      @hide_condition = BlockedTerm.like_condition(@hide_terms)
      @flag_condition = BlockedTerm.like_condition(@flag_terms)
    end

    # A `NOT (...)` condition that drops hidden posts, plus its binds, or nil
    # when nothing is hidden. Returned as SQL so the exclusion happens in the
    # database rather than by filtering a page of rows in Ruby.
    def hide_sql
      @hide_condition
    end

    # The same condition for the flag terms, which the panel matches against to
    # list the posts awaiting review.
    def flag_sql
      @flag_condition
    end
  end
end