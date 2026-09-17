# Generates profile pictures for simulated accounts.
#
# The avatars are drawn as SVG rather than sourced as photographs: there is no
# image library available and no licensed photo set, and a wrong-looking stock
# portrait reads as less believable than a clean illustration. The styles below
# cover what real profile pictures usually are on the service - an initials
# monogram, an abstract shape, a simple pattern - so the timeline has a mix of
# faces and blanks instead of a wall of default icons.
#
# Roughly two thirds of accounts get a picture and the rest keep the default,
# matching how a real population actually looks.
module AvatarGenerator
  # Avatar generation writes files, so make sure the helper is loaded even when
  # this module is used outside a full Rails boot (rake tasks, tests).
  require "fileutils"

  # Avatar palettes. Each is a foreground/background pair drawn from colours
  # that sit well against the site's own palette.
  PALETTES = [
    [ "#1DA1F2", "#E8F5FE" ], [ "#E0245E", "#FDE9F0" ], [ "#17BF63", "#E7F8EE" ],
    [ "#794BC4", "#EFE9F9" ], [ "#F45D22", "#FDEBE1" ], [ "#FFAD1F", "#FFF5E0" ],
    [ "#1B95E0", "#E4F2FD" ], [ "#0084B4", "#E0F1F8" ], [ "#6A0DAD", "#F0E6F8" ],
    [ "#C0392B", "#F9E5E2" ], [ "#2C3E50", "#E6E9EC" ], [ "#16A085", "#E2F5F1" ],
    [ "#D35400", "#FBE9DC" ], [ "#8E44AD", "#F1E8F7" ], [ "#2980B9", "#E4EFF7" ],
    [ "#27AE60", "#E4F6EA" ], [ "#E67E22", "#FCEEDF" ], [ "#34495E", "#E8EBEE" ]
  ].freeze

  # Solid colours used for the abstract and pattern styles.
  SHAPES = %w[circle triangle square ring arc].freeze

  # Writes an avatar for `user` and returns its path relative to /uploads, or
  # nil when this account is one of the ones left without a picture.
  def self.generate(seed:, initials:, root: Rails.root.join("public", "uploads"))
    rng = Random.new(seed)

    # Just over two thirds of accounts have a picture.
    return nil if rng.rand > 0.68

    fg, bg = PALETTES[rng.rand(PALETTES.size)]
    style = %w[monogram monogram geometric pattern].sample(random: rng)
    svg = send("draw_#{style}", rng, fg, bg, initials)

    dir = root.join("avatars")
    FileUtils.mkdir_p(dir)

    name = "bot_#{seed}.svg"
    File.write(dir.join(name), svg)
    "avatars/#{name}"
  end

  def self.initials_for(display_name, username)
    parts = display_name.to_s.split(/\s+/).reject(&:blank?)
    letters = if parts.size >= 2
                parts.first[0] + parts.last[0]
              else
                (parts.first || username).to_s[0, 2]
              end
    letters.to_s.upcase
  end

  # ---------------------------------------------------------------- styles

  # Every avatar is a 128x128 SVG in the same document shape.
  def self.svg_open
    %(<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">)
  end

  # Initials on a flat background, the most common non-photo picture there is.
  def self.draw_monogram(rng, fg, bg, initials)
    svg_open +
      %(<rect width="128" height="128" fill="#{bg}"/>) +
      %(<text x="64" y="64" font-family="Helvetica,Arial,sans-serif" font-size="#{rng.rand(44..54)}" ) +
      %(fill="#{fg}" text-anchor="middle" dominant-baseline="central" font-weight="bold">) +
      "#{escape(initials)}</text></svg>"
  end

  # Overlapping geometric shapes, a common choice for topical or brand accounts.
  def self.draw_geometric(rng, fg, bg, _initials)
    body = +svg_open
    body << %(<rect width="128" height="128" fill="#{bg}"/>)
    3.times do
      cx = rng.rand(20..108)
      cy = rng.rand(20..108)
      size = rng.rand(18..52)
      opacity = (rng.rand(30..70) / 100.0).round(2)

      body << case SHAPES.sample(random: rng)
              when "circle"
                %(<circle cx="#{cx}" cy="#{cy}" r="#{size / 2}" fill="#{fg}" fill-opacity="#{opacity}"/>)
              when "triangle"
                %(<polygon points="#{cx},#{cy - size / 2} #{cx - size / 2},#{cy + size / 2} ) +
                  %(#{cx + size / 2},#{cy + size / 2}" fill="#{fg}" fill-opacity="#{opacity}"/>)
              when "square"
                %(<rect x="#{cx - size / 2}" y="#{cy - size / 2}" width="#{size}" height="#{size}" ) +
                  %(fill="#{fg}" fill-opacity="#{opacity}" transform="rotate(#{rng.rand(0..45)} #{cx} #{cy})"/>)
              when "ring"
                %(<circle cx="#{cx}" cy="#{cy}" r="#{size / 2}" fill="none" stroke="#{fg}" ) +
                  %(stroke-width="#{rng.rand(3..9)}" stroke-opacity="#{opacity}"/>)
              else
                %(<path d="M#{cx - size / 2} #{cy + size / 2} A#{size / 2} #{size / 2} 0 0 1 ) +
                  %(#{cx + size / 2} #{cy + size / 2} Z" fill="#{fg}" fill-opacity="#{opacity}"/>)
              end
    end
    "#{body}</svg>"
  end

  # A repeating motif across a coloured field.
  def self.draw_pattern(rng, fg, bg, _initials)
    body = +svg_open
    body << %(<rect width="128" height="128" fill="#{bg}"/>)
    step = rng.rand(12..26)
    radius = rng.rand(2..5)
    opacity = (rng.rand(40..75) / 100.0).round(2)

    (0..128).step(step) do |x|
      (0..128).step(step) do |y|
        body << %(<circle cx="#{x}" cy="#{y}" r="#{radius}" fill="#{fg}" fill-opacity="#{opacity}"/>)
      end
    end
    "#{body}</svg>"
  end

  # Keeps generated text from breaking the SVG document.
  def self.escape(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  # Removes every generated avatar file.
  def self.clear(root: Rails.root.join("public", "uploads", "avatars"))
    Dir.glob(root.join("bot_*.svg")).each { |path| File.delete(path) }
  end
end