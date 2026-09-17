ENV["RAILS_ENV"] ||= "test"
require_relative "test_helper"

# Boots the app in a real browser so layout claims can be measured rather than
# assumed. Chromium is driven headlessly through Selenium; the geometry helpers
# below read the laid-out boxes back out of the page.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
  end

  # Selenium's driver binary, which is the same Chromium the runtime provides.
  Selenium::WebDriver::Chrome.path = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]

  # The laid-out rectangle of the first element matching `selector`, in CSS
  # pixels relative to the document.
  def box(selector)
    rect = page.evaluate_script(<<~JS)
      (function () {
        var el = document.querySelector(#{selector.to_json});
        if (!el) return null;
        var r = el.getBoundingClientRect();
        return { left: r.left, top: r.top + window.scrollY,
                 right: r.right, bottom: r.bottom + window.scrollY,
                 width: r.width, height: r.height };
      })()
    JS
    raise "no element matching #{selector}" if rect.nil?

    rect.symbolize_keys
  end

  # How far the document overflows the viewport horizontally. Positive means a
  # horizontal scrollbar, which is the bug the narrow layouts used to have.
  def horizontal_overflow
    page.evaluate_script(
      "document.documentElement.scrollWidth - document.documentElement.clientWidth"
    )
  end

  # Whether two boxes share any area at all.
  def overlapping?(a, b)
    return false if a[:right] <= b[:left] || b[:right] <= a[:left]
    return false if a[:bottom] <= b[:top] || b[:bottom] <= a[:top]

    true
  end
end