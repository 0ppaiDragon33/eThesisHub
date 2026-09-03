# M3 — Defence scheduling and live comments

**Date:** 2026-08-22
**Status:** approved for planning
**Parent:** `2026-08-12-ethesishub-design.md` §5.3, §4, §9.2 (M3)
**Depends on:** M1a (nomination), M1b (title defence), M2 (documents)
**Feeds:** M4 (evaluation) reads these defences and adds `evaluations/{evaluatorUid}`

Objective 2 (scheduling half), and the last piece of the minimum defensible
build (skeleton + M1 + M2 + M3). It is also the distinctive feature: no system
reviewed in Chapter II has live multi-role defence commenting.

## 1. What this milestone delivers

The coordinator schedules a pre-oral or final defence. At the appointed time
they open it, and the adviser, panel, coordinator and dean file comments that
appear live for every participant. The coordinator closes it, freezing the
log. The adviser consolidates the comments into the bracketed per-commenter
block Guidelines §4d requires, and releases it — which is the moment the group
can read it.

## 2. Decisions taken

| # | Decision | Rationale |
|---|---|---|
| M3-1 | Defences get **their own `comments` collection**; M1b's `titleComments` is left untouched | M1b was verified in the field this week. Unifying the two would rewrite working code and migrate live data for a tidier diagram. The widgets are shared; only the collections differ |
| M3-2 | The group reads comments **only after the adviser releases the consolidation** | Guidelines §4d makes the adviser the one who consolidates and furnishes the copy. The students hear the remarks in the room; what they need afterwards is the agreed list, not raw keystrokes — including ones the panel withdrew mid-sentence. Mirrors M1b, where comments were hidden until the decision |
| M3-3 | Scheduling **warns but does not block** when chapters are not approved | Departments book rooms and panels weeks ahead. A hard block would keep a group whose Chapter III is approved the day before off the schedule entirely. M2's readiness is shown at the point of decision, which is where it earns its keep |
| M3-4 | `scheduled → inProgress → completed`, driven by the **coordinator** | Commenting is permitted only while `inProgress`, which is what makes the log a record of the room rather than a document anyone can append to later |
| M3-5 | Completing a defence **does not move the thesis status** | M4's verdict does. Consistent with M2: nothing fires without someone pressing it |
| M3-6 | `panelUids` and `adviserUid` are **snapshots** on the defence | If the panel changes next semester, last semester's record must still say who actually sat. The thesis is the live truth; the defence is the historical one |
| M3-7 | **`editedAt` is dropped** from the committed comment shape | §5.3 says append-only and §6.4 makes it a rule. A field recording an edit the rules forbid is a promise the system contradicts. One item of documentation debt |
| M3-8 | The **panel gains read access to chapters** here | M2 deferred it deliberately — the panel meets the document at the pre-oral defence, which is this milestone. One arm added to M2's rules |

## 3. Data model

Top level, because a defence is an event rather than a property of a thesis.

```
defenses/{defenseId}
  thesisId
  type              'preOral' | 'final'
  scheduledAt
  venue
  panelUids[]       snapshot, copied from the thesis at scheduling
  adviserUid        snapshot, same reason
  status            'scheduled' | 'inProgress' | 'completed'
  createdBy, createdAt
  consolidatedAt    set when the adviser releases the summary; absent until then

  comments/{commentId}
    authorUid, authorName, text, createdAt
    authorPosition    'Adviser' | 'Panel Member' | 'Coordinator' | 'Dean'
```

`authorPosition` is the label the consolidation prints in the bracket, so it
is stored rather than derived: the position someone held at the defence must
not change when their account role changes later.

`type` covers only `preOral` and `final`. The title defence keeps M1b's own
collection (M3-1).

`consolidatedAt` is a single timestamp, not a stored copy of the text. The
consolidation is a *view* over the same append-only comments, so it cannot
drift from what was actually said.

## 4. Lifecycle

```
scheduled    booked; no comments may be written
   |  coordinator opens
inProgress   the panel may comment; every client holds a listener
   |  coordinator closes
completed    the log is frozen; the adviser may consolidate and release
```

Comments are writable **only while `inProgress`**. This is the same shape as
M2's status arms: a write permitted only against a particular parent state.

**Accepted risk.** The coordinator sometimes has a class, so a defence cannot
start if they are absent. Adding the adviser to that one rule arm is a
two-line change if it bites in practice.

## 5. Permissions

`firestore.rules` is the only authorization boundary on this project — the
Firebase Spark plan has no Cloud Functions.

| Path | get / list | create | update | delete |
|---|---|---|---|---|
| `defenses/{id}` | leader, adviser, panel, coordinator, dean | coordinator only; `status == 'scheduled'`; `panelUids`/`adviserUid` must match the thesis; no `consolidatedAt` | **coordinator arm:** `status` only, and only `scheduled → inProgress` or `inProgress → completed` — never backwards, never skipping · **adviser arm:** `consolidatedAt` only, only once `status == 'completed'`, and only if it was previously absent | never |
| `comments/{id}` | adviser, panel, coordinator, dean · **leader only once `consolidatedAt` is set** | adviser, panel, coordinator, dean; only while `status == 'inProgress'`; `authorUid` pinned to the caller | never | never |

Two arms carry the weight of the whole module and must each have a control in
the rules tests: a comment written while `scheduled` or `completed` is denied,
and a leader reading comments before `consolidatedAt` is denied.

### 5.1 Listing defences

Each role reaches its own defences by a query the rules permit:

- **leader** — `where('thesisId', isEqualTo: <their thesis>)`
- **adviser** — `where('adviserUid', isEqualTo: uid)`
- **panel** — `where('panelUids', arrayContains: uid)`
- **coordinator, dean** — unfiltered list

Each needs a matching `allow list` arm evaluated per returned document, and
the `arrayContains` query needs a composite index if combined with an
ordering. Probe the index requirement against the emulator rather than
assuming: a missing index surfaces as `failed-precondition`, which
`ErrorState` already names.

### 5.2 The M2 rules change

`documents/{chapterId}`, `versions/{n}` and `feedback/{id}` gain a panel arm,
so a panel member can read the chapters they are about to hear defended. The
dean's existing split stands — status but not contents.

## 6. Consolidation

Grouped per commenter, in the order they first spoke:

```
[Dr. Noel A. Armada — Adviser]
  Revise the statement of the problem to be measurable.
  Add the sampling frame to Chapter III.

[Dr. Louella C. Diamante — Panelist]
  Justify the choice of respondents.
```

M1b's `consolidatedComments()` already produces exactly this shape and is
reused rather than reimplemented.

## 7. Screens

| Screen | Who | What |
|---|---|---|
| Schedule a defence | coordinator | Type, date/time, venue; panel and adviser copied from the thesis. Calls M2's `readinessOf` on the thesis's chapters and warns — but allows — when the gate for the chosen type is unmet (M3-3) |
| Defence room | adviser, panel, coordinator, dean | The live log, a comment box while `inProgress`, and the open/close control for the coordinator |
| Consolidated comments | the above, plus the leader after release | The bracketed blocks; the adviser also gets the release control |
| Upcoming defences | every role, filtered per §5.1 | Slots into the existing destinations — Panels for faculty, Defences for dean and coordinator, Thesis for the student |

Reuses `PageShell`, `ErrorState`, `LoadingState`, `EmptyState`, M1b's comment
list and composing indicator, and `ChapterStatusWords`.

Every state — loading, error, empty, denied — renders inside a `Scaffold`
with an `AppBar`. A bare `PageShell` has no navigation and strands the user.

## 8. Error handling

Every stream whose permission depends on the caller watches
`signedInUidProvider`. A plain `StreamProvider` is built once for the life of
the container, so a listener refused under one account stays in `AsyncError`
until the page reloads.

The live comment listener is the first in this system that a user holds open
for an hour while others write to it. A dropped connection must surface as an
error rather than a silently stale list: a panel member who thinks nobody else
is commenting will repeat points already made, which is the exact problem the
live log exists to prevent.

## 9. Testing

- **Rules tests** in the emulator for every arm, each with a control proving
  the deny is not passing for an unrelated reason.
- **The two load-bearing denials** get two-sided tests: commenting outside
  `inProgress`, and a leader reading before `consolidatedAt`.
- **Repository tests** for each lifecycle transition and each denied one.
- **Widget tests** for every screen, with loading branches pumped bare —
  `pumpAndSettle` resolves the stream first and the test then observes the
  settled state, proving nothing.
- **Every test falsified** by reverting the code under it.

`fake_cloud_firestore` enforces no rules and returns documents in insertion
order. A permission or ordering test that never sees wrong data proves
nothing.

## 10. Out of scope

Verdicts, scores and grades (M4). Notifications (M5). Generated forms (M6).
Panel availability polling, room booking, calendar integration, rescheduling
workflows, and attendance tracking.

## 11. Documentation debt

Two new items for the parent spec §11:

> `defenses/comments` drops `editedAt`. The field recorded an edit that §5.3
> and §6.4 forbid outright.

> `defenses` gains `adviserUid` and `consolidatedAt`. The first is the
> historical snapshot of who advised; the second is what releases the
> consolidation to the group.
