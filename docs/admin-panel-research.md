# Research: what a real internal admin panel looks like

Before rebuilding the panel, this looked at what platforms actually ship to
their internal staff, and at what leaked screenshots revealed about those tools.
The point is not to copy any one company. It is to find the conventions that
real trust-and-safety tooling converged on independently, and to adopt those
instead of the consumer product's look.

## Sources

The most concrete evidence is the **Twitter "Agent Tool"**, the internal support
panel exposed by the July 2020 account-hijacking incident. Several outlets
published screenshots of it, and Twitter's own statements confirm what it did.

- Motherboard/Vice obtained four screenshots of the panel, one showing it opened
  on the Binance account. The tool could set the email address on any account,
  which is how the accounts were taken over; two sources said it was also used
  to move ownership of short "OG" handles between accounts.
  <https://www.vice.com/en/article/twitter-insider-access-panel-account-hacks-biden-uber-bezos>
- CNET described the same screenshots: the panel showed *"internal details like
  the email addresses registered with accounts, when the account was last
  accessed and what phone numbers were tied to it"*, plus *"the number of
  strikes logged against each account"*.
  <https://www.cnet.com/news/privacy/twitter-says-hackers-got-access-to-internal-tools-for-hijacking-spree>
- The New York Times authenticated a screenshot showing toggles including
  **"Search Blacklist"**, **"Trends Blacklist"** and **"Notifications Spike"**.
  <https://www.wsws.org/en/articles/2020/07/24/twit-j24.html>
- Access was widespread: roughly 1,500 of 4,600 employees reportedly had it, and
  reaching it from outside the office also required VPN plus explicit per-account
  authorization.
  <https://www.darkreading.com/cyberattacks-data-breaches/access-to-internal-twitter-admin-tools-is-widespread>
- Twitter confirmed the attackers "accessed tools only available to our internal
  support teams", and that the entry route was a phone spear-phishing attack on
  employees, some of whom did not themselves have tool access.

Meta's **Cross-Check / XCheck** programme is the other well-documented one, from
the 2021 Facebook Papers. Internal documents described a system that routed
high-profile accounts to a *separate* review queue, insulated from normal
enforcement, which had grown to at least 5.8 million users by 2020. The relevant
design lesson is that "this account is special, do not treat it like the others"
is a real, explicit piece of state in these systems.

- <https://en.wikipedia.org/wiki/2021_Facebook_leak>
- <https://www.cnn.com/business/live-news/facebook-papers-internal-documents-10-25-21>

Discord's Trust & Safety workflow documents the message-ID-verification step:
staff require the immutable message ID rather than a screenshot, precisely
because screenshots can be forged. Internally that maps to leading with stable
identifiers over display strings.

General internal-tool practice was drawn from the design literature rather than
a single product:

- Operational dashboards differ from analytical ones: "Density is a feature, the
  data is current, and the job is to make action cheap." Table-first layouts
  (the Stripe pattern) where "status as colored chips", muted gridlines and
  right-aligned tabular numerals are the norm.
  <https://adminlte.io/blog/admin-dashboard-design>
- Safety mechanisms are treated as non-negotiable: confirmation dialogs for
  destructive actions, and status transitions instead of deletion for sensitive
  entities. Multi-environment separation exists specifically to prevent
  "accidental production writes from a test dashboard".
  <https://www.jetadmin.io/blog/admin-dashboard-how-to-choose-build-and-ship-a-production-ready-admin-panel>
- Enterprise tables: tabular figures so digits align, fixed headers, filter and
  search, explicit density controls.
  <https://stephaniewalter.design/blog/essential-resources-design-complex-data-tables>
- Enterprise UX is "measured by how quickly and accurately people complete work
  across many roles, departments, and large data sets, not by how long they stay
  engaged". The named failure mode is a "wall of data tables with no hierarchy".
  <https://fuselabcreative.com/enterprise-ux-design-guide-2026-best-practices>

## What the real tools have in common

Reading these together, eight conventions show up again and again. The rebuild
adopts all eight.

**1. It does not look like the product.** The Agent Tool shares nothing with the
Twitter timeline. Internal tooling is dense, neutral and utilitarian, because
the person using it is at work and reads it all day. Dropping the consumer
styling is the single most important change for realism.

**2. The account ID leads, the handle is secondary.** Every account in the tool
is addressable as a number that never changes. Handles are shown, but the ID is
what identifies the row and what goes in the URL.

**3. Raw contact data is shown, prominently.** Registered email, phone, and the
attached history. This is exactly the data the 2020 attackers were after.

**4. Last-access timestamps are first-class.** "When the account was last
accessed" was called out as a headline field, alongside when it joined.

**5. Enforcement state is explicit and named.** Whether an account is suspended,
permanently suspended, or protected are displayed as distinct states. Strikes
are counted. Nothing is inferred.

**6. The sensitive toggles have blunt names.** "Search Blacklist", "Trends
Blacklist", "Do Not Amplify". The tool says what it does, in plain words, even
when the effect is invisible to the user.

**7. Escalation flags are prominent.** Cross-Check exists as a visible marker
meaning "this account is handled differently". A caution banner sits above the
action controls, not below them.

**8. Every change is attributable.** Actor, action, target, timestamp and the
before/after detail go to an audit trail. This is the control that makes
widespread access tolerable at all - the 2020 failure was not that many people
had the tool, but that a change to a high-profile account's email did not raise a
flag. The audit trail is therefore a primary surface, not a footnote.

## Design direction for this panel

Concretely, applied to the panel in this repository:

- **Palette.** Neutral slate/greys for the chrome, a single restrained accent for
  interactive elements, and a reserved set of status colours used *only* for
  state (ok / warn / danger). No brand blue on chrome, no pills-and-hearts
  styling carried over from the timeline.
- **Type.** System UI stack, smaller than the consumer site, with tabular
  numerals everywhere numbers are compared in columns.
- **Chrome.** A slim global bar carrying environment and operator identity, with
  the section navigation in a persistent left rail. The panel must be readable
  at a glance as "internal system", not as a page of the social product.
- **Tables are the interface.** Dense rows, muted gridlines, fixed header,
  right-aligned numerals, status as chips, ID as the first column.
- **Detail pages lead with identity and state**, then contact data and timestamps,
  then the controls - with the escalation caution above the controls.
- **Destructive actions are separated** into a distinct danger zone, each with a
  confirmation step and an explicit description of what will happen.
- **The audit trail is shown on the object it concerns**, not only on a separate
  screen.
- **Owner protection is part of the design**, not only the controller: the
  read-only card for an account the operator may not manage follows directly from
  the "some accounts are handled differently" convention above.
