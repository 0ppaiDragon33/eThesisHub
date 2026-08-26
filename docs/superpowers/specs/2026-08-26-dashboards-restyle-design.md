# Dashboards and the accent restyle

Every role currently lands on a work queue. A student opens the app to
"My thesis", a coordinator to "Recommendations". Neither answers the
question people actually arrive with — *where does this stand, and what
needs me?* This milestone gives each role a real overview screen at
index 0, and adds the analytics the Chapter I objectives promise but the
app has never shown.

It also takes a measured amount of visual direction from a Figma
redesign the researcher produced separately: the accent-coloured stat
tiles and the chart panels, without the indigo palette or the account
model that redesign assumes.

No new user-facing capability is added. Every number on every dashboard
is derived from data the app already stores and the reader is already
permitted to see.

## 1. What this delivers

- An **Overview** destination at index 0 for student, faculty, dean and
  coordinator. Existing destinations shift down one.
- A **`StatTile`** widget — four per dashboard, responsive across three
  size steps.
- A **"Needs you"** queue on every overview, containing only items that
  reader can act on.
- A **student progress rail** across the six thesis lifecycle stages.
- **Two chart panels** — a stage breakdown donut and a submission trend
  — on the coordinator and dean overviews only.
- An **accent palette** extending `AppTokens`, used exclusively where
  colour identifies rather than judges.

## 2. Decisions taken

Numbering continues from the project design doc.

**D14 — Colour has two jobs and they stay separate.**
The existing palette assigns meaning: `endorsed` is a signature,
`returned` a rubber stamp, `awaiting` "someone else has it", `seal`
"you can act here". Those never move. A new five-colour accent set is
added for tile icons and chart series, where colour distinguishes one
thing from another and asserts nothing about it. A reader who learns
that green means signed must never then meet a decorative green.

**D15 — No trend deltas.**
The reference design puts `↑ +6 from last sem` under every figure.
Computing that needs a stored snapshot of the previous value, and
nothing in this system keeps one. Tiles show the count and a factual
sub-line. Where a genuine ratio exists — 2 of 5 chapters approved — a
slim proportion bar occupies that space instead.

**D16 — The count and the queue share one provider.**
"3 things need you today" is `queue.length` of the same list rendered
below it, never a separately computed figure. Two sources would
eventually disagree, and a dashboard that contradicts itself is worse
than one that shows nothing.

**D17 — The faculty "Needs you" queue spans both modes.**
Tiles remain mode-aware, matching D5. The queue does not: a Conforme
request or a defence consolidation you owe must not hide behind the
Adviser/Panelist switch, because the person who needs to see it has no
reason to think of looking in the other mode.

**D18 — Charts are for whole-college roles only.**
The donut and the trend appear for the coordinator and the dean, who
are the only readers with a college-wide view and the only ones for
whom aggregate shape is a real question. A faculty member with four
advisees needs a list, not a chart.

**D19 — Bundle a serif, and give it only the document voice.**
This corrects a factual error in the first draft of this spec, which
assumed the app already set headings in a serif. It does not.
`app_theme.dart` bundles no font files at all: the family is the
platform default, and structure comes from weight, size and tracking
alone. The serif in this project exists only inside the generated PDF,
which the `pdf` package renders independently of the theme.

That was a deliberate, documented choice and this milestone reverses
it. Reversing it needs a reason, and the reason is that the paper
metaphor has until now been asserted in a doc comment rather than
visible on screen — every justification for the palette rests on a
resemblance the interface never actually had.

**Source Serif 4**, SIL Open Font License 1.1, two static weights
(SemiBold 600, Bold 700). Chosen over Lora or EB Garamond because it
was drawn for screen text at interface sizes rather than adapted from
a print face, and over any commercial face because an OFL licence can
be redistributed with the manuscript without a further permission.

It is applied **only** to page titles, section headings and stat
values. Tile labels, sub-lines, chip text, buttons, body copy, chart
labels and every other piece of interface furniture stay on the
platform sans. At 13px a serif label reads as small rather than as
considered, and the whole point of a second family is the contrast.

Costs, stated plainly: two font files in the repository, a licence
line in the manuscript's tools section, and a brief fallback flash on
first web paint. The theme declares a fallback stack so a failed font
load degrades to the current appearance rather than to a broken one.

## 3. The accent palette

Added to `AppTokens`, with dark counterparts tuned the same way the
existing dark set was — same relationships, not art-directed separately.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `accentPlum` | `#5B4C8A` | `#A99AD4` | first series / tile |
| `accentSeal` | `#0B5FA5` | `#6FB0E8` | second — reuses `seal`'s hue |
| `accentPine` | `#1F6B4A` | `#6FCFA0` | third |
| `accentOchre` | `#B8722E` | `#DFA867` | fourth |
| `accentBrick` | `#B4472F` | `#E89078` | fifth |

Exposed as `AppTokens.accents` (ordered `List<Color>`) so a chart with
*n* series indexes into it rather than hard-coding, and
`AppTokens.accentsDark`.

Three of these share a hue with a meaning colour — `accentSeal` with
`seal`, `accentPine` with `endorsed`, `accentBrick` with `returned`.
That is deliberate: the palette stays small, and inventing five more
unrelated hues would make the app look like a different product.

It is also the one genuine risk in D14, and worth stating plainly
rather than glossing. A coordinator overview shows a pine tile badge
and a green `endorsed` status chip *on the same screen*, so the claim
cannot be that the two sets never meet. What keeps it safe is narrower:

- Accents appear **only** inside a tile badge or a chart segment.
  Meaning colours appear **only** on status chips, buttons and text.
  The two never share a component.
- **A tile badge is never coloured by the status of the thing it
  counts.** The badge colour is fixed per tile position, so it cannot
  drift into agreeing or disagreeing with a verdict.
- Badges carry an icon, chips carry a word. A reader is never asked to
  read colour alone.

If in review the pine badge still reads as an endorsement, the fix is
to move that tile's accent, not to abandon the rule.

Documented in the `AppTokens` doc comment, which currently explains
only the meaning palette and must be extended rather than replaced.

## 4. `StatTile`

`lib/core/widgets/stat_tile.dart`. One widget, used by all four
dashboards.

```dart
StatTile({
  required String label,       // sans, 13px, muted
  required String value,       // serif, large
  String? unit,                // "/ 5" — smaller, muted, inline
  String? caption,             // sub-line
  double? progress,            // 0..1 — renders the bar, suppresses caption
  required IconData icon,
  required Color accent,       // from AppTokens.accents
  VoidCallback? onTap,
})
```

Layout: label top-left and a 38px rounded-square badge top-right, pushed
apart. Value pinned to the bottom of the card so all four in a row share
a baseline. Card padding 22, radius 12, one-pixel border plus a 4%
shadow, minimum height 148.

**Three size steps**, keyed off the tile's own width via `LayoutBuilder`
— not the screen width, so a tile placed in a narrow column behaves
correctly regardless of device:

| Tile width | Padding | Value | Badge | Min height |
|---|---|---|---|---|
| ≥ 200 | 22 | 31 | 38 | 148 |
| < 200 | 14 | 24 | 28 | 116 |

Two steps, not three. A tile narrower than 150 is not reachable through
the grid below, so no third case is specified; the compact step simply
continues to apply.

The grid is `repeat(auto-fit, minmax(150px, 1fr))` capped at 1180px
wide. This produces four across on a desktop, 2×2 at tablet and split
widths, and 2×2 compact on a 360px phone. It never collapses to a
single column at any width a real device presents, and never stretches
into wide flat strips on a large monitor.

`value` is a `String`, not a number, because several tiles show text
("Not scheduled", "Dr. Armada"). Where the value is not numeric the
caller passes a smaller size hint; the widget does not attempt to guess.

**A tile whose value is still loading shows a skeleton, never `0`.**
This project has shipped the "0 is indistinguishable from loading" bug
four times (`_ReadinessRow`, `_DefencesList`, `_AdviseeCard`, and the
adviser count). A named constructor `StatTile.async` takes an
`AsyncValue<T>` plus a `String Function(T)` formatter, rendering a
shimmer bar in place of the value while loading and a muted em dash on
error. Every tile whose source is a stream uses it; the plain
constructor is for genuinely synchronous values only.

## 5. Layout measure

`PageShell` constrains to `AppTokens.measure` (620) because it was built
for forms. A dashboard needs more. Adds `AppTokens.measureWide = 1180`
and an optional `maxWidth` parameter on `PageShell`, defaulting to the
existing value so no current screen changes.

## 6. The overviews

Every overview follows the same skeleton: greeting, one line of context,
four tiles, "Needs you", then role-specific panels.

The greeting uses the first whitespace-separated token of
`AppUser.fullName` from `currentUserProvider` — there is no separate
given-name field, and no honorific, so it reads "Good afternoon,
Maria" for everyone. Where the profile document is missing or
`fullName` is empty — which M2 proved happens — it falls back to a
plain "Good afternoon" rather than blocking the screen. **Nothing on
an overview may depend on the profile document existing**; that
mistake locked a leader out of uploads in M2.

### 6.1 Student (group leader)

Progress rail across `draft → nominationPendingConforme →
titleApproved → chapters → pre-oral → final`, deriving the current step
from `Thesis.status` plus, once `titleApproved`, chapter and defence
state.

Tiles: chapters approved (`n / 5`, with the proportion bar) · with your
adviser (`submitted` count) · next defence · your adviser.

Queue: chapters at `revise`; the thesis at `titleRejected`; a `draft`
thesis with nominations not yet submitted.

Non-leader members see the same screen. Where an action belongs to the
leader alone the row is present but says who it is waiting on, rather
than being hidden — a member who cannot see the returned chapter cannot
chase their leader about it.

### 6.2 Faculty

Tiles are mode-aware. Adviser mode: chapters awaiting your review ·
advisees · defences this week · Conforme requests. Panelist mode: panels
· title sets to review · defences this week · Conforme requests.

Queue spans both modes (D17): chapters `submitted` on advised theses ·
nominations pending this uid's Conforme · defences `completed` on
advised theses with `consolidatedAt` unset · a defence `inProgress` or
scheduled today.

### 6.3 Dean

Tiles: awaiting your approval (`nominationPendingDean`) · title defences
(`titlePendingDefence`) · defences this week · active theses.

Queue: theses at `nominationPendingDean`, then `titlePendingDefence`.

Then both chart panels, college-wide.

### 6.4 Coordinator

Tiles: active theses · awaiting your recommendation
(`nominationPendingCoordinator`) · defences this week · faculty
accounts.

Queue: theses at `nominationPendingCoordinator`, then
`titlePendingDefence`, then theses meeting defence readiness with no
defence scheduled.

Then a filterable **All theses** table (tabs: All · Nomination · Title ·
Chapters · Defence) and both chart panels.

No Score column — scores belong to M4, which is not built. The table
gains the column when M4 lands rather than showing a placeholder now.

## 7. Data

### 7.1 New

- `ThesisRepository.watchAll()` → `Stream<List<Thesis>>`, unfiltered.
- `allThesesProvider` — a `StreamProvider` over it, watching
  `signedInUidProvider` like its siblings.
- A `needsYouProvider` per role, returning a typed list of queue items
  (`label`, `detail`, `route`, `chip`). The count reads `.length` of the
  same provider (D16).

### 7.2 Permissions

**No rules change.** `match /theses/{thesisId}` already carries
`allow list: … || isCoordinator() || isDean()`, and that arm reads no
field off `resource`, so an unfiltered list is permitted. This is the
one case where the M3 finding — a list query must filter on the field
its matching arm reads — does not bite, precisely because the
coordinator arm reads nothing.

Every other number on every overview comes from a provider that already
exists and is already permitted.

`allThesesProvider` must therefore be watched **only** by the dean and
coordinator dashboards. Watched anywhere else it produces a
`permission-denied` that the reader cannot act on.

### 7.3 Charts

`fl_chart`, added with `flutter pub add` and pinned to whatever it
resolves to, recorded in `pubspec.lock`. Pure Dart, no platform
channels, works on web and Android — the two targets.

- **Stage breakdown** — donut over `allThesesProvider`, grouped into the
  five stages, coloured from `AppTokens.accents` by index. Legend to the
  side with counts; the legend alone must remain legible if the chart
  fails to render.
- **Submission trend** — theses created per month over the trailing
  seven months, from `Thesis.createdAt`. This is real data, but it says
  nothing until the system has been used for a semester; the panel
  states its own range ("Past 7 months") so an early flat line reads as
  young data rather than as a broken chart.

Both are rendered inside a fixed-height box with an `overflow` guard.
Neither is interactive.

## 8. Navigation

Index 0 becomes Overview for all four roles; existing destinations shift
down one. Two consequences:

- The student's conditional destinations (`chaptersUnlocked`) shift, so
  the index arithmetic in `student_dashboard.dart` must be recomputed,
  not merely offset.
- The coordinator's index-4 jump to `/invites` becomes index 5. That
  branch is a literal in `onDestinationSelected` and will silently
  route the wrong destination if missed — it must be driven off the
  destination list rather than a hard-coded integer.

`ResponsiveScaffold.minDestinations` is unaffected; every role already
exceeds it and now exceeds it by one more.

## 9. Error and loading handling

Each panel resolves its own `AsyncValue`. Collapsing several streams
into one `when` means a single slow query blanks the whole dashboard,
and collapsing to `data(const [])` while loading renders an empty state
indistinguishable from "nothing waiting" — the bug named in §4.

An overview whose every panel has failed still renders its greeting and
its navigation. A dashboard that replaces itself with a full-page error
strands the reader with no way to reach the screens that do work.

## 10. Testing

The standing hazards in this codebase apply directly here:

- **`fake_cloud_firestore` returns insertion order.** The All-theses
  table and the trend both order data. Fixtures seed *against* the
  expected order or the test proves nothing.
- **`pumpAndSettle` resolves streams before assertions.** Every
  loading-state test — and there are many, one per tile — pumps once
  against a never-emitting controller.
- **`fake_cloud_firestore` enforces no rules.** The claim in §7.2 that
  the coordinator may list all theses is a *rules* claim and belongs in
  the emulator suite, with a control proving a student is denied the
  same query.

Specific to this milestone:

- A tile whose source is loading renders a skeleton and **not** `0` —
  falsified by making the value emit `0` and confirming the two states
  render differently.
- The "N things need you" count equals the rendered queue length, tested
  by mutating the queue and asserting both move (D16).
- The faculty queue includes a Conforme request while in **adviser**
  mode and a chapter review while in **panelist** mode (D17). Testing
  only the matching mode would pass with the mode filter left in.
- `StatTile` at each of the three width steps, driven by a sized
  surface, asserting the padding and value size actually change.
- The coordinator's `/invites` jump still lands on `/invites` after the
  index shift (§8).

## 11. Out of scope

- **The admin slice** — user list, activate/deactivate,
  `availableAsAdviser`. Its own spec, next.
- **Score, pass rates, evaluation analytics** — M4.
- **Messages, announcements, calendar, repository, audit log, system
  health** — present in the reference redesign, absent from the
  manuscript's six modules. Adding any widens scope past the objectives
  the panel checks against.
- **Trend deltas** (D15).
- **Global search** — the reference redesign's header search spans
  collections no single role may read.

## 12. Documentation debt

- Chapter IV must describe the two-palette rule (D14) alongside the
  existing paper-and-ink justification; the accent set is a new claim
  and needs one sentence of reasoning, not a colour table.
- `fl_chart` is the first dependency added for presentation rather than
  capability, and should be named in the tools section.
- Source Serif 4 must be credited in the tools section with its SIL
  Open Font License 1.1, and `assets/fonts/OFL.txt` ships with it.
- `app_theme.dart`'s class doc comment currently states that no font
  files are bundled and explains why. D19 reverses that; the comment
  must be rewritten rather than left contradicting the code.
