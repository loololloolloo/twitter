# 2019 Twitter web fidelity audit

What the 2019 web client did, what this code does, and what still needs
changing. Kept as a running list so the audit is resumable rather than
restarted. Each entry names the page, the 2019 behaviour, and the gap.

## Fixed

### Right rail — trends card title
* 2019: the card was titled **"What's happening"**, with the trends nested
  beneath a smaller **"Trends for you"** subheading.
* Was: the card was titled "Trends for you" and had no parent heading, so the
  trends read as the card's own name rather than as one section of a broader
  card.
* Now: `_modern_rail.html.erb` renders `What's happening` as the card title and
  `Trends for you` as a nested heading, with "Show more" inside the section.

### Right rail — search placeholder and wording
* 2019: the rail search field was labelled **"Search Twitter"**.
* Was: the rail field said just "Search", and the footer links were abbreviated
  ("Help", "Terms", "Privacy").
* Now: the rail field and the footer links use the full 2019 wording.

### Right rail — "Show more" and the About card
* 2019: "Show more" always closed the trends list and linked to the trends
  screen; the footer card carried no prose, only the policy links and the
  copyright.
* Was: "Show more" only appeared when more than five trends existed, and the
  About card carried an explanatory sentence.
* Now: "Show more" always renders, and the About card is links plus copyright.

### Rail typography
* 2019: card titles were 19px/800; the stream body is 15px.
* Was: a second `.rail-heading` rule (dead — it styled the removed
  `.rail-block` markup) collided with the card heading and the admin panel's
  uppercase heading style.
* Now: `.rail-title` is 19px/800, nested section headings are 15px/700, and the
  dead `.rail-block` / `.rail-stats` / `.rail-actions-list` rules are gone.

## Verified correct already

Checked against the 2019 client and left alone, so a later run does not
"fix" them into something less accurate:

* **Profile picture geometry.** `--pfp-size: 134px` with `--pfp-ring: 4px` and
  `--pfp-overlap: 67px` on desktop, and `112px / 56px` at the mobile
  breakpoint. The frame straddles the banner edge by half its height, which is
  the 2019 arrangement. **Do not change these numbers** — the overlap is
  deliberately half the frame, and the stat bar reserves `--pfp-overlap` so the
  name clears the circle.
* **Composer placeholder.** `site_tagline` defaults to "What's happening?",
  which is the 2019 string. It is operator-editable in the admin settings, so
  the default is what matters.
* **Sidebar order.** Home, Explore, Notifications, Messages, Bookmarks, Lists,
  Profile, More, then the Tweet button — the 2019 sequence. A test asserts the
  order so it cannot drift.

## Open

### Right rail
* **Search bar — fixed.** Was: the search box was wrapped in `.rail-card` like
  every other rail module, so it read as one more card in the stack.
  2019: a bare sticky bar pinned to the top of the rail column, spanning the
  column width, visible while the column scrolled, sitting outside the trend
  card. Now: `.rail-search` is its own element (no `.rail-card`), `position:
  sticky; top: var(--header-h)` so it pins under the page's sticky headers, with
  the search field itself on a card-coloured pill. Asserted in
  `test/integration/shell_layout_test.rb`.
* 2019 grouped "What's happening" trends in the sidebar with a "Show more" link
  to `/explore`; the trend rows carried a category label ("Trending in
  Technology") when a location or category was known. This build has no
  category field, so trends show the tag alone. The "What's happening" heading
  and the "Show more" link to `/explore` are both present and correct.

### Sidebar
* 2019 ordered the rail: Home, Explore, Notifications, Messages, Bookmarks,
  Lists, Profile, More, then the Tweet button. The current order matches, but
  the **account switcher** sits at the foot; 2019 put it at the very bottom as a
  wide button with the avatar, display name, handle and an overflow. Confirm the
  markup matches rather than approximating it.
* **Notifications unread badge — fixed.** Was: the rail had a `.side-badge`
  pill, but only Follow requests ever rendered one; Notifications carried no
  count. 2019: a blue count sat on the Notifications item naming how much was
  unread, clearing when the list was opened. Now:
  `User#unread_notification_count` backs the badge in `shared/_side_nav.html.erb`,
  the count is capped at "99+" and matches the list the page actually renders
  (notifications from blocked or muted actors are excluded, because the
  controller drops them from the list). Under 1100px the pill floats on the
  icon's corner instead of being pushed off the row by `margin-left: auto`.
  While fixing this, the "New" chip was also made to render: the controller
  loaded `@items` as a lazy relation, so the read-marking ran the query first
  and every row already read as read. Asserted in
  `test/integration/shell_layout_test.rb`.

### Composer
* 2019's composer placeholder was "What's happening?" and the toolbar showed
  image, GIF, poll, emoji and schedule in that order. Verify the toolbar icons
  and their order on the home timeline.
* **Scheduling — fixed.** 2019's schedule control was the last toolbar item and
  opened a small panel (like the GIF picker) with a date and time; confirming it
  changed the Tweet button to a Schedule action and closed the panel. This build
  now matches: `_composer.html.erb` carries the `data-schedule-*` panel, the
  value is staged in a hidden field so a half-typed date cannot queue anything,
  and `TweetsController#scheduled_time` refuses anything that is not the exact
  `YYYY-MM-DD HH:MM` spelling or is in the past. A post with a future
  `scheduled_at` is withheld from every reader by `Tweet.visible` (the author's
  own Scheduled tab is the only place that reads past it), publishes on its own
  when the clock passes, and notifies nobody until then. The author's profile
  carries a Scheduled tab, visible only to the author. Asserted in
  `test/integration/scheduled_tweets_test.rb`.

### Profile
* 2019 used a two-column header: avatar straddling the banner edge at 67/67px
  on desktop and 56/56px on mobile. The tracker records this as the target; it
  needs re-verifying against the rendered page after the shell changes.

### Explore
* 2019's Explore screen had tabs: **For you, Trending, News, Sports,
  Entertainment**. This build renders a single stream. The tabs are the largest
  remaining structural difference on that screen.
