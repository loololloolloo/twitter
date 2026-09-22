module ApplicationHelper
  # Renders the tweet body: links @mentions and #hashtags, escaping everything
  # else. The mention pattern matches twitter-text's rules (letters, digits and
  # underscores, 2-15 characters, not preceded by a word character or @).
  #
  # Matching runs over the raw text and each span is escaped as it is emitted.
  # Escaping the whole body up front would let the hashtag pattern match inside
  # the entities it produced - `I'm` becomes `I&#39;m`, and `#39` then reads as
  # a hashtag, leaving the literal entity on screen.
  LINKIFY_PATTERN = /(?<![\w@])@([A-Za-z0-9_]{2,15})|(?<!\w)#([A-Za-z0-9_]{1,50})/.freeze

  def linkify(text)
    source = text.to_s
    out = +""
    cursor = 0

    source.to_enum(:scan, LINKIFY_PATTERN).each do
      match = Regexp.last_match
      out << ERB::Util.html_escape(source[cursor...match.begin(0)])

      if match[1]
        handle = ERB::Util.html_escape(match[1])
        out << %(<a class="mention" href="#{profile_path(match[1])}">@#{handle}</a>)
      else
        tag = ERB::Util.html_escape(match[2])
        out << %(<a class="hashtag" href="#{explore_path(q: "##{match[2]}")}">##{tag}</a>)
      end

      cursor = match.end(0)
    end

    out << ERB::Util.html_escape(source[cursor..].to_s)
    out.html_safe
  end

  # Inlines one of the SVGs in app/assets/images/icons. Inlining lets CSS
  # colour the glyph, which an <img> tag cannot do.
  def icon(name)
    path = Rails.root.join("app", "assets", "images", "icons", "#{name}.svg")
    return "".html_safe unless path.exist?

    svg = path.read.gsub(/<!--.*?-->/m, "").sub("<svg ", '<svg class="ico" ')
    svg.html_safe
  end

  # Sensitive media in the console is hidden behind a blur rather than blocked:
  # research on moderation tooling is consistent that concealment that the
  # operator can lift deliberately cuts harm exposure without changing the
  # decision they reach. On means the safe state is the one the operator is
  # already in; the reveal is a per-view choice, so the same attachment is
  # blurred again the next time it is rendered.
  def blurred_media?
    @wellness_media_blurred
  end

  def sensitive_media_tag(url:, video:, alt: "", content_type: nil)
    classes = [ "ops-media" ]
    classes << "ops-media-blurred" if blurred_media?

    if video
      content_tag(:div, class: classes.join(" "), data: { sensitive_media: true }) do
        concat content_tag(:video, tag.source(src: url, type: content_type),
                           class: "tweet-video", controls: true, preload: "metadata")
        concat media_reveal_overlay
      end
    else
      content_tag(:div, class: classes.join(" "), data: { sensitive_media: true }) do
        concat tag.img(src: url, alt: alt, loading: "lazy")
        concat media_reveal_overlay
      end
    end
  end

  # The cover is a real button, so the reveal works with the keyboard, and it
  # says out loud what it is hiding rather than relying on the blur alone.
  def media_reveal_overlay
    return "".html_safe unless blurred_media?

    content_tag(:button, type: "button", class: "ops-media-reveal",
                        data: { reveal_media: true }) do
      concat icon("eye-slash")
      concat content_tag(:span, "Sensitive media. Click to reveal.")
    end
  end

  # Avatar image, falling back to the user glyph when nothing is uploaded.
  def pic(path, size = 48)
    if path.present?
      tag.img(src: "/uploads/#{path}", class: "avatar avatar-#{size}", alt: "")
    else
      content_tag(:span, icon("user"), class: "avatar avatar-#{size} avatar-empty")
    end
  end

  def bird
    tag.img(src: asset_path("icons/twitter-bird.svg"), alt: "Twitter")
  end

  # The console's own mark: the bird inlined rather than used as an <img> so the
  # bar can draw it in whatever colour the chrome needs.
  def bird_mark
    path = Rails.root.join("app", "assets", "images", "icons", "twitter-bird.svg")
    return "".html_safe unless path.exist?

    path.read.gsub(/<!--.*?-->/m, "").sub("<svg ", '<svg class="brand-bird" ').html_safe
  end

  # "Joined March 2012" rather than a bare timestamp.
  def joined(value)
    return value if value.blank?

    value.to_time.strftime("%B %Y")
  rescue StandardError
    value
  end

  # Compact counts exactly as the classic client showed them: 950 stays "950",
  # 1500 becomes "1.5K", 123456 becomes "123K" and 1234567890 becomes "1.2B".
  # One decimal is kept below 100 (1.5K) and dropped at or above it (123K).
  def count_label(number)
    n = number.to_i
    return n.to_s if n < 1_000

    units = [ [ 1_000_000_000_000, "T" ], [ 1_000_000_000, "B" ],
              [ 1_000_000, "M" ], [ 1_000, "K" ] ]
    base, suffix = units.find { |threshold, _| n >= threshold }
    return n.to_s if base.nil?

    rounded = compact_value(n, base)

    # 999,949 rounded at K precision is 1000K, which reads wrong; promote it to
    # the next unit and format again so it shows as 1M.
    if rounded >= 1000
      base, suffix = units[units.index([ base, suffix ]) - 1]
      rounded = compact_value(n, base)
    end

    "#{trim_decimal(rounded)}#{suffix}"
  end

  # Value of n in the given unit, rounded the way it will be displayed: whole
  # numbers once the value is three digits or more, one decimal below that.
  def compact_value(n, base)
    value = n.to_f / base
    value >= 100 ? value.round.to_f : (value * 10).round / 10.0
  end

  def trim_decimal(value)
    value == value.round ? value.round.to_s : format("%.1f", value)
  end

  # How long a poll still has to run, as "3 days left". The wording is the
  # 2019 one; the count itself comes from the same rounding as a ban expiry so
  # a poll set for a week does not read as "6 days" a second later.
  def poll_time_left(poll)
    return "Final results" if poll.closed?

    "#{humanize_until(poll.closes_at)} left"
  end

  # Account age in the round units an operator reads at a glance. The exact
  # date is on the account record; what matters next to a decision is roughly
  # how established the account is.
  def request_account_age(user)
    return "unknown" if user.created_at.blank?

    days = (Time.current - user.created_at.to_time).to_i / 86_400
    return "#{days}d" if days < 30
    return "#{days / 30}mo" if days < 365

    "#{days / 365}y"
  end

  def time_ago(value)
    return "" if value.blank?

    seconds = (Time.current - value.to_time).to_i
    return "now" if seconds < 60

    minutes = seconds / 60
    return "#{minutes}m" if minutes < 60

    hours = minutes / 60
    return "#{hours}h" if hours < 24

    days = hours / 24
    return "#{days}d" if days < 7

    value.to_time.strftime("%d %b")
  end

  def flash_class(key)
    key.to_s == "error" || key.to_s == "alert" ? "flash-error" : "flash-success"
  end

  # Shows a website without its scheme and trailing slash, as the classic
  # profile page did.
  def display_url(url)
    url.to_s.sub(%r{\Ahttps?://(www\.)?}, "").sub(%r{/\z}, "")
  end

  # The coloured tag chips the internal tool shows on an account. Visibility
  # limits share the yellow the real tool used; a compromise warning is red and
  # the two informational tags are blue.
  TAG_STYLES = {
    "Search Blacklist" => "tag-limit",
    "Trends Blacklist" => "tag-limit",
    "Do Not Amplify"   => "tag-limit",
    "Compromised"      => "tag-alert",
    "High Profile"     => "tag-info",
    "Consult SIP-PES"  => "tag-alert"
  }.freeze

  def account_tag_chips(user)
    tags = user.account_tags
    return content_tag(:span, "No tags", class: "tag tag-quiet") if tags.empty?

    safe_join(tags.map { |label|
      content_tag(:span, label, class: "tag #{TAG_STYLES.fetch(label, 'tag-quiet')}")
    })
  end

  # The red strip the tool puts above an account whose actions have to be
  # escalated before anything is done to it.
  def review_caution(user)
    return "".html_safe unless user.requires_review

    content_tag(:div, class: "caution") do
      safe_join([
        content_tag(:p, "Do Not Take Action on This Account Without Consulting SIP-PES",
                    class: "caution-text"),
        content_tag(:p, "The account is tagged for escalation. Confirm the decision with the policy team before suspending, banning or deleting.",
                    class: "caution-sub")
      ])
    end
  end
end
