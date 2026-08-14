# M1 — Title Submission and Nomination — Design

**Date:** 2026-08-14
**Module:** M1 of eThesisHub (see `2026-08-12-ethesishub-design.md` §9.3)
**Depends on:** the walking skeleton, merged to `master` at `112e5d9`

---

## 1. What this module delivers

A thesis group is created, gets a title approved by the Dean, and ends with an
adviser and panel formally fixed — the digital equivalent of Form 1 plus the
title decision of Capstone 1.

Ends at thesis status `in_progress`, which is where M2 (documents and revisions)
begins.

---

## 2. Corrections to the parent spec

Design review with the project owner established three facts the parent spec got
wrong. This document supersedes it on all three.

| Parent spec says | Reality |
|---|---|
| One tentative title per thesis | Students submit **three or more candidate titles**; the Dean approves one |
| Title approval follows nomination (§4.1), or is skipped entirely (§5.1 — the two contradict each other) | **Title approval comes first.** Nomination begins only after a title is approved |
| Thesis members are user accounts (`memberUids[]`) | **Only the group leader has an account.** Members are recorded as names |

Additionally, title approval goes **straight to the Dean** with no Research
Coordinator step, unlike every other approval in the system. This is deliberate:
the title decision happens in a face-to-face meeting during Capstone 1, and the
app records it rather than orchestrating it.

---

## 3. Roles in this module

| Role | Does |
|---|---|
| Student (leader) | Creates the thesis, records member names, submits candidate titles, nominates adviser and panel, re-nominates declined slots |
| Dean | Approves one candidate title or rejects the set with a remark; gives final approval to the nomination |
| Research Coordinator | Recommends the nomination to the Dean |
| Faculty | Accepts or declines their own nomination (Conforme) |

Nominee eligibility is unchanged from the parent spec: any account whose role is
`faculty`, `coordinator` or `dean` may be nominated, because Guidelines §4a
requires the panel to include the Research Coordinator or Chair.

---

## 4. Data model

```
theses/{thesisId}
  leaderUid          string    the only account attached to this thesis
  memberNames[]      string[]  groupmates, recorded as names only
  program            string
  academicYear       string
  status             string    see §5
  approvedTitle      string?   null until the Dean approves one
  adviserUid         string?   null until nomination is approved
  panelistUids[]     string[]  empty until nomination is approved
  coordinatorRecommendedAt timestamp?   nomination endorsed to the Dean
  deanApprovedAt           timestamp?   nomination finally approved
  createdAt, updatedAt

  candidateTitles/{titleId}
    text             string
    submittedAt      timestamp
    status           string    pending | approved | rejected
    deanRemark       string?
    decidedBy        string?   dean uid
    decidedAt        timestamp?

  nominations/{nomineeUid}
    position           string     adviser | panelist
    nomineeName        string     denormalised from facultyDirectory
    conformeStatus     string     pending | accepted | declined
    respondedAt        timestamp?
    declineReason      string?

facultyDirectory/{uid}
  fullName, college, specialization, role       ← deliberately no email
```

### 4.1 Why candidate titles are a subcollection

Each candidate carries its own decision, remark and timestamp, and the Dean
writes to exactly one of them. As an array field on the thesis, approving one
title means rewriting the whole array — so the rules cannot constrain *what*
changed, and two simultaneous writers silently overwrite each other. As a
subcollection the rule is enforceable: the Dean may set decision fields on one
title document, and nothing else.

The same reasoning makes `nominations` keyed by nominee uid: each faculty member
writes only their own document, so a rule can bind the writer to the subject.

### 4.1a Where the coordinator and dean decisions live

The parent spec put `coordinatorRecommendedAt` and `deanApprovedAt` on each
nomination document. That is wrong: the coordinator recommends — and the Dean
approves — **the nomination as a whole**, not each nominee individually. Storing
them per-nominee would mean writing four or more documents for one decision, with
no way to make that atomic and no way for a rule to tell a complete decision from
a partial one.

Both fields therefore live on the **thesis** document, alongside the status they
advance. Per-nominee documents carry only what that nominee personally did:
their Conforme.

### 4.2 Why facultyDirectory exists

Students must find faculty to nominate them, but the deployed rules allow listing
`users` only to coordinators and deans, and **Firestore has no field-level read
security** — any rule permitting a student to read a faculty `users` document
exposes that document's email too.

`facultyDirectory` holds only the fields the nomination picker needs. It is
readable by any verified user and writable only by its own subject.

**Synchronisation.** There are no Cloud Functions on the Spark plan, so the
directory is maintained client-side: a faculty member's own client writes their
entry during `promoteFromInvite`, which already runs at their sign-in. A
coordinator may also correct entries. The accepted cost is that a name changed in
`users` goes stale in the directory until that user next signs in.

Existing faculty promoted before this module ships need a one-off backfill.

---

## 5. Status flow

```
draft                          group created, no titles submitted
  → titles_pending_dean        three or more candidates submitted
  → title_approved             Dean approved one; approvedTitle set
  → nomination_pending_conforme
  → nomination_pending_coordinator
  → nomination_pending_dean
  → in_progress                adviser and panel fixed; Form 1 complete
```

**Rejection paths**
- Dean rejects the whole candidate set → back to `draft`, remark visible to the
  student, existing candidates marked `rejected` and retained for the record
- A nominee declines → that slot returns to the student for re-nomination;
  accepted Conformes on other slots stand, and status stays
  `nomination_pending_conforme`

---

## 6. Screens

**Student (leader)**
1. **Create thesis** — member names, program, academic year
2. **Candidate titles** — add three or more, submit as a set
3. **Nominate** — search `facultyDirectory`; select one adviser and three or more panel members
4. **Thesis status** — current stage, the Dean's remark if rejected, per-nominee Conforme state, re-nominate action on declined slots

**Dean**
1. **Title decisions** — groups awaiting a decision; open one, see all candidates, approve one or reject the set with a remark
2. **Nomination approvals** — final approval, which writes `adviserUid` and `panelistUids[]`

**Coordinator**
1. **Nomination recommendations** — endorse to the Dean

**Faculty**
1. **Nomination inbox** — pending nominations; accept, or decline with a reason

---

## 7. Security rules

### 7.1 New collection rules

| Collection | Read | Write |
|---|---|---|
| `theses` | Leader, assigned adviser, assigned panelists, coordinator, dean | Leader creates with `leaderUid == self` and `status: 'draft'`; status transitions gated per role. Only a coordinator may set `coordinatorRecommendedAt`; only a dean may set `approvedTitle`, `deanApprovedAt`, `adviserUid` and `panelistUids[]` |
| `candidateTitles` | Same as parent thesis | Leader adds and removes while `draft`; **only the Dean** may write `status`, `deanRemark`, `decidedBy`, `decidedAt` |
| `nominations` | Same as parent thesis, plus the nominee | Leader creates; **only the nominee** may set their own `conformeStatus`, `respondedAt` and `declineReason` — nothing else |
| `facultyDirectory` | Any verified user | Own entry only, and only while your `users` role is not `student` |

Students cannot read one another's theses.

### 7.2 Collection-group query

The faculty nomination inbox must find nominations across all theses, which
requires a collection-group query and therefore its own rule:

```
match /{path=**}/nominations/{nomineeUid} {
  allow read: if verified() && request.auth.uid == nomineeUid;
}
```

The nominee uid is the document id, which makes this rule expressible.

### 7.3 Audit

`AuditService` is already wired. M1 adds entries at the two decisions that
matter: `title.approved` and `nomination.approved`. Both must write exactly the
six whitelisted keys, and an audit failure must never break the action it
records.

---

## 8. Out of scope

- **Guidelines §1e coordinator-assign fallback** — deferred by decision. M1 ships
  the normal path only.
- **Form 4b title changes** after approval — a later module.
- **Form 1 PDF generation** — M6.
- **§1c five-advisees-per-faculty cap** — still on the backlog from the parent spec.
- Groupmate accounts, group-member self-service, and transfer of leadership.

---

## 9. Accepted limitations

1. **Only the leader can act.** Groupmates cannot view progress, upload, or be
   notified. Everything routes through one account.
2. **A lost leader account strands the thesis.** There is no co-owner and no
   transfer mechanism.
3. **`facultyDirectory` can go stale** relative to `users` until the subject next
   signs in. No server-side reconciliation is possible on Spark.
4. **Member names are unverified free text.** Nothing checks that a recorded
   groupmate is a real enrolled student.

All four belong in Scope and Limitations.

---

## 10. Decisions taken during spec review

**Academic year format** is `YYYY-YYYY`, e.g. `2026-2027`, validated client-side
and by a rules regex. Fixing the format now means M5's archive can group and sort
by year without parsing free text later.

**Minimum three panel members, no maximum.** Enforced client-side and in the
rules (`panelistUids.size() >= 3` at approval). Guidelines §4a governs; Form 1's
two printed blanks are an error in the manual.

**Candidate titles are retained after rejection**, marked `rejected` rather than
deleted, so the Dean's remarks remain visible and the history of what was
proposed survives.
