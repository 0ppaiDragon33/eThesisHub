# Change of adviser and change of title — design

**Status:** approved in conversation 2026-09-25; awaiting written-spec review.
**Branch:** docs/ui-overhaul-spec.

## 1. What this is for

A group whose thesis already has an approved title sometimes needs to change
its adviser, or change the approved title itself. The Guidelines have two
paper forms for this: **Form 4a** (Change of Undergraduate Thesis Adviser)
and **Form 4b** (Change of Undergraduate Thesis Title). Today the app only
prints those forms blank; there is no request, no routing, and no effect on
the thesis.

This builds the paperless workflow the app is meant to be: a student submits
the request in the app, it runs through the same sign-off chain the printed
form carries, and on the Dean's approval the app makes the change.

Success: a group leader can request a change of adviser or of title from the
thesis screen; the named advisers, then the Coordinator, then the Dean act
in the app; the Dean's approval updates the thesis (new adviser, or new
title); and a decline at any step returns the request to the student to fix
and resubmit.

Not in this work: the change-of-defence request (Form 5a and the re-defence
already exist; whether a "request a different defence" flow is needed is a
question still with the faculty). The defence work is untouched here.

## 2. Decisions taken in conversation

| Question | Decision |
|---|---|
| How much of the chain runs in-app? | The full chain. The app is paperless. |
| When can a change of adviser be requested? | Only during chapter writing — the thesis is at `titleApproved` and no defence has been scheduled yet. |
| When can a change of title be requested? | Any time before the final defence — the thesis is at `titleApproved` and no final defence has passed. |
| Who signs off on a change of adviser? | The new adviser **and** the former adviser both accept (Conforme), then Coordinator, then Dean. |
| What happens on a decline? | The request is returned to the student with the reason; they edit and resubmit. One open request of each type per thesis. |
| Where do the requests live? | A per-thesis `changeRequests` subcollection, modelled on nominations (approach A). |

## 3. Findings that shaped the design

- **Nominations are the template.** `theses/{id}/nominations/{uid}` holds one
  document per nominee with a `conformeStatus` the nominee updates in place;
  `respondToNomination` (`thesis_repository.dart:387`) advances the thesis
  status once every outstanding Conforme is in. The rule helpers
  (`isThesisLeader`, `isCoordinator`, `isDean`, `isOnPanel`, `thesisData`)
  live inside `match /theses/{thesisId}` and are reused across its
  subcollections. A change request fits the same shape.
- **The adviser is a single field.** `thesis.adviserUid` (`thesis.dart:47`).
  Advisee lists are a query on it (`watchAdvisedTheses`,
  `thesis_repository.dart:340`), so setting a new `adviserUid` moves the
  thesis between advisers with no other write. The panel
  (`panelistUids`) is separate and untouched.
- **The title shown everywhere is `workingTitle`** (`thesis.dart`,
  `student_overview.dart:178`, `title_defence_screen.dart:388`).
  `approvedTitleId` points at the candidate the panel approved. A change of
  title updates `workingTitle`; `approvedTitleId` is left as history.
- **The finer eligibility gate is a UI concern, not a rule.** Defence
  scheduling already gates coarsely in the rules (status, role) and finely
  in the UI (chapter readiness). Rules cannot join the `defenses` collection
  into a `theses/` subcollection rule without per-document reads that blow
  the evaluation budget. So the rules gate on `status == titleApproved` and
  the leader; the screen hides the button when the defence state disallows
  it.
- **A filled Form 4a/4b already has a template.** Phase 3 made both forms
  editable, so a filled PDF can be generated from the request data (as
  Form 1 is generated from nomination data), reusing those templates.

## 4. Data model

### 4.1 `ChangeRequest` (`lib/data/models/change_request.dart`, new)

One document at `theses/{thesisId}/changeRequests/{requestId}`.
`requestId` is `adviser` or `title` — the type is the id, so there is at most
one change-request document of each type per thesis, and it is reused rather
than duplicated. The leader may write a fresh first-pending request into it
whenever it is **absent** (the first request), **`returned`** (edit and
resubmit), or **`approved`** (a later, separate change of the same kind, once
the earlier one has taken effect). It may never be overwritten while a
request is still open (any pending stage) — that is the "one open request of
each type" guarantee. The document holds only the latest request; the effect
of an approved change is preserved on the thesis itself (the new adviser or
title).

Fields:
- `type`: `ChangeRequestType` — `adviser` or `title` (equals the id).
- `stage`: `ChangeRequestStage` (see §4.2).
- `reasons`: `String` — the student's justification.
- `leaderUid`: `String` — who submitted; pinned like a defence's `leaderUid`.
- `createdAt`, `updatedAt`.
- **Adviser request:** `newAdviserUid`, `newAdviserName`,
  `formerAdviserUid`, `formerAdviserName`.
- **Title request:** `newTitle`.
- `signoffs`: `Map<String, Signoff>` keyed by role. A `Signoff` is
  `{status: pending|accepted|declined, respondedAt: Timestamp?, reason:
  String?}`. The keys are:
  - adviser request: `newAdviser`, `formerAdviser`, `coordinator`, `dean`;
  - title request: `adviser`, `coordinator`, `dean`.

`ChangeRequestType` and `ChangeRequestStage` are enums with the
`value`/`fromString` shape used across the models (null-safe, a typo does
not silently pass).

### 4.2 Stages

**Form 4a (adviser):**
`pendingAdvisers` → `pendingCoordinator` → `pendingDean` → `approved`,
with `returned` reachable from any pending stage on a decline.
- `pendingAdvisers`: both `newAdviser` and `formerAdviser` accept, in
  parallel (like Conforme). The stage advances only when both are
  `accepted`.

**Form 4b (title):**
`pendingAdviser` → `pendingCoordinator` → `pendingDean` → `approved`,
with `returned` on a decline.
- `pendingAdviser`: the thesis's current adviser notes (accepts) the change.

`returned` carries the declining role's reason on that role's `Signoff`. The
leader edits the request (new adviser/title, reasons) and resubmits, which
resets every `Signoff` to `pending` and the stage to the first pending
stage. There is no `declined` terminal state: a request is either open,
returned (for the student to act on), or `approved`.

### 4.3 Repository (`change_request_repository.dart`, new)

- `Stream<List<ChangeRequest>> watchForThesis(String thesisId)` — the
  leader's and approvers' view of a thesis's requests.
- `Stream<List<({String thesisId, ChangeRequest request})>> watchForSignoff(
  String uid, {required Set<ChangeRequestRole> asRoles})` — the inbox
  queries for a faculty member (the new/former/current adviser) and for the
  coordinator/dean queues, via a `collectionGroup('changeRequests')` read.
- `Future<void> submit({...})` — write a fresh first-pending request:
  the first create, a resubmit of a `returned` one, or a later change once
  the previous one is `approved` (§4.1). Validates the type's fields, sets
  every `Signoff` to `pending`, and the stage to the first pending stage.
  Refuses when a request of this type is still open (any pending stage).
- `Future<void> respond({thesisId, type, role, accept, reason})` — a
  transaction, in the shape of `respondToNomination`: read the request and
  thesis, refuse if the stage no longer awaits this role, write this role's
  `Signoff`, and advance the stage when the step is complete. A decline sets
  the stage to `returned`.
- `Future<void> approveAsDean({thesisId, type})` — the Dean's final step.
  A batch that writes the dean `Signoff` and the stage `approved` **and**
  the thesis change (`adviserUid`, or `workingTitle`) together, so the two
  cannot diverge. The security rules validate the batch as a unit.

The transaction guard **returns** its failure and throws outside the
closure, per the project's memory rule (throwing inside `runTransaction`
crashes on Android).

## 5. Eligibility and effect

- **Change of adviser** — the button shows when: `status == titleApproved`,
  and the thesis has no non-cancelled defence of any kind (chapter writing is
  still on). Reads the thesis's defences, which the leader may read
  (`watchForLeader`).
- **Change of title** — the button shows when: `status == titleApproved`,
  the thesis is not archived, and no final defence has a `pass` verdict.
- The rules enforce only `status == titleApproved` and leader identity; the
  screen enforces the defence-state gate above.
- **On the Dean's approval:**
  - adviser: set `thesis.adviserUid = newAdviserUid`. The thesis moves
    between advisee lists automatically; the panel is untouched.
  - title: set `thesis.workingTitle = newTitle`. `approvedTitleId` is left as
    history.

## 6. Screens

### 6.1 Student — thesis screen (`thesis_status_screen.dart`)

Below the existing status and Form 1 download, when eligible (§5), two
buttons: **Request change of adviser**, **Request change of title**. Each
opens a small form screen:
- adviser: a picker over the faculty directory
  (`allDirectoryProvider`, `nominableAsAdviser` honoured, the current adviser
  excluded), plus a reasons field;
- title: a new-title field and a reasons field.

Below the buttons, a card per open or returned request shows its stage, each
sign-off's state (pending/accepted/declined), and, when returned, the reason
and an **Edit and resubmit** action. When a request is `approved`, the card
offers the filled Form 4a/4b PDF (§6.5).

### 6.2 Faculty — the adviser sign-off inbox

The nominated adviser, former adviser and current adviser act where they
already handle nominations. A **Change requests** section lists the requests
awaiting this person's sign-off (from `watchForSignoff`), each showing the
group, the from→to change and the reasons, with **Accept** and **Decline
(with reason)**.

### 6.3 Coordinator and Dean — the queues

A **Change requests** queue on each desk (a `collectionGroup` read, like the
defence and title-defence queues), showing requests at
`pendingCoordinator` / `pendingDean`. The Coordinator **Recommends** or
**Returns**; the Dean **Approves** (which applies the change) or **Returns**.
Each row shows the change and the reasons, and both roles can read the
sign-offs so far.

### 6.4 Navigation

These reuse existing destinations rather than adding sidebar entries: the
student's requests live on the thesis screen; the faculty sign-offs sit with
nominations; the Coordinator and Dean queues sit on their overview desks
alongside the title-defence and recommendation queues. New routes only for
the two student request forms (e.g. `/thesis/change-adviser`,
`/thesis/change-title`).

### 6.5 The record PDF

A filled Form 4a/4b, generated from the request data through the Phase 3
templates (the way Form 1 is generated from nomination data). Offered for
download once the request is `approved`. Generation logic only; no template
change.

## 7. Security rules (`theses/{thesisId}/changeRequests/{requestId}`)

Inside `match /theses/{thesisId}`, reusing its helpers.

- **read (get, list):** the leader, the two named advisers (adviser
  request) or the current adviser (title request), anyone on the panel, the
  coordinator and the dean.
- **create / reset:** only the leader (`isThesisLeader`), only while
  `thesisData(thesisId).status == 'titleApproved'`, `requestId in ['adviser',
  'title']` and matching `type`, only the allowed fields for that type, every
  `Signoff` `pending`, and `stage` the first pending stage. This one rule
  covers the first create (no document yet) and every reset of an existing
  one — a create where the document is absent, and an update where the
  existing `stage` is `returned` or `approved`. An update where the existing
  `stage` is any pending stage is refused, which is the "one open request per
  type" guarantee.
- **update — a sign-off:** an approver changes only their own `Signoff` and
  only at the stage that awaits them:
  - the new adviser or the former adviser at `pendingAdvisers`
    (`request.auth.uid == newAdviserUid` / `== formerAdviserUid`);
  - the current adviser at `pendingAdviser` (title);
  - the coordinator at `pendingCoordinator`; the dean at `pendingDean`.
  The stage may advance by one only when the step is complete (both advisers
  accepted; or the single signer accepted), and only to the next stage in
  order. A decline sets `stage == 'returned'` and touches nothing else.
  (The leader's resubmit of a `returned` request, and a later change after an
  `approved` one, are the same "create / reset" rule above — a leader writing
  a fresh first-pending request.)
- **the Dean's approval batch:** the dean `Signoff` accepted + `stage`
  `approved` on the request, and the matching thesis change
  (`adviserUid` or `workingTitle`) — the thesis's own update rule admits this
  write only when the request is at `pendingDean` and this is the dean.
  Validated as a batch, the way the title-decision batch is.
- **delete:** never.

Emulator tests for every allowed and denied case, in the style of the
nomination and defence rules tests: each role signing only at its own stage,
the wrong role refused, a sign-off out of stage refused, the create gated on
status and leader, one-open-request, the resubmit only from returned, and
the Dean's batch (allowed together, each half denied alone).

## 8. Testing

- **Model:** `ChangeRequest.fromMap`/`toMap` round-trip for both types; the
  enums' `fromString` null-safety; the stage helpers.
- **Repository (fake_cloud_firestore):** submit (create and resubmit);
  respond advancing the stage only when the step completes; a decline
  returning it; `approveAsDean` writing the thesis change; refusals for the
  wrong stage.
- **Providers:** the inbox and queue queries return the right requests per
  role.
- **Screens (widget):** the student sees the buttons only when eligible, can
  submit and can resubmit a returned request; the faculty inbox shows and
  acts on a sign-off; the Coordinator and Dean queues recommend/approve/
  return; on approval the thesis shows the new adviser/title.
- **Rules:** §7.

## 9. Deploy

After implementation, the user deploys `firestore.rules` (new subcollection
rules, and the thesis update arm for the Dean's batch) and a Firestore index
for the `collectionGroup('changeRequests')` queries if the console asks for
one. No data migration: theses without change requests simply have an empty
subcollection.

## 10. Out of scope

- The change-of-defence request (with the faculty).
- Any change once a thesis is archived.
- Changing the panel — this is adviser and title only.
- Notifications beyond what the existing inbox/queue widgets already surface.

## 11. Open questions for the faculty

1. If the former adviser will not respond, is there a Coordinator override,
   or does the request simply stall until they do? (Built as: it waits.
   A Coordinator reopen, like the stalled-nomination reopen, could be added
   later without changing the model.)
2. Does a change of adviser ever need to change the panel too (e.g. the new
   adviser is currently a panelist)? Assumed no.
