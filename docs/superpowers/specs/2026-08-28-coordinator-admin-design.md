# The coordinator admin slice

The Chapter I role table gives the coordinator four administrative
duties: provision faculty accounts, assign advisers under Guidelines
§1e, monitor all theses, and manage the archive. Only the first is
built — `/invites` issues faculty invitations. There is nowhere to see
who holds an account, nowhere to deactivate one, and nothing anywhere
that decides who a group may nominate.

This milestone builds the account half. It also closes a defect the
design uncovered: a faculty member with no positions yet is silently
put into panelist mode with an empty screen and no way out.

§1e itself — the coordinator assigning an adviser to a group that
could not secure one — is **not** in this milestone. It is a separate
spec, and it will build on the designation this one introduces.

## 1. What this delivers

- A **Users** destination replacing the current Faculty one, with two
  tabs: **Accounts** and **Invites**. Invites move under it unchanged.
- A list of every account — name, email, role, current positions —
  filterable by role and by active state.
- **Activate and deactivate**, already permitted by the rules and
  currently unreachable from anywhere in the app.
- **Nomination designation**: per account, whether they may be
  nominated as an adviser, as a panelist, both, or neither.
- A revision of **D5** so the faculty mode switch is driven by
  designation as well as by positions held.

## 2. Decisions taken

Numbering continues from the app-shell spec, which ended at D26.

**D27 — Designation is the authority; the directory is a mirror.**
`facultyDirectory` is a client-written mirror maintained by its own
subject at sign-in (`mayWriteOwnDirectoryEntry()`). The rules already
carry the reasoning, at the ex-officio check: *"the directory is a
client-written mirror … trusting it here would make ex-officio status
self-declarable"*. Designation therefore lives on `users/{uid}`, which
only a coordinator may write and only in named fields. The directory
carries a copy so the nomination picker can filter, written by the
coordinator rather than by the subject. That mirror is not free: it
takes three changes to a security-critical rule, and §4.2 sets out
exactly what and why.

**D28 — The nomination rule verifies designation against `users`.**
Filtering the picker is a UX guard. `firestore.rules` is the only
authorization boundary on the Spark plan, so the nomination `create`
rule reads `users/{nomineeUid}` and refuses a nomination whose
position the nominee is not designated for. This reuses the pattern
the ex-officio check already established for exactly this reason.

**D29 — Designation gates the picker, so designation and position
cannot disagree going forward.** A student cannot nominate someone who
is not offered. This dissolves the question of which wins: they can
only disagree *backwards*, for someone already placed when their
designation is narrowed.

**D30 — Capability is the union of designation and positions held.
Neither subtracts.** Designation adds what you may become; a position
you already hold always grants access. A faculty member narrowed to
adviser-only who already sits on three panels keeps those panels in
their own app. The alternative — designation simply winning — would
make an approved, live responsibility vanish from the screen of the
person who has to discharge it. This project has shipped that failure
twice: M2 permanently hid a group leader's upload button, and the
dashboards milestone routed a profile-less dean down the faculty code
path. Both looked like working software.

**D31 — Designation is uniform across roles. No role-specific rules.**
Not "the coordinator is always an adviser". The institution has two
kinds of coordinator — a department coordinator who advises and a
college coordinator who holds no advisees — and the app has one
`coordinator` role. The toggle expresses that difference without a
second role, which is why no second role is introduced.

**D32 — Ex-officio seats bypass designation.** The coordinator and dean
sit on panels by office. That seat is conferred by the office, not by a
coordinator's list, and must not be blocked because someone forgot to
tick a box.

**D33 — A new account is designated both.** Not neither. Neither is a
legitimate state — someone on leave — but it is also what every freshly
invited account would look like before anyone reached this screen, and
that would make new faculty silently unpickable with no error anywhere.
The coordinator narrows; they never have to enable.

## 3. Data model

Two boolean fields, on both records:

```
users/{uid}
  … existing …
  nominableAsAdviser   bool   default true
  nominableAsPanelist  bool   default true

facultyDirectory/{uid}
  … existing …
  nominableAsAdviser   bool   mirror, coordinator-written
  nominableAsPanelist  bool   mirror, coordinator-written
```

Two booleans rather than one enum, because the four states are a
product of two independent facts and a reader of the document should
not have to decode `'adviserOnly'`.

**Absence reads as `true`.** Every account that exists today predates
these fields; a missing value must mean "nominable", or deploying this
would make every current faculty member unpickable at once. `AppUser`
and `FacultyDirectoryEntry` both default a missing key to `true` on
read (D33 in the model layer, not only in the screen).

## 4. Permissions

Three rules changes. Everything else this milestone needs is already
permitted.

### 4.1 `users` — extend the coordinator arm

```
allow update: if isCoordinator()
              && request.auth.uid != uid
              && onlyChanged(['fullName', 'college', 'program',
                              'specialization', 'active',
                              'nominableAsAdviser',
                              'nominableAsPanelist']);
```

The two additions are the whole change. `role` stays unwritable, the
self-edit ban stays, `allow delete: if false` stays.

**Consequence, stated because it is easy to miss:** this arm already
lets a coordinator edit the *dean's* account, including deactivating
them. That is pre-existing for `active`; this extends the same
authority to designation. With two coordinators and a self-edit ban,
coordinators designate each other. Both are properties of the existing
rule, not new ones, and neither is a security hole — but they are the
kind of thing an examiner asks about.

### 4.2 `facultyDirectory` — three changes, not one

This is the most delicate change in the milestone, and it is more than
adding an arm. `mayWriteOwnDirectoryEntry()` currently pins:

```
request.resource.data.keys().hasOnly(
  ['fullName', 'role', 'college', 'specialization'])
```

`upsertOwnEntry` writes with `SetOptions(merge: true)`, and the
repository's own comment records what that means: *"under
`SetOptions(merge: true)` `request.resource.data` is the merged
**result**, not the written subset, so `keys().hasOnly([...])` and the
`role == myRole()` pin both still apply to the whole document."*

So adding two designation fields to an entry makes that faculty
member's next sign-in produce a six-key document, `hasOnly` fails, and
**their routine directory upsert is refused.** Designating someone
would break their sign-in housekeeping. The comment that catches this
was written for an earlier finding, and it must survive this change.

Three edits, all required together:

1. **Widen `hasOnly` to six keys**, so a merged result carrying
   designation is accepted.
2. **Pin designation against the subject.** Widening `hasOnly` would
   otherwise let a faculty member write their own designation — exactly
   what D27 exists to prevent. On update, the subject's write must
   leave both fields equal to their current values; on create it must
   not carry them at all. Absence still reads as `true` (§3).
3. **Add a coordinator arm** that may change only the two designation
   fields, and only on an entry that already **exists**. A coordinator
   may not create a directory entry: that would put a nameless row in
   the nomination picker.

### 4.2.1 The sync window, stated plainly

A faculty member invited and designated but who has **never signed in**
has no directory entry. Their designation lives on `users/{uid}` alone.
When they first sign in, `upsertOwnEntry` creates their entry
**without** designation — it cannot write those fields — so the entry
reads as nominable for both (§3) while `users` may say otherwise.

During that window the picker offers them for a position the
nomination rule (§4.3) will refuse. Nothing is corrupted and nothing is
exposed; a nomination simply fails.

**Two mitigations, both required.** The Users screen marks accounts
with no directory entry as *"not yet signed in"*, so a coordinator can
see that a designation has not reached the picker. And the nomination
refusal must say what happened in words — *"Dr. X is not available as a
panelist this semester"* — never a raw permission code. A student who
picked someone from a list the app showed them must not be told the
security rules refused it.

### 4.3 `nominations` — verify designation

The `create` rule gains a check reading `users/{nomineeUid}`: a
nomination whose `position` is `adviser` requires
`nominableAsAdviser`; `panelist` requires `nominableAsPanelist`. An
ex-officio nomination is exempt (D32).

**Read from `users`, never from `facultyDirectory`** — the directory is
self-written and would make designation self-declarable, which is the
finding D27 exists to avoid.

## 5. The Users screen

`/users` is the Accounts tab; `/invites` remains its own route for the
Invites tab. One destination owns both:

```dart
ShellDestination(label: 'Users', route: '/users', alsoOwns: ['/invites'])
```

This is the first thing to populate `alsoOwns`. A finding deferred
during the app-shell milestone applies: `destinationForLocation` sorts
candidate matches by `d.route.length` rather than by the length of the
root that actually matched. No other destination owns `/invites`, so
the tiebreak never fires and this is safe — but the finding moves from
dormant to one-competitor-away, and this milestone fixes it rather than
leaving an armed trap for whoever populates `alsoOwns` next.

### 5.1 Each row

Name, email, role, **current positions**, designation, active.

Positions are shown *because* of D30: a coordinator narrowing someone
needs to see that they already sit on three panels, since those seats
survive the narrowing and the designation will then disagree with
reality. The row says so at the moment of choosing rather than leaving
it to be discovered.

### 5.2 What the screen refuses, visibly

- `role` is text, not a control. A coordinator may never write it.
- The coordinator's own row renders with its controls disabled and the
  reason stated. Hiding the row would be stranger than showing it.
- There is no delete anywhere.

A control that fails when tapped reads as a broken app rather than an
unfinished one — the rule `ResponsiveScaffold` established and
`AppShell` inherited.

### 5.3 Filters

By role and by active state, defaulting to active accounts with
students hidden. Students appear in the list — otherwise nothing
anywhere can deactivate a graduated student — but they carry no
designation, which is meaningless for a role that cannot be nominated.

## 6. The D5 revision

`faculty_mode_provider.dart:85-87` currently ends:

```dart
return FacultyMode.panelist;   // reached when both counts are 0
```

So a faculty member with no positions of either kind is put into
panelist mode, with no switch and an empty screen. That is every newly
invited account.

Effective capability becomes the union of designation and positions
held (D30):

| Designated | Holds | Effective | Switch |
|---|---|---|---|
| both | nothing | both | yes |
| adviser | nothing | adviser | no |
| panelist | nothing | panelist | no |
| adviser | 3 panels | both | yes |
| neither | nothing | neither | no destination |
| neither | 2 advisees | adviser | no |

**"Neither" declares no mode destination at all.** Not an empty
Advisees screen. Someone on leave sees Overview, Defences and
Nominations, which is honest.

Two consequences: the mode switch moves from "holds adviser positions"
to "holds both capabilities", and `pendingInOtherModeProvider` yields
zero rather than computing against a mode the reader cannot reach.

**Degradation.** The mode now depends on the profile document. A
faculty member may read their own `users/{uid}` (the `get` rule
permits `request.auth.uid == uid`), so this works — but if that read
fails, the union falls back to **positions alone**, which is exactly
today's behaviour. Nothing may depend on `users/{uid}` existing in
order to render.

## 7. Error handling

Each panel resolves its own `AsyncValue`. A failed positions query must
not blank the account list, and a failed account list must not blank
the screen — the row shows what it knows and says what it could not
load.

A refused write says which write was refused. The screen shows the
Firestore code, as `ErrorState` already does; a coordinator hitting the
self-edit ban through some path the UI did not anticipate must be told
that, not "something went wrong".

## 8. Testing

The standing hazards apply. `fake_cloud_firestore` enforces **no
rules**, so every permission claim in §4 belongs in
`rules-test/rules.test.js` and nowhere else. It returns documents in
**insertion order**, so the account list's ordering fixture is seeded
against the expected order. `pumpAndSettle` resolves streams before
assertions, so loading tests pump once.

Specific to this milestone:

- **Every rule in §4, both directions, with controls.** A coordinator
  may write the two designation fields; a coordinator may **not** write
  `role` in the same update; a coordinator may not write their own
  account; a faculty member may not write their own designation in
  either collection. That last one is D27's whole point and is the test
  that matters most.
- A nomination naming an adviser-only nominee as a panelist is
  **refused by the rules**, not merely absent from the picker (D28).
  With a control proving the same nomination succeeds once the nominee
  is designated.
- An ex-officio nomination succeeds regardless of designation (D32).
- An account document with **no** designation fields reads as nominable
  (§3), so the deploy does not silently unpick everyone.
- The mode table in §6, every row. The "designated adviser, holds
  panels" row is the one that proves D30 — testing only the agreeing
  rows would pass with the union replaced by designation alone.
- A faculty member whose profile read fails still gets a mode from
  positions alone (§6 degradation).
- `/users` and `/invites` both highlight the Users destination, and
  neither is reachable by a non-coordinator.

Because §4.2 widens a security-critical `hasOnly` and adds a pin, three
tests exist solely to prove the widening did not open what it widened:

- **A faculty member's ordinary sign-in still succeeds on an entry that
  carries designation.** This is the regression §4.2 exists to avoid —
  without the widening, designating someone breaks their sign-in
  housekeeping. Falsified by narrowing `hasOnly` back to four keys and
  confirming the test fails.
- **A faculty member may NOT change their own designation** through the
  now-widened directory write, in either direction, on create or on
  update. This is D27's whole point, and the widening is exactly what
  would break it.
- **A coordinator may not CREATE a directory entry**, only update one
  that exists — otherwise a nameless row reaches the nomination picker.

## 9. Out of scope

- **§1e adviser assignment.** Its own spec, building on this one.
- **The archive**, the fourth administrative duty.
- **A `track` or specialization match** between adviser and thesis.
  `specialization` exists on the user record but nothing compares it to
  a thesis, and the coordinator's track-holding is context the app does
  not need to encode.
- **Ranking or hinting in the picker.** One order, no priority.
- **A second coordinator role** for department versus college. D31.

## 10. Documentation debt

- D5's statement in the project design doc describes a mode derived
  purely from positions held. It is revised, not replaced, and the
  entry must say so.
- The Chapter I role table lists four coordinator duties; two remain
  unbuilt after this milestone (§1e and the archive) and the manuscript
  should not imply otherwise.
