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

### Permalink — "Quote Tweets" figure opens the quotes screen
* 2019's permalink count line showed "N Quote Tweets" next to the replies and
  retweets and the figure was a link into a screen listing the quotes
  themselves, with the source post carried onto that screen.
* Was: `tweets/show.html.erb` rendered the quote figure as static text in the
  count line - the number was visible but there was no way to reach the posts
  behind it, so a reader could see that a post was quoted without being able to
  read the quotes.
* Now: the figure is `<a class="stat stat-quote" href="/tweet/:id/quotes">`,
  backed by `tweets#quotes` and `tweets/quotes.html.erb`. The source post leads
  the list, then the quoting posts through `@tweet.quotes.visible
  .readable_by(current_user)` - the same visibility rule as every timeline - so
  a quote by a blocked, silenced or permanently banned account is withheld,
  while the live count on the permalink keeps including it (the count answers
  "how many", the list answers "which ones you may read"). An unquoted post
  shows the centred empty state. The permalink stats payload carries
  `quote_count_label` so the figure stays in step while the page polls.
  Asserted in `test/integration/client_features_test.rb`.

### Rail typography
* 2019: card titles were 19px/800; the stream body is 15px.
* Was: a second `.rail-heading` rule (dead — it styled the removed
  `.rail-block` markup) collided with the card heading and the admin panel's
  uppercase heading style.
*   Now: `.rail-title` is 19px/800, nested section headings are 15px/700, and the
  dead `.rail-block` / `.rail-stats` / `.rail-actions-list` rules are gone.

### Trends — category labels
* 2019: a trend could be labelled with the vertical it belonged to, e.g.
  **"Trending in Technology"** above the tag, so the list read as topics rather
  than as a wall of hashtags.
* Was: trends rendered as a bare `#tag` plus the count line, with no vertical
  anywhere (`_modern_rail.html.erb`, `_legacy_rail.html.erb`,
  `timelines/explore.html.erb`).
* Now: `Tweet::TREND_CATEGORIES` maps tag words to a vertical and
  `Tweet.trend_category` returns it; `compute_top_trends` carries the category
  as the fourth element of each trend tuple and the rail, the legacy rail and
  Explore render "Trending in <vertical>" above the tag. Matching is on whole
  words, so `#guardrails` does not read as Technology. A tag with no known
  vertical carries **no** label rather than a bare "Trending" the data cannot
  back. The trend cache key is versioned (`.../v2/...`) so a result computed
  before the fourth element existed is not read with the new shape
  (`test/integration/trend_categories_test.rb`).

### Stream — reply context line
* 2019: a reply in any stream was prefixed, above the body, with a quiet
  **"Replying to @handle"** line whose handle linked to the account being
  answered. It is what makes a reply legible as half of a conversation rather
  than a detached post, and the permalink carried the same line.
* Was: replies rendered with no such line anywhere — the timeline, the
  permalink, and the profile "Tweets & replies" tab all showed the body alone.
* Now: `Tweet#reply_target(viewer)` names the parent's author and the shared
  `_tweet` partial plus `tweets/show.html.erb` render `.tweet-reply-context`
  above the body. The retweeted entry in the stream does **not** carry it: a
  retweet of a reply is not itself a reply, and the retweeter answered nobody.
* The line is a disclosure, so it obeys the parent's own visibility rule: it is
  withheld when the parent is missing, deleted, authored by a permanently
  banned account, or authored by a protected account the viewer may not read.
  The permalink's ancestor block, which rendered the same withheld parents, now
  walks the chain through `Tweet.visible.readable_by` so it stops at the first
  ancestor the viewer cannot open. Asserted in
  `test/integration/reply_context_test.rb`.

### Shell — phone-width layout
* 2019's phone client dropped the left rail entirely: at narrow widths the four
  primary destinations (Home, Explore, Notifications, Messages) moved into a bar
  fixed to the bottom edge, with the compose action floating above it. A
  collapsed icon rail was not used, because a rail - collapsed or not - is a
  column that steals width from an already-narrow stream.
* Was: the shell kept the rail at every width and shrank it, so at phone widths
  the stream was squeezed and the page scrolled horizontally. The narrow band
  also kept `align-items: flex-start` after flipping `.layout` to
  `flex-direction: column`, which shrank each column to its content width and
  pushed a wide tweet row past the right edge.
* Now: `shared/_mobile_nav.html.erb` renders the bottom bar plus a floating
  compose control at every width (CSS decides visibility, so the markup and the
  destinations are identical in both shapes), the bar carries the same unread
  count as the rail, and `twitter.css` sets `align-items: stretch` on the
  column-mode `.layout` while the content band reserves the bar's height as
  bottom padding. Asserted in
  `test/system/shell_layout_test.rb` and
  `test/integration/shell_layout_test.rb`.

### Settings — "Search settings" section filter
* 2019: the Settings screen opened its left column with a **"Search settings"**
  field above the section list. Typing into it narrowed the column to the
  sections whose names matched, so a member with a setting in mind did not have
  to scan seven headings. It was a filter on the navigation only - the selected
  section kept rendering in the detail column; the field never searched the
  site or changed what was on screen.
* Was: `settings/edit.html.erb` rendered the seven section links with no way to
  narrow them, and `docs/2019-audit.md` did not cover the Settings screen at all.
* Now: the nav opens with `.settings-search` (a magnifying-glass glyph and a
  `type="search"` field) and each section link carries
  `data-settings-match` with the words that should find it (so "password"
  reaches Security and "dark" reaches Accessibility). `twitter.js` filters the
  links on the visible label plus those words and shows a
  `.settings-nav-empty` note when nothing matches. It is a filter over the
  links, deliberately client-side and progressive: with no script every link
  stays reachable. The selected section is not pinned open - it disappears like
  any other non-match, leaving only the way back to it. Asserted in
  `test/integration/settings_features_test.rb`.

### Stream — empty states
* 2019 emptied every stream surface into the same centred shape: a glyph over a
  heading and a one-line note naming what would fill it. The audit had already
  converted the empty Bookmarks, Notifications, Messages, Lists, profile tabs,
  Explore search and the quote list to that shape, calling out each time that a
  bare sentence in a list row reads as a row that failed to render rather than
  as a deliberate empty screen.
* Was: three surfaces were still on the old pattern — the home timeline
  (`<li class="empty">No tweets yet. Follow someone or post the first one.</li>`),
  the permalink reply list (`<li class="empty">No replies yet.</li>`) and an
  Explore landing section with no posts (`<li class="empty-note">Nothing to see
  here yet.</li>`).
* Now: a single `shared/_empty_state.html.erb` renders the shape (the
  `profiles/_empty_state.html.erb` duplicate is folded into it and its five
  call sites repointed), and the three streams above use it — house glyph over
  "Your Home timeline is empty", comment glyph over "No replies yet",
  magnifier over "Nothing to see here yet". The search no-results branch keeps
  its query-specific inline copy, because the heading interpolates the escaped
  query. Asserted in `test/integration/stream_empty_states_test.rb`.

### Stream — the share control on the action row
* 2019 ended every action row with a **share** control (the boxed arrow),
  opening the actions that leave the row rather than the ones that react to it:
  quote, copy link, bookmark and send via Direct Message. It is what a reader
  reaches for to pass a post on.
* Was: `tweets/_tweet.html.erb` had no share control at all. Copy link lived
  only in the overflow menu and only on your own posts, so a reader could not
  share another account's post anywhere.
* Now: the row ends with `details.tweet-share`, a flex item pushed right by
  `margin-left: auto` (so it sits outside the delete branch and appears on
  every post), carrying Quote Tweet (another account's post, not a retweet),
  Copy link to Tweet (always), and Send via Direct Message (another account's
  post, signed in). Bookmarking keeps its own toggling control on the row; the
  share menu does not duplicate it. Asserted in
  `test/integration/client_features_test.rb`.

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
  Lists, Profile, More, then the Tweet button. The current order matches, and
  the **account switcher** is verified: `_side_nav.html.erb` puts `.side-account`
  at the foot of the rail (`margin-top: auto` pins it there), and the trigger is
  the wide button 2019 used - avatar, display name, @handle and an overflow
  caret, opening the upward popover rather than navigating. Markup and position
  match; no change needed.
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
  image, GIF, poll, emoji and schedule in that order. Verified: `_composer.html.erb`
  renders exactly that sequence in `.compose-tools` (image, GIF, chart-simple for
  poll, emoji, clock for schedule), and the placeholder defaults to the 2019
  string through `site_tagline`. No change needed - the earlier "verify" note is
  closed. The order and placeholder now have a regression guard in
  `test/integration/shell_layout_test.rb` ("the composer toolbar keeps the 2019
  order and prompt").
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
* **"Follows you" chip — fixed.** 2019 put a small bordered "Follows you" label
  on the handle line when the account on screen follows the viewer, so the
  relationship read before the bio did. The build had no such chip anywhere.
  `ProfilesController#show` now sets `@follows_me` (the profile account follows
  the viewer, never true on your own profile) and the header renders
  `span.follows-you` beside `@handle`, styled as a bordered label rather than a
  filled button because it states a fact, not an action. Asserted in
  `test/integration/profile_layout_test.rb` (present when followed, absent when
  not, absent on your own profile).

### Explore
* 2019's Explore screen had tabs: **For you, Trending, News, Sports,
  Entertainment**. This build now renders them: `TimelinesController#explore`
  switches the landing sections on `tab` and the search result tabs on the
  presence of `q`, and the view renders only one strip at a time
  (`test/integration/explore_tabs_test.rb`). Verified against the rendered
  page - the earlier "single stream" note is stale.

* **Search no-results state - fixed.** 2019's search screen, when nothing
  matched, was a centred magnifier over "No results for <query>" and a line
  telling the reader to try another keyword or check the spelling - the same
  shape as the empty Bookmarks, Notifications and Lists screens. Was: a bare
  "Nothing found." in a list row (`.empty-note`), which read as a timeline row
  that had failed to render. Now: `timelines/explore.html.erb` renders
  `.empty-state` with the `magnifying-glass` glyph, the query echoed in the
  heading and the retry line, and only in search mode - a landing section
  falls back to the site stream so it never reaches this branch, and it keeps a
  plain note rather than printing "No results for" over a section name.
  Asserted in `test/integration/explore_tabs_test.rb`.

### Messages
* **Inbox placeholder — fixed.** 2019's Messages inbox, with no conversation
  open, showed a centred envelope glyph over the prompt "Select a message" and
  a one-line explanation of how to start one, filling the whole right pane.
  Was: a `dm-thread-head` bar carrying the same words as a plain heading, with
  a separate paragraph below it - the shape of a thread header that had failed
  to load rather than a deliberate empty state. Now: `messages/index.html.erb`
  renders `.dm-empty-state` (envelope, prompt, explanation) and
  `.dm-empty-state` is styled in `twitter.css`. Asserted in
  `test/integration/messages_inbox_test.rb` (placeholder on the inbox, gone
  once a thread is open, conversation text present instead).
* The thread pane keeps the conversation list beside it while a thread is
  open, which is the 2019 two-pane inbox. Verified, no change needed.
* 2019 showed a compose control at the top of the inbox that opened a new
  message. This build starts a conversation from a profile's Message button
  instead. Acceptable substitute, but a search-and-start control in the inbox
  header is the closer match if the budget allows it later.

### Notifications
* 2019 gave the notifications header a settings gear at the right edge, which
  opened the notification panel of Settings rather than a page of its own.
  Added as `a.head-icon` linking to `settings_path(panel: "notifications")`
  (`test/integration/shell_layout_test.rb`).
* **Activity badge on the actor's picture — fixed.** 2019 stamped a small filled
  glyph (heart, retweet arrows, person-plus, reply arrow) on the lower-right
  corner of each notification's actor picture, so the list could be scanned by
  shape before the sentence was read. The build had a plain row. The row now
  wraps the picture in `span.notif-avatar` and overlays a coloured
  `span.notif-badge` carrying the kind's icon (colour varies by kind: blue for
  follows, green for retweets/quotes, red for likes/favourites). The badge sits
  inside the avatar anchor, so picture and badge are one link. A kind with no
  glyph (a bare system notice) renders no badge rather than inventing one.
  Asserted in `test/integration/shell_layout_test.rb`.
* **Empty state — fixed.** 2019's Notifications screen, with nothing in the
  list, was a centred bell glyph over the heading "Nothing to see here - yet"
  and a one-line explanation of what will fill it, the same shape as the empty
  Bookmarks screen. Was: a bare "No notifications yet." in a list row
  (`.empty-note`), which read as a failed row rather than a deliberate empty
  list. Now: `notifications/index.html.erb` renders `.empty-state` with the
  `bell` glyph, that heading and that sub-line. Both tabs are empty lists over
  the same table, so both carry the state; a notification on either tab
  replaces it. Asserted in `test/integration/notifications_empty_test.rb`.

## Open fidelity items (resumable backlog)

These are the known remaining gaps, recorded so a later run can pick one up
without redoing the audit. Each names the page, what 2019 did, and where the
code stands now. Verify against the rendered page before changing anything.

### Messages
* **Inbox row dates - fixed.** 2019 put a relative timestamp at the right edge
  of each conversation row's preview line ("now", "3h", "12 Mar"), so the list
  could be scanned for what arrived lately rather than only for who. Was: the
  preview rendered the last message body alone, with no date, on both the inbox
  and the sidebar beside an open thread. Now: `messages/index.html.erb` and
  `messages/show.html.erb` render `.dm-list-time` after `.dm-list-preview-text`
  inside a flex `.dm-list-preview`, using the shared `time_ago` helper. A
  conversation holding no message renders no date, because there is no arrival
  to name. Asserted in `test/integration/messages_inbox_test.rb`.

* **Compose control in the inbox header - fixed.** 2019's Messages inbox carried
  a compose affordance at the top of the conversation list (a search box plus a
  new-message control) so a conversation could be started without visiting a
  profile. Now: `messages/index.html.erb` renders a compose glyph beside the
  "Messages" heading; opening it reveals a handle picker backed by a
  `<datalist>` of registered accounts. Posting the picker resolves the handle
  and hands it to the same write the open-thread box uses, so the stored
  message is identical either way. The picker is a `<details>` disclosure, so
  it still opens with the script unavailable, and it re-opens on load when the
  inbox is carrying a picker result. An unresolved handle returns to the inbox
  with a note rather than a 404, and addressing the signed-in account is
  refused before a conversation row is built.
  Code: `app/views/messages/index.html.erb`, `MessagesController#compose`,
  `MessagesController#recipient_for`, route
  `post "messages", to: "messages#compose"`, `test/integration/messages_inbox_test.rb`.
  The profile Message button still starts a conversation by account id, which
  is unchanged.

* **Empty inbox - fixed.** 2019 emptied an inbox with no conversations into
  the same centred shape as the rest of the client: the envelope glyph over a
  heading and a line naming what fills the list, the twin of the right pane's
  "Select a message" placeholder. Was: `messages/index.html.erb` left a bare
  "No conversations yet." in a `.empty-note` row, which the audit has called
  out elsewhere as reading like a row that failed to render rather than a
  deliberate empty screen. Now: the list renders `.dm-empty-state` - the
  `envelope` glyph over "You don't have any messages yet" and "When you start a
  conversation, it will show up here." - reusing the placeholder's classes with
  a `flex: 1` rule so the state centres in the list column. Asserted in
  `test/integration/messages_inbox_test.rb` (the state present when empty and
  replaced once a conversation exists).

### Lists
* **List header counts - fixed.** 2019's list page header printed the member and
  follower counts inline beside the list name ("3 members"). Was: the header
  rendered the member count alone, because there was no way to follow a list -
  the only membership was `list_memberships`, which names who is *on* the list.
  2019 followed lists the same way it followed accounts, so the follower count
  was missing data, not just missing markup. Now: a `list_subscriptions` table
  and `ListSubscription` model back a real follow, the list page carries a
  Follow/Following button, and the header renders both counts
  ("2 members · 1 follower"). The owner is subscribed on creation so a new list
  does not open on zero followers. Following a list never touches the follow
  graph or the membership, which is the point of a list. Asserted in
  `test/integration/client_features_test.rb`.

* **Empty state - fixed.** 2019's Lists screen, with no lists on it, was not
  two bare sentences in list rows: each section carried a centred glyph over a
  heading and a one-line explanation of what would fill it, the same shape as
  the empty Bookmarks, Notifications and Messages screens. Was: "You have not
  created any lists yet." and "You are not on anyone else's list." as bare
  `.empty-note` rows, each reading as a row that had failed to render. Now:
  `lists/index.html.erb` renders `.empty-state` in both sections - the `list`
  glyph over "You haven't created any Lists yet", the `users` glyph over
  "You're not on any Lists yet" - with a sub-line apiece. Asserted in
  `test/integration/client_features_test.rb` (both states present when empty,
  the "Your lists" state replaced once a list exists).

### Bookmarks
* **Empty state - fixed.** 2019's empty Bookmarks screen was a centred
  bookmark glyph over the heading "You haven't added any Tweets to your
  Bookmarks yet", with a sub-line telling the member to use the share icon to
  add one. Was: a bare "Nothing saved yet. Tap the bookmark icon on a post to
  keep it here." in a list row (`.empty-note`), with no glyph and no heading.
  Now: `bookmarks/index.html.erb` renders `.empty-state` with a blue
  `bookmark-regular` glyph, that exact heading, and a sub-line naming the share
  icon, matching the inbox placeholder's shape. Asserted in
  `test/integration/client_features_test.rb`.

### Profile
* **Media tab progressive loading - fixed.** 2019's profile media grid filled a
  page at a time rather than shipping every thumbnail in the first response.
  Was: the media tab rendered up to 60 cells at once with no way to reach the
  rest, so a prolific account's grid was truncated silently. Now the grid draws
  one page of 60 cells and ends in a "Load more" control. The control is a real
  link (`?tab=media&page=N`) so it works without JavaScript, and asking for
  page N renders every page up to N, which is how the pre-script client
  extended rather than replaced the grid. With JavaScript the link appends only
  the newly fetched cells through `GET /u/:username/media`, which reads through
  the same visibility scope as the tab, so a block, a permanent ban or a
  protected account hides a cell on a fetched page exactly as it does on the
  first. Asserted in `test/integration/profile_media_pagination_test.rb`.
* **Stream tab empty states - fixed.** 2019 emptied every profile tab into the
  same centred shape the rest of the client uses: a glyph over a heading and a
  line naming what fills the tab. Was: the Media tab (`p.empty.profile-empty`,
  "No photos or videos yet."), the Scheduled tab ("Nothing scheduled.") and the
  shared Tweets / Tweets & replies / Likes branch each left a bare sentence,
  the last of them as a `<li>` in the timeline, so an account with nothing in a
  tab read as a row that had failed to render. Now all of them render
  `profiles/_empty_state.html.erb` (`.empty-state`, reusing the class the other
  2019 screens use): the `image` glyph on Media, `clock` on Scheduled, and on
  the timeline `heart` for Likes, `compose` for your own empty timeline and
  `comment` for a visitor's. The copy differs per tab because what fills a tab
  differs - Likes fills when the account reacts to a post, Media when it
  attaches one - and the timeline speaks in the first person only on your own
  profile. Asserted in `test/integration/profile_layout_test.rb` (each heading
  present on its tab, the two timeline voices kept distinct, and the state
  replaced once the tab has content).

### Shell
* **Left sidebar "More" disclosure - verified.** 2019 kept More inline in the
  sidebar list, expanding under the trigger rather than as an overlay. Confirmed:
  `.side-more-list` is a static flex column inside the `<li>` (no `position:
  absolute`), indented under the summary with a left rule, so it pushes the list
  below it down rather than floating. `test/integration/shell_layout_test.rb`
  asserts the labels. No change needed.

### Following / Followers
* **Empty state - fixed.** When an account follows nobody, or has no followers,
  2019 centred a glyph over a heading and a sub-line, the same shape as every
  other empty screen. Was: `profiles/connections.html.erb` left a bare sentence
  in a list row (`.empty-note`) - "@user isn't following anyone yet." - with no
  glyph and no heading, the one 2019 surface still using that older pattern.
  Now both tabs render `.empty-state`: the `users` glyph over "… isn't following
  anyone yet" on Following, the `user` glyph over "… doesn't have any followers
  yet" on Followers, each with a sub-line naming when the list fills. Asserted in
  `test/integration/profile_layout_test.rb` (each heading present on its own tab
  and absent on the other, and the state replaced once a follow exists).

