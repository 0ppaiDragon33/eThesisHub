# The application shell

Navigation exists on four screens. The four dashboards use
`ResponsiveScaffold`; the other sixteen signed-in screens are bare
`Scaffold`s. Every navigation call is `context.go`, which replaces the
route rather than pushing onto it, so Flutter never draws a back arrow.

The result is that leaving a dashboard strands you. Open a chapter, a
title set, a defence room, the review queue — and there is no sidebar,
no bottom bar, no back button, and no way home except the browser's own
back control, which on Android is a system gesture and on web is
outside the app. This was reported from the field as "I don't see any
back menu while navigating on screens", and it is accurate.

This milestone puts one shell around every signed-in route, and turns
each navigation destination into a real URL.

It adds no new user-facing capability. Every screen it touches already
exists; what changes is how you reach them and whether you can leave.

## 1. What this delivers

- One `ShellRoute` wrapping every authenticated route, rendering a
  persistent sidebar, an app bar, and the current screen.
- A **collapsible** sidebar on wide screens — icon + label, or icons
  only — with the choice remembered between launches.
- A **drawer** on narrow screens, opened by a hamburger that is present
  on every screen. The bottom navigation bar is removed entirely.
- **Seven new routes**, each an inline dashboard body extracted into a
  screen of its own.
- A **back control** on screens deeper than a destination, backed by a
  real navigation stack rather than a re-navigation.
- An explicit, escapable state for a signed-in account whose profile
  document is missing or unreadable.

## 2. Decisions taken

Numbering continues from the dashboards spec, which ended at D19.

**D20 — One shell, every signed-in route.**
Not "dashboards and one level down", and not "everything except focused
screens". Two navigation patterns in one app means learning where the
rules change, and the screens most likely to strand someone — the
defence room, chapter detail — are exactly the ones a partial shell
would leave out. Login, register and verify-email stay outside it:
there is no role to build a sidebar from until someone is signed in.

**D21 — Destinations are routes, not indices.**
The dashboards currently hold `_selectedIndex` and switch their body
inline, so the URL reads `/student` whichever tab you are on. Web is
one of two targets; under that scheme the browser back button skips
every tab at once, a link cannot be shared, a refresh loses your place,
and the sidebar cannot know what to highlight on an inner screen
because the URL does not say. Making each destination a route fixes all
four at once, and is the reason this milestone is large.

**D22 — Flat, role-agnostic paths.**
Not `/student/chapters` and `/faculty/chapters`. Several screens are
genuinely shared: `/thesis/chapters` is opened by a student uploading
and by their adviser reviewing, and the router already carries a
hard-won exemption saying so. Role-prefixed paths would force such a
screen to exist at two URLs or to pick one role and read wrong for the
other. Eleven routes already have flat paths; this is mostly additive.

**D23 — Deep screens are pushed; destinations are replaced.**
`context.push` for anything below a destination, `context.go` for the
destinations themselves. This is what makes back a genuine pop that
restores the list underneath **with its scroll position**, rather than
a re-navigation that reloads it from the top. The absence of a stack is
the direct cause of the missing back arrow today.

**D24 — Highlighting is by declared ownership, not string prefix.**
Each destination names the route prefixes it owns. Naive prefix
matching would light `Defences` (`/defences`) for the defence room
(`/defence/room/:id`) — one character apart, different screens. Where
no destination owns the current URL, nothing highlights. A wrong
highlight is worse than none: it tells the reader they are somewhere
they are not.

**D25 — No code path may substitute a default role for an unknown one.**
Not `?? UserRole.student`, not an implicit fall-through in a `switch`,
not a remembered role from `shared_preferences`. Where the role is
unknown the app says so and stops. This project has twice shipped the
opposite: M2 gated an upload control on the profile document and
permanently hid it from a leader whose document was missing, and the
dashboards milestone shipped a `myDefencesProvider` that sent a
profile-less dean down the faculty code path. Both looked like working
software.

**D26 — While the role is loading, the shell renders but does not offer.**
Chrome on frame one — app bar, hamburger, sidebar frame — with the
destination list as inert skeleton rows. Not a full-screen spinner,
which would blank the app on every cold web load and trap a reader if
the read fails. Not an optimistic guess from a remembered role either:
during the guess window the sidebar would offer destinations the
account may not hold, and tapping one produces a `permission-denied`
the reader cannot act on. A skeleton cannot misroute, because there is
nothing to tap.

## 3. The route tree

```
GoRouter
├── /login  /register  /verify-email          outside the shell
└── ShellRoute → AppShell(child)
    ├── /overview                             role-aware
    ├── /thesis  /thesis/create
    │   /thesis/nominate  /thesis/titles
    ├── /thesis/chapters                      destination
    │   └── /thesis/chapters/:chapterId       deeper — pushed
    ├── /defences                             new
    │   ├── /defence/:thesisId                deeper — pushed
    │   ├── /defence/schedule                 deeper — pushed
    │   └── /defence/room/:defenceId          deeper — pushed
    │       └── …/consolidated                deeper — pushed
    ├── /advisees  /panels                    new
    ├── /approvals  /recommendations          new
    ├── /title-defences  /readiness           new
    ├── /nominations  /review  /invites
    └── /no-profile                           see §7
```

`AppShell` watches `currentUserProvider`, builds that role's
destination list, reads `GoRouterState.uri` to decide what is
highlighted, and renders `child`. Each screen keeps its own widget and
loses its own `Scaffold` and `AppBar` — the shell owns both.

## 4. The new routes

Seven, each extracting a body that is currently rendered inline by a
dashboard's `switch`:

| Route | What moves there | Currently inline in |
|---|---|---|
| `/overview` | the four Overview widgets, role-switched | all four |
| `/defences` | `DefencesList` | all four |
| `/advisees` | the adviser-mode body | faculty |
| `/panels` | the panelist-mode body | faculty |
| `/approvals` | the pending-approval queue | dean |
| `/recommendations` | the pending-recommendation queue | coordinator |
| `/title-defences` | `DefenceQueue` | dean, coordinator |
| `/readiness` | `DefenceReadinessList` | dean, coordinator |

**`/title-defences`, not `/titles`.** `/thesis/titles` already exists
for *submitting* a candidate set. Two routes a character apart meaning
different things is how `/faculty` was registered twice in M1, leaving
the invites screen unreachable — caught only because a test drove the
router rather than pumping the screen.

`homeRouteFor` returns `/overview` for every role. The four existing
home routes redirect there so nothing already bookmarked breaks.

## 5. The shell

### 5.1 Wide (≥ 900px)

`NavigationRail(extended: isExpanded)`. Material implements
collapse/expand natively — extended is icon and label at ~256px,
collapsed is icons with tooltips at ~72px — so this is not hand-rolled.
A chevron in the rail header toggles it.

The state lives in a `sidebarExpandedProvider` persisted through
`shared_preferences`, the same shape `facultyModeProvider` already
uses.

### 5.2 Narrow (< 900px)

No bottom bar. A hamburger in the app bar opens a `NavigationDrawer`
over the content with a scrim; selecting a destination navigates **and**
closes it. Because the shell owns the app bar, the hamburger is present
on every screen — the specific thing reported missing.

### 5.3 The account footer

Name, role and sign-out at the foot of the sidebar. `SignOutButton` is
currently repeated in four dashboards' `actions`; it becomes one.

### 5.4 The app bar title

Currently `'eThesisHub'` on every screen. It becomes the name of the
screen you are on. On a phone, where the sidebar is hidden behind the
hamburger, that title is the only thing saying where you are.

### 5.5 The faculty mode switch

Moves from the faculty dashboard's app bar into the shell, and appears
only for a faculty member holding both positions. Since Advisees and
Panels are now separate routes, changing mode navigates between them
and the sidebar shows whichever matches. D5 is unchanged; it lives one
layer up.

## 6. Highlighting and back

Each destination declares the prefixes it owns (D24). The highlighted
destination is the one owning the current location; where none does,
none highlights.

The same declaration decides the back control, so there is one source
of truth rather than two: a location is **deeper** when a destination
owns it but it is not that destination's own route.
`/thesis/chapters` is the Chapters destination itself, so no back
control; `/thesis/chapters/chapterIII` is owned by Chapters but is not
it, so a back control appears. A location no destination owns gets a
back control too, since the sidebar cannot return the reader anywhere
useful from there.

Because those screens are reached with `context.push` (D23), back is
`Navigator.pop`, and the list underneath survives with its scroll
intact.

## 7. Role resolution

Three states, three behaviours. The existing redirect already
distinguishes some of these; this section says what each becomes.

### 7.1 Loading

Shell chrome renders; destinations are inert skeleton rows; the child
route renders its own loading state as it does today. The redirect
already holds position while `currentUserProvider` is loading
(`loading: () => null`) — that stays.

### 7.2 Absent — the read succeeded and the document is not there

Today the redirect sends this account to `/login`, which shows a
"signed in as X — sign out" affordance. That is not silent, and it is
better than what M2 shipped, but `/login` is the wrong screen: it
implies you are not signed in, when in fact you are and something else
is wrong.

A dedicated `/no-profile` route replaces it, inside the shell, with an
empty destination list — an empty sidebar is the honest statement,
because the app genuinely does not know what this account may reach. It
says the account exists but its profile record is missing, that this
usually means registration did not finish, and offers **Retry** and
**Sign out**.

Sign out is not optional. Without it this account is trapped: no
destination is reachable and no other account can be signed into.

### 7.3 Error — the read failed

Today this returns `null` from the redirect, so the reader stays
wherever they are with no explanation at all. This is the real gap.

It routes to the same `/no-profile` screen, which distinguishes the two
cases, because the remedies differ: absent means registration did not
finish and needs a coordinator; error means offline or refused, and the
Firestore code must be shown, as `ErrorState` already does. Collapsing
them into one "something went wrong" is precisely the failure that sent
this project hunting a network problem that did not exist during the
storage-upload investigation.

A **denied** self-read is a rules defect, not a user problem: an
account may always read its own `users/{uid}`. An emulator test pins
that, so a confusing field report becomes a failing test.

## 8. Route guards

The redirect's role guards are prefix-based and carry two hard-won
exemptions — `/thesis/chapters` for advisers, `/defence/room/` for the
leader reading a consolidated log. Both must survive unchanged.

Each of the seven new routes needs its own guard:

| Route | Permitted |
|---|---|
| `/overview` | every signed-in role |
| `/defences` | every signed-in role |
| `/advisees` `/panels` | faculty, coordinator, dean |
| `/approvals` | dean |
| `/recommendations` | coordinator |
| `/title-defences` `/readiness` | coordinator, dean |

These are UX guards only. The authorization boundary remains
`firestore.rules`, and every screen's reads and writes still pass
through it regardless of what the client permits.

## 9. What happens to the dashboards

The four `*_dashboard.dart` files largely dissolve. Their destination
lists move into the shell; their bodies become the routes in §4; their
`_selectedIndex` becomes the URL.

This is a substantial refactor of code that has just been reviewed. It
is the price of D21, and it is worth paying once rather than growing a
second navigation system beside the first.

## 10. Error handling

An overview or a screen whose panels have all failed still renders the
shell and its navigation. A screen that replaces the whole window with
an error strands the reader with no way to reach the screens that do
work — which is this milestone's own subject.

## 11. Testing

The standing hazards apply. `fake_cloud_firestore` enforces no rules
and returns insertion order; `pumpAndSettle` resolves streams before
assertions.

Specific to this milestone:

- **Drive the router, do not pump the screen.** The `/faculty`
  double-registration in M1 was invisible to widget tests and caught
  only by a routing test. Every route in §4 gets one.
- Each of the seven new routes is reachable, and refuses the roles §8
  excludes — both directions, or the guard passes with the check
  removed.
- The two existing exemptions still hold: an adviser reaches
  `/thesis/chapters`, and a leader reaches `/defence/room/:id`.
  Falsified by removing each exemption and confirming the test fails.
- Collapsed and expanded both render; the choice survives a rebuild.
- Narrow renders no bottom bar, a hamburger on **a screen that is not a
  dashboard**, and a drawer that closes on selection.
- Highlighting: chapter detail highlights Chapters; the defence room
  highlights nothing rather than Defences (D24).
- Back from a pushed screen pops rather than re-navigating. Assert on
  the observable consequence, not on the mechanism: scroll a list, push
  a detail screen, go back, and assert the scroll offset is unchanged.
  A re-navigation returns the list at offset zero, so the test fails if
  `push` is ever swapped back to `go`.
- A missing profile reaches `/no-profile` and **no dashboard** (D25),
  with a working sign-out.
- A failed profile read reaches `/no-profile` and shows the Firestore
  code, distinguishably from the absent case.
- While the role is loading, the sidebar renders skeleton rows and no
  tappable destination — single `pump()`, never `pumpAndSettle`.

## 12. Out of scope

- **The admin slice** — user list, activate/deactivate,
  `availableAsAdviser`. Still its own spec.
- **M4 evaluation.**
- **Grouped sidebar sections** ("OVERVIEW", "ACADEMIC", "RESOURCES")
  from the reference redesign. With four to six destinations per role,
  section headers cost more vertical space than they buy clarity. They
  become worth revisiting if a role ever exceeds eight.
- **Badge counts on sidebar items.** The reference shows them; they
  would each need a live count provider, and the "Needs you" queue
  already answers "what wants me" in one place.
- **Messages, Calendar, Repository, Forms, Audit Log** — not in the
  manuscript's six modules.

## 13. Documentation debt

- Chapter IV's navigation section describes a bottom bar and a rail.
  Both are replaced.
- `ResponsiveScaffold`'s doc comment explains why navigation hides
  below two destinations. That rule survives, but the widget it lives
  in does not; the reasoning moves to `AppShell`.
- The redirect's two exemption comments are among the most valuable in
  the codebase. They must move with the guards, not be summarised away.
