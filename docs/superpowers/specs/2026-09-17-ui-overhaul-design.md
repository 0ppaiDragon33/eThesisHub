# UI overhaul — foundation and entry screens

The app was built milestone by milestone, and it looks like it. Each
screen hand-rolled its own `Card`-with-a-`ListTile`, its own spacing, its
own title block. The dashboards were restyled once (accent palette,
Source Serif 4, stat tiles); almost nothing else was. Several screens are
still the walking skeleton they were scaffolded as.

Measured before writing this: **35 screens**. `forms_screen.dart` alone
hand-rolls **29** `Card`/`ListTile` blocks. The five entry screens use no
shared scaffolding at all. Two queue screens do not even use `PageShell`.

## 0. Scope

**This spec covers Phase 0 and Phase 1 only.** The overhaul is too large
for one spec, so it is decomposed into five phases, each with its own
spec, plan and PR, each shippable alone:

| Phase | Covers | Screens |
|---|---|---|
| **0 — Foundation** | The document primitives everything else composes from | none |
| **1 — Entry** | login, register, verify-email, no-profile, deactivated | 5 |
| 2 — Queues | Approvals, Recommendations, Review queue, Stalled, Panels, Advisees, Title defences, Readiness, Archive, Notifications, Nomination inbox, Archive queue | ~12 |
| 3 — Workflow | nominate, chapters, chapter detail, defence room, evaluation, grades, consolidated, schedule, submit titles, title defence, archive entry, thesis status, create thesis, users, invites | ~15 |
| 4 — Forms | `forms_screen.dart` — a catalogue, not a queue | 1 |

Phases 2–4 are named here so the decomposition is on record; they are not
designed by this document.

**Phase 0 is not skippable.** The complaint being answered is
inconsistency, and inconsistency is what happens when each screen invents
its own layout. Skinning screens before the primitives exist would add a
fourth dialect to the three already in the codebase.

## 1. Decisions taken

Numbering continues from the grading-gate spec, which ended at D77.

**D78 — The visual direction is a document, not a deck of cards.**
Content sits on ruled rows under a hard section rule, rather than inside
nested bordered panels. The tokens are already a paper-and-ink set —
`ink`, `paper`, `rule`, `seal`, `endorsed` — and a register-like
treatment uses them instead of fighting them with another layer of boxes.
It is also the cheapest treatment to apply across 35 screens and the
hardest to make cluttered.

Rejected: a panelled treatment (the app shell is already a panel, so
panels inside it become boxes within boxes) and a main-plus-rail split
(most of these screens have no secondary content to fill a rail, and it
doubles the layout work per screen).

**D79 — The component set is designed fresh; the tokens are not touched.**
There is untracked prior work in a stash (`brand_panel.dart`,
`components/panels.dart`, ~1,100 lines) proposing a panelled vocabulary.
It is not adopted: its direction is the one D78 rejects, and inheriting a
half-finished foundation is worse than writing the primitives this
direction actually needs.

No colour changes. No palette shift. `test/core/design_system_test.dart`
pins the current tokens and **must keep passing untouched** through Phase
0 — if this phase turns those tests red, something has gone wrong.

**D80 — `PageShell` and `states.dart` are extended, never replaced.**
`PageShell(title, subtitle, children, scrollable, maxWidth)` already
scaffolds a page and **26 screens** already use it;
`EmptyState`/`ErrorState`/`LoadingState` already exist and already
distinguish the three states properly. Rewriting either would churn
working screens for no gain. `PageShell` gains one optional `kicker`
overline and nothing else changes.

**D81 — The emblem is drawn in code, in seal blue.** A mortarboard inside
a rounded square (Material's `Icons.school`), not a shipped image: it
stays sharp at every size it appears (56px brand pane, 40px auth, 26px
app bar) and can recolour itself for dark mode.

It is **seal blue**, not the purple of the reference image. The purple
would otherwise be the only purple in a product whose every primary
button, link and active nav item keys off `seal`, which reads as borrowed
rather than designed. Adopting purple properly (re-tuning every accent,
and re-checking `endorsed` green and `returned` red for distinguishability
against it) was considered and judged not worth the churn.

**D82 — The entry screens are a split masthead with the form in a card.**
Desktop: a seal brand pane at ~42% beside the form. Phone: a brand band
above it. The form sits in a card in both, so it reads as one object.

The five-field register screen was mocked as the stress test before this
was settled — it is the screen most likely to break a shared scaffold,
and the split holds because the card simply grows.

**D83 — The keyboard is never detected; the brand band scrolls.**
The band lives INSIDE the scroll view, and `resizeToAvoidBottomInset`
stays at its Flutter default of `true`.

This is the whole mechanism. `Scaffold` already shrinks the viewport to
the space above the keyboard, and a focused `TextField` already calls
`Scrollable.ensureVisible` — so a field cannot end up hidden behind the
keyboard. Putting the band inside the scrollable means it simply scrolls
away when typing starts, giving register's five fields the full viewport.

Rejected: reading `MediaQuery.viewInsets` to collapse or animate the band.
That is a second mechanism to get wrong for a problem the framework has
already solved, and a fixed band outside the scroll view would
permanently consume part of an already-shrunken viewport.

## 2. Structure

```
lib/core/components/
  document.dart        SectionRule, RecordRow, FormRow, KeyFacts   (new)
  brand.dart           BrandEmblem, AuthScaffold                   (new)
lib/core/widgets/
  page_shell.dart      + optional `kicker`                         (modified)
```

### 2.1 The primitives

**`SectionRule`** — the band opener: an uppercase label, an optional
trailing count or control, and a hard bottom rule. Replaces the panel
header that D78 removes.

**`RecordRow`** — the load-bearing one. A ruled row carrying an optional
leading badge, a title, a subtitle and a trailing action or status. Twelve
queue screens currently hand-roll `Card` + `ListTile` for exactly this
shape; Phase 2 replaces all of them with this. It is specified in Phase 0
rather than Phase 2 because the entry screens' error and notice rows use
the same row rhythm, and a primitive designed against two consumers is
better than one designed against a single screen.

**`FormRow`** — the field treatment: an overline label above an underlined
input. Screens currently pass their own `InputDecoration` per field, which
is the direct cause of forms looking different from each other.

**`KeyFacts`** — label-and-value pairs for detail contexts. Used lightly in
Phase 1 (the no-profile and deactivated screens state an account fact);
it earns its keep in Phase 3.

**`BrandEmblem`** — D81's mark. Takes a size and optional foreground and
background; defaults to seal.

**`AuthScaffold`** — D82's split: brand pane plus card on wide surfaces, band
plus card on narrow, both inside one scroll view per D83. Takes the card's
children, a title and a subtitle.

### 2.2 The entry screens

All five compose `AuthScaffold`. Their logic, validation, error handling and
providers are untouched — this phase changes presentation only. Concretely:
`login_screen.dart`, `register_screen.dart`, `verify_email_screen.dart`,
`no_profile_screen.dart`, `deactivated_screen.dart`.

`institutional_domain_notice.dart` and `password_strength_meter.dart` are
existing widgets used by these screens; they are restyled to sit inside the
card but keep their behaviour and their tests.

## 3. Testing

Phase 0 adds widget tests per primitive: that `RecordRow` renders its
trailing slot, that `SectionRule` renders its count, that `FormRow` labels
its input, that `BrandEmblem` honours an override colour.

Phase 1 adds, per entry screen, that it renders at a narrow surface and at
a wide one — the two layouts D82 creates are the regression risk, since a
change that fixes one can silently break the other.

One test pins D83 specifically: with a simulated bottom inset, the focused
field remains reachable. That is the failure this design was questioned on,
so it gets a test rather than a promise.

`design_system_test.dart` is expected to pass unchanged throughout (D79).
Every existing auth-screen test is expected to keep passing: this phase
changes presentation, not behaviour, so a red behavioural test means the
restyle broke something it should not have touched.

## 4. Out of scope

- **Phases 2–4** (§0). Named, not designed here.
- **A decline path for nominations, and a "Decided" section.** Raised
  during design; they do not exist today — there is no rejected status in
  `ThesisStatus`, no decline method, and no rules arm, so approve is the
  only button because declining was never built. This is a feature
  milestone, not a restyle, and its semantics must be read out of the
  Guidelines (the §1e fallback) rather than invented.
- **Deadlines on queue rows** ("Due in 3 days"). There is no deadline data
  anywhere in the model — zero references to `deadline`, `dueAt` or
  `dueDate`. Displaying one would mean fabricating information on a screen
  a defence panel will read. It is blocked on the Guidelines lead-time work
  already sitting in the backlog.
- **Master-detail, action confirmations and bulk actions.** Real and wanted,
  but they belong to the queue family — Phase 2.
- **Dark mode rework.** The tokens already carry dark variants and the
  primitives honour them; no separate dark design pass is planned.

## 5. Open decision

**The brand pane's sentence is not chosen.** The mockups carried
*"Nomination, defence and the thesis record — in one place, for the whole
college"* as a placeholder. On a projector this is the first line a panel
reads, so it is the owner's sentence to write, not the implementer's.

Phase 1 cannot ship without it. Until it is chosen, implementations should
use the placeholder above and keep it in ONE constant so replacing it is a
one-line change rather than five.
