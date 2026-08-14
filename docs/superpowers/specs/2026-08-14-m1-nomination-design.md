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

**Nominee eligibility — corrected.** The parent spec said any account with role
`faculty`, `coordinator` or `dean` may be nominated, reasoning that Guidelines
§4a requires the panel to include the Research Coordinator. That reasoning no
longer holds now that the Dean and Coordinator sit ex officio (§4.0a) —
nominating them as well would count them twice, and would let a Coordinator
decline a seat they hold by role.

Students therefore **choose** only accounts whose role is `faculty`. The
`facultyDirectory` picker excludes the Dean and Coordinators.

They are still **recorded** as panel members, so Form 1 shows the complete panel
— the system adds those entries itself, marked ex officio (§4.0b). The
distinction is between choosing and recording: the student chooses three or more
faculty; the system records everyone who sits on the resulting panel.

*Consequence to accept:* a faculty member who is later promoted to Coordinator
while already serving as a nominated panel member on an existing thesis would
then appear twice on that panel. Rare enough to handle by hand; a later module
can reconcile it if it happens.

---

## 4. Data model

```
theses/{thesisId}
  leaderUid          string    the only account attached to this thesis
  memberNames[]      string[]  groupmates, recorded as names only
  workingTitle       string    the group's initial idea; names the thesis in
                               lists. NOT a candidate title — M1b's three or
                               more candidates are separate and may differ
  college            string    for the Form 1 letterhead
  program            string
  semester           string    First | Second — Form 1 requires it
  academicYear       string    YYYY-YYYY
  status             string    see §5
  adviserUid         string?   null until nomination is approved
  panelistUids[]     string[]  empty until nomination is approved
  coordinatorRecommendedAt timestamp?
  coordinatorRecommendedBy string?    uid of the coordinator who recommended
  deanApprovedAt           timestamp?
  deanApprovedBy           string?    uid of the dean who approved
  createdAt, updatedAt

  nominations/{nomineeUid}
    position         string     adviser | panelist | coordinator | dean
    nomineeName      string     denormalised from facultyDirectory
    exOfficio        bool       true for coordinator and dean entries
    conformeStatus   string     pending | accepted | declined | exOfficio
    respondedAt      timestamp?
    declineReason    string?

facultyDirectory/{uid}
  fullName, college, specialization, role       ← deliberately no email
```

### 4.0a `panelistUids[]` holds only the nominated members

The Dean and the Research Coordinators sit on the thesis panel **ex officio** —
by virtue of their role, not by nomination. They are never nominated, never give
a Conforme, and are never written into `panelistUids[]`.

**There may be more than one coordinator** (for example a Research Coordinator
and a Research Chair, or one per programme), and **all of them sit on every
panel**. This matches how `isCoordinator()` already works in the deployed rules,
so no rule needs to distinguish between them.

So the effective panel at any defence is:

```
Dean (ex officio) + every Coordinator (ex officio)
  + adviserUid + panelistUids[]        ← the nominated three or more
```

### 4.0b Ex officio members are recorded, but never asked

For completeness of the paper record, the system writes `nominations` entries for
the Dean and every Coordinator when the student submits, marked
`exOfficio: true` and `conformeStatus: 'exOfficio'`. They therefore appear on
Form 1 as full panel members.

They are **not** selectable in the picker, are **never** sent a Conforme request,
and cannot decline. A seat held by role is not an invitation.

**This changes the record only — never their powers.** Every capability the Dean
and Coordinators hold is derived from their role, not from these entries:

- Firestore rules gate on `isCoordinator()` and `isDean()`, which already grant
  read access to every thesis and write access to the recommend and approve steps
- M1b's title decision is the Dean's because they are the Dean
- The pre-oral and final defence panel is derived per §4.0a, so they attend,
  comment and count toward §4f quorum regardless

Deleting every `exOfficio` entry would change nothing except what Form 1 prints.

Two consequences to carry forward:

- **Panel size varies with staffing.** Appointing another coordinator enlarges
  every panel in the system, including theses already in progress. Nothing
  breaks, but M3's quorum check must count the panel as derived here rather than
  assuming a fixed size.
- **Any one coordinator's recommendation advances the nomination.** Form 1 has a
  single *"Recommending Approval: College Research Coordinator"* signature line,
  so this is not a vote requiring all of them. `coordinatorRecommendedBy` records
  which one acted, because with several coordinators an unattributed timestamp
  would be useless in an audit.

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
  → nomination_pending_coordinator  every non-ex-officio Conforme accepted
  → nomination_pending_dean       coordinator recommended
  → nomination_approved           Dean approved; adviserUid + panelistUids fixed
                                  (Form 1 complete — M1b begins here)
```

**Decline path.** A nominee declining returns that one slot to the student for
re-nomination. Accepted Conformes on other slots stand, and the status remains
`nomination_pending_conforme`.

---

## 6. Screens

**Field types.** People and fixed sets are always chosen, never typed — a typo in
a nominee's name or an academic year would silently corrupt the record and the
generated form. Only genuinely free text is an input.

| Field | Control |
|---|---|
| Working title | text input |
| Group member names | text input, one per row, add more |
| College, program, semester, academic year | dropdown |
| Adviser, panel members | searchable dropdown from `facultyDirectory` |
| Coordinator, Dean | **not selectable** — ex officio (§4.0a), shown read-only |

**Student (leader)**
1. **Create thesis** — working title, member names, college, program, semester, academic year
2. **Nominate** — search `facultyDirectory`; select one adviser and three or more panel members
3. **Thesis status** — current stage, per-nominee Conforme state, re-nominate action on any declined slot, and **Download Form 1** once approved

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
| `theses` | Leader, assigned adviser, assigned panelists, any coordinator, dean | Leader creates with `leaderUid == self` and `status: 'draft'`; status transitions gated per role. Only a coordinator may set `coordinatorRecommendedAt`, and must set `coordinatorRecommendedBy` to their own uid; only a dean may set `deanApprovedAt`, `deanApprovedBy` (own uid), `adviserUid` and `panelistUids[]` |
| `nominations` | Same as parent thesis, plus the nominee | Leader creates while the thesis is `draft` or `nomination_pending_conforme`, including the ex officio entries (`exOfficio: true`, `conformeStatus: 'exOfficio'`, which the rules must pin to exactly those values so a student cannot forge an acceptance); **only the nominee** may set their own `conformeStatus`, `respondedAt` and `declineReason`, and only on an entry where `exOfficio == false` |
| `facultyDirectory` | Any verified user | Own entry only, and only while your `users` role is not `student` |

Students cannot read one another's theses.

At Dean approval the rules must enforce `panelistUids.size() >= 3` and that every
nomination **where `exOfficio == false`** has `conformeStatus == 'accepted'`.
Ex officio entries carry `conformeStatus: 'exOfficio'` and are excluded from this
check — requiring them to be `accepted` would block every approval, since they
are never asked.

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

### 7.3 Form 1 generation

Once the nomination reaches `nomination_approved`, the leader can download
**Form 1 — Nomination of Thesis Adviser and Panel Members** as a PDF, generated
with the `pdf` and `printing` packages.

**It prints what happened, not blank signature lines.** Because Conforme,
recommendation and approval are all recorded in the app, each signature block
renders the recorded action instead:

```
Conforme:
    Dr. Noel A. Armada      Accepted 14 Aug 2026, 10:22 — via eThesisHub
    Dr. L. Diamante         Accepted 14 Aug 2026, 11:05 — via eThesisHub
    ...
Recommending Approval:
    Dr. J. Bito-onon        Recommended 15 Aug 2026 — via eThesisHub
Approved:
    Dr. N. Siason Jr.       Approved 16 Aug 2026 — via eThesisHub
```

**Fidelity.** Match the printed form's wording, headings and control number
(`RD-30-06/24-04`) so the R&D office recognises it; render cleanly rather than
reproducing the printed layout exactly.

**Layout, as approved in design review:**

- **Letterhead** — ISUFST seal left, university and R&D block centred, ISO 9001 /
  UKAS accreditation marks right, over a blue rule. Form title and reference code
  beneath.
- **Body text** — the printed form's wording, with nominated names in bold. **No
  underlines**: the names are printed values, not blanks to fill.
- **Researchers** — stacked in a single right-aligned column directly under
  "Very truly yours,", the leader first and labelled *Researcher · Group Leader*,
  then each member from `memberNames[]` labelled *Researcher*. Roughly 20px of
  clear space above each name to sign into.
- **Conforme, Recommending Approval, Approved** — a flat list, each entry with
  ~22px of clear signing space, then the printed name, then the role beneath it.
  The recorded acceptance sits right-aligned on the same row so it cannot collide
  with a handwritten signature.
- **Ex officio entries** appear in the Conforme list after the nominated members,
  their role rendered as *Research Coordinator (ex officio)* and *Dean (ex
  officio)*, with "Ex officio member" in place of an acceptance timestamp. The
  full panel therefore reads in one place, even though only the nominated members
  were asked to accept.
- **No horizontal rules above any name.** Signing space is blank.
- **Verification strip** — states that acceptances were recorded against verified
  institutional accounts, with the reference code. This is what gives a
  system-generated form its authority in place of ink.
- **Footer** — the university's guiding principles and a generation timestamp.
- Fits one page with a five-member group and a six-person panel.

**Three deliberate departures from the printed form:**

1. **Three or more panel entries.** The printed form has two blanks, which
   contradicts §4a's requirement of three panel members. The generated form grows
   with the actual panel.
2. **All researchers listed**, not only the leader who signs. The printed form
   names one student; a group capstone has several.
3. **First person plural** — "*We* have the honor to nominate … to be *our*
   Undergraduate Thesis Adviser". With several researchers listed, the printed
   singular reads wrongly. A solo thesis falls back to the singular.

**The date** in the top-right is the date the **nomination was submitted**, not
the date the PDF was generated. Regenerating an approved form months later must
not silently change the date on it.

**Data sources.** Every value is populated from captured data — nothing is typed
into the form.

| Form element | Source |
|---|---|
| `College of …` in the address block | `thesis.college` |
| "this ___ semester" | `thesis.semester` |
| "Academic Year ___" | `thesis.academicYear` |
| Adviser name (body and Conforme) | `nominations` where `position = adviser` → `nomineeName` |
| Panel member names (body and Conforme) | `nominations` where `position = panelist` → `nomineeName` |
| Leader name | `users.fullName` of `leaderUid` |
| Member names | `thesis.memberNames[]` |
| Conforme acceptance timestamps | `nominations.respondedAt` |
| Coordinator name | `facultyDirectory` lookup of `coordinatorRecommendedBy` |
| Recommended timestamp | `thesis.coordinatorRecommendedAt` |
| Dean name | `facultyDirectory` lookup of `deanApprovedBy` |
| Approved timestamp | `thesis.deanApprovedAt` |
| Reference code | derived from `thesisId` |
| Date (top right) | date the nomination was submitted |
| Control number, letterhead, footer | static |

The panel names in the body sentence and in the Conforme block read from the
**same** nomination records, so the two can never disagree — the failure a
hand-typed form invites.

`thesis.program` is captured at group creation but does not appear on Form 1; the
printed form has no such field. It is retained for the archive and for M1b.

**Institutional risk to confirm.** If the R&D office still requires wet
signatures, a form printing "Accepted via eThesisHub" will not satisfy them.
Worth checking with the Research Coordinator before the defence — it is a policy
question, not a technical one.

### 7.4 Audit

`AuditService` is already wired. M1a adds `nomination.approved` at the Dean's
approval. It must write exactly the six whitelisted keys, and an audit failure
must never break the approval it records.

---

## 8. Out of scope

- **Everything about titles** — candidate titles, justification documents,
  presentations and the title defence are M1b (§11). `workingTitle` is captured
  in M1a only to name the thesis in lists; it is not a candidate.
- **Form 2 — Appointment as Undergraduate Thesis Adviser** — deferred by
  decision. It requires a tentative title, which does not exist until M1b.
- **Uploading signed scans** — not needed; in-app acceptance is the record.
- **Guidelines §1e coordinator-assign fallback** — deferred by decision
- **All other forms (3, 4a, 4b, 5a, 5b, 5c, 7, 8)** — their data comes from
  later modules. Each should emit its own form once its data model exists, reusing
  the PDF scaffolding M1a builds; M6 then covers whatever remains
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
