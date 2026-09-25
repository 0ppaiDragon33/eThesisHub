# Defence stages and re-defence — design

**Status:** approved in conversation 2026-09-25; awaiting written-spec review.
**Branch:** docs/ui-overhaul-spec.

## 1. What this is for

Faculty feedback asked for three things:

1. **The adviser sees the title defence.** Today only panel members reach it.
2. **One Defences page, split by stage.** A switch in the style of the
   existing List / Calendar toggle, reading **Title defence | Pre-oral |
   Final defence | Re-defence**. The title defence moves in from its own
   page.
3. **Re-defence.** When the panel's verdict on a pre-oral or final defence is
   **Fail**, the group defends that stage again. The app has no such thing
   today: a verdict is Pass or Fail and nothing follows a Fail.

Success: an adviser in adviser mode can open their advisee's title defence
from the Defences page or the Advisees page. Every role finds each stage
under one switch. A failed pre-oral or final defence leads to exactly one
re-defence of that stage, which runs through the same room, evaluation,
grades and verdict as the original.

### What the user said vs. what this spec assumes

| Said | Assumed (open to correction) |
|---|---|
| Re-defence = defend again after a Fail | The Coordinator schedules it, as for any defence |
| Pre-oral and final only; a rejected title set keeps the current resubmit flow | It uses the thesis's same panel (the create rule already pins the panel to the thesis) |
| The number of re-defences is for the faculty to decide | **One per stage** until they answer (§10) |

## 2. Findings that shaped the design

- **Why the adviser misses the title defence.** The faculty sidebar shows
  **Advisees** or **Panels** by faculty mode, never both
  (`shell_destination.dart`). The only "Open title defence" link is in
  `PanelRegister` on `/panels`. The rules already let the adviser in:
  `isOnPanel()` includes `t.adviserUid`. `TitleDefenceScreen` already labels
  them "Adviser". So this is a missing link, not a permission.
- **Title defences have no date.** They are a thesis status
  (`titlePendingDefence`), not a `defenses` document. The List / Calendar
  toggle cannot apply to them.
- **Re-defence can reuse everything.** A defence document is the unit the
  room, comments, consolidation, evaluation, grades and verdict hang off.
  The gates that ask "did the final defence pass" (`manuscript_upload.dart`,
  `archive_queue_screen.dart`, `archive_providers.dart`) test
  `type == final_ && panelVerdict == pass`. The progress rail reads the
  defence type. All of them count a passed final **re-defence** correctly,
  unchanged, as long as a re-defence is a defence of the same type.

## 3. Approach

A re-defence is an ordinary `defenses` document of the same `type` as the
defence it re-does, with one extra field, `redefenceOf: <failed defence id>`.
Its document id is `<failed defence id>_redefence`, so a second re-defence
of the same Fail cannot be created.

Rejected alternatives:
- **A `round` number on each defence.** It loses the link to the specific
  failed defence, and "one per stage" becomes hard to enforce in rules.
- **A separate re-defence collection.** It would duplicate the room,
  evaluation and grades machinery for no gain.

## 4. Data model

### 4.1 `Defence` (`lib/data/models/defence.dart`)

- New `final String? redefenceOf;`, read from `map['redefenceOf']`.
- `bool get isRedefence => redefenceOf != null;`
- A new `String get label`: "Pre-oral defence", "Final defence",
  "Pre-oral re-defence", "Final re-defence". Screens that print
  `type.label` for a whole defence use it instead.
- `static String redefenceIdFor(String failedId) => '${failedId}_redefence';`

### 4.2 Repository (`defence_repository.dart`)

New method `scheduleRedefence({required Defence failed, required DateTime
scheduledAt, required String venue, required String createdBy})`:
- Refuses on the client (as `ArgumentError`, matching `schedule`) unless
  `failed.panelVerdict == PassFail.fail` and `!failed.isRedefence`.
- Writes `defenses/{Defence.redefenceIdFor(failed.id)}` with `set()`. The
  fields are those of `schedule()`, plus `redefenceOf: failed.id`. The type,
  thesis, panel, adviser and leader are copied from `failed`.
- Panel, adviser and leader are copied from the failed defence, not
  re-read from the thesis. The rule still requires them to equal the
  thesis's current values (§5), so a panel changed in between is refused
  rather than silently mixed.

Existing `schedule()` is unchanged.

### 4.3 Derived: failed defences awaiting a re-defence

`awaitingRedefence(List<Defence> all)`, a pure function: every defence with
`panelVerdict == fail` and `!isRedefence`, for which no defence in `all` has
`redefenceOf == its id`. It is exposed through a provider built on
`myDefencesProvider` (per-reader) for the Re-defence tab.

## 5. Security rules (`firestore.rules`, `match /defenses/{defenceId}`)

The create rule gains an optional `redefenceOf`:

```
allow create: if verified() && isCoordinator()
  && incoming().keys().hasOnly([... existing ..., 'redefenceOf'])
  && (existing checks unchanged)
  && (!('redefenceOf' in incoming()) || validRedefence(defenceId));
```

`validRedefence(defenceId)`, with `failed = get(defenses/incoming().redefenceOf)`:
- `failed` exists;
- `failed.thesisId == incoming().thesisId` and `failed.type == incoming().type`;
- `failed.panelVerdict == 'fail'`;
- `!('redefenceOf' in failed)`. This is the one-re-defence limit. Changing
  the limit changes only this line.
- `defenceId == incoming().redefenceOf + '_redefence'`. This, together with
  create-only semantics, makes a second re-defence of the same Fail
  impossible: a second write is an update, and no update arm allows it.

No other rule changes. Room, comment, evaluation, release and verdict rules
already apply to any defence document.

**Known gap (unchanged by this work):** the Coordinator can still schedule a
plain new pre-oral or final defence for a thesis whose earlier one failed.
Rules cannot query "has a failed defence of this type". The UI steers to
re-defence instead (§6.4).

### 5.1 Rules tests (`rules-test`, emulator)

- Allowed: Coordinator re-defence of a failed pre-oral, and of a failed
  final.
- Denied:
  - a re-defence of a passed defence;
  - one of a defence with no verdict;
  - one of a re-defence;
  - a second re-defence of the same Fail;
  - a type mismatch or a thesis mismatch;
  - a wrong document id;
  - a non-Coordinator;
  - a nonexistent `redefenceOf`.
- The existing non-re-defence create tests pass unchanged.

## 6. Screens

### 6.1 Defences page (`/defences`, `defences_screen.dart`)

- **Stage switch.** A `SegmentedButton` (key `defenceStageSwitch`) above the
  content, with segments **Title defence | Pre-oral | Final defence |
  Re-defence**.
  - Each label carries a count when it is above zero, e.g. "Pre-oral (2)".
  - On compact widths the labels shorten to **Title | Pre-oral | Final |
    Re-defence** and drop their icons. If the switch still does not fit, it
    scrolls sideways; the page never overflows.
- **The stage is in the URL.** `/defences?stage=title|preOral|final|redefence`
  is used by dashboards and links. A missing or unknown value falls back to
  **Title defence**, the first stage. Changing the stage updates the query
  (`go`, not `push`), so browser back does not step through tabs.
- **List / Calendar** stays in the page actions for **Pre-oral**, **Final
  defence** and **Re-defence**, and is hidden on **Title defence** (no
  dates). `DefencesList` and `DefenceCalendar` each gain an optional
  `bool Function(Defence) where` filter:
  - Pre-oral: `type == preOral && !isRedefence`.
  - Final: `type == final_ && !isRedefence`.
  - Re-defence: `isRedefence`.
- Page subtitle: "Title defences, pre-oral and final defences, and
  re-defences."

### 6.2 Title defence stage

A new widget, `TitleDefenceStage`, chosen per role:
- **Coordinator / Dean.** The existing `DefenceQueue` (every thesis at
  `titlePendingDefence`), unchanged.
- **Faculty.** Theses at `titlePendingDefence` that the reader **advises**
  (`myAdviseesProvider`) **or** sits on (`myThesisIdsProvider` →
  `thesisByIdProvider`), de-duplicated. Each row has an "Open title defence"
  button to `/defence/{id}`. Empty state: "None of your theses are at title
  defence right now."
- **Student.** Their own thesis (`myThesisProvider`), as a read-only card:
  - `titlePendingDefence`: "Your candidate titles are with the panel."
  - `titleRejected`: "The panel returned your titles. Submit a new set." with
    a link to `/thesis/titles?id=…`.
  - Any status past `titleApproved`: "Title approved: <title>."
  - Before titles are submitted: "Your group has not submitted candidate
    titles yet."

  Students still never open `/defence/:thesisId` (its role guard is
  unchanged).

### 6.3 Re-defence stage

Top to bottom:
1. **Awaiting a re-defence**, from `awaitingRedefence` over the reader's own
   defences. Each row shows the group, the failed defence's label and date,
   and the verdict "Fail".
   - **Coordinator:** a **Schedule re-defence** button (key
     `scheduleRedefence-{id}`) to `/defence/schedule?redefenceOf={id}`.
   - **Everyone else:** "Waiting for the Coordinator to schedule the
     re-defence."
2. **Re-defences**, the filtered `DefencesList` / `DefenceCalendar`.

Empty (nothing awaiting, nothing scheduled): "No re-defences. A group
re-defends a stage when the panel's verdict on it is Fail."

### 6.4 Scheduling a re-defence (`schedule_defence_screen.dart`)

- `/defence/schedule?redefenceOf={id}` loads the failed defence and shows a
  locked heading: "Re-defence of the <pre-oral/final> defence held
  <date>". Type and thesis are fixed. Only date, time and venue are asked.
  Save calls `scheduleRedefence`.
- If the failed defence is not a Fail, is itself a re-defence, or already has
  a re-defence, the screen says so ("This defence cannot be re-defended")
  instead of the form.
- When scheduling a **plain** defence of a type the thesis already failed
  (and no re-defence exists), the screen shows a notice with a link:
  "This group failed its <type> on <date>. Schedule a re-defence instead."
  This is advisory; it does not block (§5 gap).
- Route guard: `/defence/schedule` stays Coordinator-only, as today.

### 6.5 Failed defence pages

`defence_room_screen.dart` and `defence_grades_screen.dart`, where they
print the verdict "Fail" and no re-defence exists yet, add:
- For the Coordinator: a **Schedule re-defence** button (same route as
  §6.3).
- For others: "A re-defence of this stage is to be scheduled."

On a re-defence's own pages, the heading uses `Defence.label` ("Pre-oral
re-defence") and links "Re-defence of: <original label, date>" to the
original room.

### 6.6 Advisees page

On `/advisees`, a thesis at `titlePendingDefence` gets an **Open title
defence** button to `/defence/{id}`.

### 6.7 Navigation

- The **Title defences** sidebar entry is removed for Dean and Coordinator.
- `/title-defences` redirects to `/defences?stage=title`. The route stays
  registered so old links and bookmarks keep working.
- `dean_overview.dart`'s link changes to `/defences?stage=title`.
- `TitleDefencesScreen` is deleted. Its content (`DefenceQueue`) lives on in
  §6.2.

## 7. Testing

- **Model:** `Defence.fromMap` reads `redefenceOf`; `label` covers all four
  cases; `redefenceIdFor`.
- **`awaitingRedefence`:** a fail with no re-defence is listed; one with a
  re-defence is not; a failed re-defence is not; pass and no-verdict are not.
- **Repository:** `scheduleRedefence` writes the derived id and copied
  fields, and refuses a non-fail or a re-defence (fake_cloud_firestore).
- **Rules:** §5.1.
- **Defences page (widget):**
  - the switch shows the four stages;
  - `?stage=` selects one, and a bad value falls back to Title;
  - List / Calendar is hidden on Title;
  - each stage lists only its defences;
  - the counts;
  - compact width renders without overflow.
- **Title stage per role:**
  - faculty in **adviser** mode sees an advisee's title defence and can open
    it;
  - a panelist sees theirs;
  - a student sees the read-only card;
  - Coordinator and Dean see the full queue.
- **Re-defence stage:** the awaiting row shows the Schedule button for the
  Coordinator only; scheduled re-defences are listed.
- **Schedule screen:** re-defence mode locks type and thesis and calls
  `scheduleRedefence`; the refusal states; the advisory notice on a plain
  schedule.
- **Routing:** `/title-defences` redirects to `/defences?stage=title`; the
  sidebar no longer lists Title defences; the existing tests that pinned
  `/title-defences` are updated to the redirect.
- **Regression:** a thesis whose final **re-defence** passed passes the
  manuscript and archive gates; the progress rail reaches Final.

## 8. Out of scope

- Re-defence of a rejected title set. It keeps the existing resubmit flow.
- Blocking a plain schedule after a Fail in rules (§5 gap).
- Notifications beyond what scheduling a defence already sends.
- Any change to scoring, verdict recording or evaluation.

## 9. Deploy

After implementation, the user deploys `firestore.rules`. There is no
schema migration: existing defence documents have no `redefenceOf` and read
as ordinary defences.

## 10. Open questions for the faculty

1. **How many re-defences per stage?** Built as one. Allowing more changes
   only the `!('redefenceOf' in failed)` line (§5) and the matching client
   check in `scheduleRedefence`.
2. **Same panel?** Assumed yes. The create rule already pins the panel to
   the thesis's current panel.
