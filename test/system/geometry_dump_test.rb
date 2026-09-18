require "application_system_test_case"

class GeometryDumpTest < ApplicationSystemTestCase
  test "dump geometry" do
    user = User.create!(
      username: "geo_member", display_name: "Geo Member",
      email: "geo_member@example.com",
      password_hash: PasswordDigest.hash("password123"),
      role: Role.find_by!(name: "user")
    )
    page.driver.browser.manage.window.resize_to(1920, 1000)
    visit "/login"
    fill_in "identifier", with: user.username
    fill_in "password", with: "password123"
    click_button "Log in"
    assert_selector ".app-shell", wait: 5

    puts page.evaluate_script(<<~JS)
      (function () {
        var out = [];
        function cs(sel, props) {
          var el = document.querySelector(sel);
          if (!el) return sel + ": MISSING";
          var b = el.getBoundingClientRect();
          var s = getComputedStyle(el);
          var parts = [sel,
            "left=" + b.left.toFixed(1), "right=" + b.right.toFixed(1),
            "w=" + b.width.toFixed(1)];
          props.forEach(function (p) { parts.push(p + "=" + s[p]); });
          return parts.join(" ");
        }
        out.push("clientWidth=" + document.documentElement.clientWidth);
        out.push(cs(".col-main", ["borderRightWidth"]));
        out.push(cs(".col-right", ["paddingLeft", "paddingRight", "width"]));
        var col = document.querySelector(".col-right");
        if (col) {
          Array.prototype.forEach.call(col.children, function (el, i) {
            var b = el.getBoundingClientRect();
            var s = getComputedStyle(el);
            out.push("rail[" + i + "] class=" + el.className +
                     " left=" + b.left.toFixed(1) + " right=" + b.right.toFixed(1) +
                     " w=" + b.width.toFixed(1) +
                     " padL=" + s.paddingLeft + " marL=" + s.marginLeft);
            var inner = el.querySelector(".rail-search-form");
            if (inner) {
              var ib = inner.getBoundingClientRect();
              out.push("    inner form left=" + ib.left.toFixed(1) + " right=" + ib.right.toFixed(1));
            }
          });
        }
        out.push("--- gap left of rail ---");
        var main = document.querySelector(".col-main").getBoundingClientRect();
        var firstRail = col && col.firstElementChild ? col.firstElementChild.getBoundingClientRect() : null;
        if (firstRail) {
          out.push("main.right=" + main.right.toFixed(1) + " -> firstRail.left=" +
                   firstRail.left.toFixed(1) + " = " + (firstRail.left - main.right).toFixed(1) + "px");
        }
        return out.join("\\n");
      })()
    JS
  end
end