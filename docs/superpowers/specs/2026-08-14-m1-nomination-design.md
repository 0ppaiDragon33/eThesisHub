# M1a — Group Creation and Nomination — Design

**Date:** 2026-08-14
**Module:** M1a of eThesisHub (see `2026-08-12-ethesishub-design.md` §9.3)
**Depends on:** the walking skeleton, merged to `master` at `112e5d9`
**Followed by:** M1b — Title Defence (outlined in §11)

---

## 1. What this module delivers

A thesis group is created and ends with an adviser and panel formally fixed —
the digital equivalent of Form 1.

Ends at thesis status `nomination_approved`, which is where M1b (title defence)
begins.

---

## 2. Corrections to the parent spec

Design review with the project owner established four facts the parent spec got
wrong. This document supersedes it on all four.

| Parent spec says | Reality |
|---|---|
| Title approval and nomination are two chains, ordered title-first (§4.1) or title-never (§5.1 — the two contradict each other) | **Nomination comes first.** The title defence is a separate event that happens *after* the adviser and panel are fixed |
| One tentative title per thesis | Students submit **three or more candidate titles**, each with its own justification document and a presentation — all in M1b |
| Thesis members are user accounts (`memberUids[]`) | **Only the group leader has an account.** Members are recorded as names |
| `coordinatorRecommendedAt` / `deanApprovedAt` live on each nomination | They are **thesis-level** decisions (§4.1a) |

---

## 3. Roles in this module

| Role | Does |
|---|---|
| Student (leader) | Creates the thesis, records member names, nominates adviser and panel, re-nominates declined slots |
| Faculty | Accepts or declines their own nomination (Conforme) |
| Research Coordinator | Recommends the nomination to the Dean |
| Dean | Final approval, which fixes the adviser and panel |

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
  academicYear       string    YYYY-YYYY
  status             string    see §5
  adviserUid         string?   null until nomination is approved
  panelistUids[]     string[]  empty until nomination is approved
  coordinatorRecommendedAt timestamp?
  deanApprovedAt           timestamp?
  createdAt, updatedAt

  nominations/{nomineeUid}
    position         string     adviser | panelist
    nomineeName      string     denormalised from facultyDirectory
    conformeStatus   string     pending | accepted | declined
    respondedAt      timestamp?
    declineReason    string?

facultyDirectory/{uid}
  fullName, college, specialization, role       ← deliberately no email
```

### 4.0a `panelistUids[]` holds only the nominated members

The Dean and Research Coordinator sit on the thesis panel **ex officio** — by
virtue of their role, not by nomination. They are never nominated, never give a
Conforme, and are never written into `panelistUids[]`.

So the effective panel at any defence is:

```
Dean (ex officio) + Research Coordinator (ex officio)
  + adviserUid + panelistUids[]        ← the nominated three or more
```

This resolves a contradiction in the manual itself: Guidelines §4a lists the
Dean and Coordinator as panel members at (a) and (b), then says at (d) that the
three nominated members "should include the Research Coordinator or Chair". They
are counted once, ex officio.

Later modules must derive the panel this way rather than reading
`panelistUids[]` alone, or the Dean and Coordinator will be missing from quorum
checks (§4f requires at least four present) and from defence attendance.

### 4.1 Why nominations are keyed by nominee uid

Each faculty member writes only their own document, so a rule can bind the writer
to the subject: `request.auth.uid == nomineeUid`. It also makes the faculty inbox
expressible as a collection-group query (§7.2).

### 4.1a Where the coordinator and dean decisions live

The parent spec put `coordinatorRecommendedAt` and `deanApprovedAt` on each
nomination document. That is wrong: the coordinator recommends — and the Dean
approves — **the nomination as a whole**, not each nominee individually. Storing
them per-nominee would mean writing four or more documents for one decision, with
no way to make that atomic and no way for a rule to tell a complete decision from
a partial one.

Both fields therefore live on the **thesis** document, alongside the status they
advance. Per-nominee documents carry only what that nominee personally did.

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

Faculty promoted before this module ships need a one-off backfill.

---

## 5. Status flow

```
draft                             group created
  → nomination_pending_conforme   adviser + 3 or more panelists nominated
  → nomination_pending_coordinator  all Conformes accepted
  → nomination_pending_dean       coordinator recommended
  → nomination_approved           Dean approved; adviserUid + panelistUids fixed
                                  (Form 1 complete — M1b begins here)
```

**Decline path.** A nominee declining returns that one slot to the student for
re-nomination. Accepted Conformes on other slots stand, and the status remains
`nomination_pending_conforme`.

---

## 6. Screens

**Student (leader)**
1. **Create thesis** — member names, program, academic year
2. **Nominate** — search `facultyDirectory`; select one adviser and three or more panel members
3. **Thesis status** — current stage, per-nominee Conforme state, re-nominate action on any declined slot

**Faculty**
1. **Nomination inbox** — pending nominations; accept, or decline with a reason

**Research Coordinator**
1. **Nomination recommendations** — endorse to the Dean

**Dean**
1. **Nomination approvals** — final approval, which writes `adviserUid` and `panelistUids[]`

---

## 7. Security rules

### 7.1 New collection rules

| Collection | Read | Write |
|---|---|---|
| `theses` | Leader, assigned adviser, assigned panelists, coordinator, dean | Leader creates with `leaderUid == self` and `status: 'draft'`; status transitions gated per role. Only a coordinator may set `coordinatorRecommendedAt`; only a dean may set `deanApprovedAt`, `adviserUid` and `panelistUids[]` |
| `nominations` | Same as parent thesis, plus the nominee | Leader creates while the thesis is `draft` or `nomination_pending_conforme`; **only the nominee** may set their own `conformeStatus`, `respondedAt` and `declineReason` — nothing else |
| `facultyDirectory` | Any verified user | Own entry only, and only while your `users` role is not `student` |

Students cannot read one another's theses.

At Dean approval the rules must enforce `panelistUids.size() >= 3` and that every
nomination's `conformeStatus` is `accepted`.

### 7.2 Collection-group query

The faculty nomination inbox must find nominations across all theses, which
requires a collection-group query and therefore its own rule:

```
match /{path=**}/nominations/{nomineeUid} {
  allow read: if verified() && request.auth.uid == nomineeUid;
}
```

Worth naming because it is easy to write the query, watch it fail with
`permission-denied`, and wrongly conclude the data model is at fault.

### 7.3 Audit

`AuditService` is already wired. M1a adds `nomination.approved` at the Dean's
approval. It must write exactly the six whitelisted keys, and an audit failure
must never break the approval it records.

---

## 8. Out of scope

- **Everything about titles** — candidate titles, justification documents,
  presentations and the title defence are M1b (§11)
- **Guidelines §1e coordinator-assign fallback** — deferred by decision
- **Form 1 PDF generation** — M6
- **§1c five-advisees-per-faculty cap** — still on the parent backlog
- Groupmate accounts, group-member self-service, transfer of leadership

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

## 10. Decisions taken during design review

- **Academic year format** is `YYYY-YYYY`, validated client-side and by a rules
  regex, so M5's archive can group and sort without parsing free text.
- **Minimum three panel members, no maximum.** Guidelines §4a governs; Form 1's
  two printed blanks are an error in the manual.
- **Nomination precedes the title defence**, correcting the parent spec.

---

## 11. M1b — Title Defence (outline, not yet specified)

Captured here so the design intent is not lost. M1b gets its own spec.

**Trigger:** thesis reaches `nomination_approved`.

**Flow**
```
Student submits 3 or more candidate titles
  each with a justification document (uploaded)
  plus a presentation (uploaded)
        ↓
Title defence: the panel reviews
        ↓
Each panelist records their own approve/reject decision per candidate
        ↓
One title approved → approvedTitle set → thesis → in_progress
```

**Decided already**

- Justification is an **uploaded document**, not a structured form — students
  already produce it in Word, and modelling a dozen sections as fields would be
  painful on a phone and duplicate the paper trail.
- A **presentation file** is uploaded alongside the candidate titles.
- **The Dean records the approved title.** The Coordinator, nominated panel
  members and the Adviser leave comments and suggestions on candidates but cast
  no formal vote.

  *This supersedes an earlier decision in the same review that each panelist
  would record their own approve/reject.* The simpler model was chosen
  deliberately: the defence happens in person, the panel reaches its decision in
  the room, and the app records the outcome rather than discovering it. The cost
  is a weaker per-person audit record for the title decision than the Conforme
  chain gives for nomination.

- **Comments are optional**, so a member who simply agrees is not forced to pad
  the record.
- The **Adviser does not vote** on the title, though they attend and may comment.
- Chapters 1–3 are **not** part of this defence; that is the pre-oral (§12).

**Open for M1b's own review**

- Does rejecting the whole set need a Dean's remark, as the parent design assumed?
- Do rejected candidates block resubmitting the same title text?
- File type and size limits for justification and presentation uploads.
- Are comments visible to the student immediately, or only after the decision?

**Reuses** `StorageService` (Supabase, public bucket, unguessable UUID paths)
already built in the skeleton.

---

## 12. Beyond M1b — the pre-oral defence (forward context only)

Recorded so later modules inherit it. Not specified here.

After the title defence comes the **pre-oral defence**, which is where Chapters
1–3 enter the process:

- The student submits Chapters 1–3, viewable by the assigned panel — nominated
  panel members, adviser, coordinator and dean
- The student presents a PPTX at the defence
- Guidelines §4c requires the proposal to reach each panel member **one week**
  before the scheduled pre-oral defence

This spans M2 (documents and revisions) and M3 (defence scheduling and live
comments). The panel used for visibility and quorum must be derived per §4.0a,
including the ex officio Dean and Coordinator.
