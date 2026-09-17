require "test_helper"

# Compiles every ERB template with the real Rails handler. Some ERB mistakes
# are valid Ruby to the plain ERB parser but break once ActionView injects its
# output buffer - a `case`/`when` chain split across separate tags is the usual
# offender - and those only surface when that one page renders. Catching them
# here means a broken page cannot ship just because no test happened to hit it.
class TemplateCompilationTest < ActiveSupport::TestCase
  test "every template compiles with the Rails ERB handler" do
    handler = ActionView::Template::Handlers::ERB.new
    failures = []

    Dir[Rails.root.join("app/views/**/*.erb")].sort.each do |path|
      source = File.read(path)
      template = ActionView::Template.new(
        path, nil, handler, locals: [], format: :html, virtual_path: path
      )
      handler.call(template, source)
    rescue StandardError => e
      failures << "#{path}: #{e.message.to_s.lines.first.to_s.strip}"
    end

    assert_empty failures, "templates failed to compile:\n#{failures.join("\n")}"
  end
end