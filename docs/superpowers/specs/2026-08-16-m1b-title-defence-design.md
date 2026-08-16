# M1b — Title Defence

**Status:** approved design, not yet implemented
**Preceded by:** M1a — Nomination (`2026-08-14-m1-nomination-design.md`)
**Parent:** `2026-08-12-ethesishub-design.md`

Begins where M1a ends: a thesis at `nominationApproved` has an adviser, a panel,
and a signed Form 1. M1b is the title defence — the students bring three or more
candidate titles, each with a justification document, and present them to the
panel. The Dean records which one is approved.

---

## 1. What this milestone is for

The title defence is a real meeting. The panel sits in a room, the students
present, remarks are made aloud, and the Dean announces an outcome. The app does
not run that meeting and must not pretend to: it carries the documents in
beforehand, gives the panel somewhere to write while they listen, and records
what was decided.

That framing settles several design questions at once, and they are noted where
they arise.

---

## 2. Decisions carried in from earlier reviews

These were settled before this spec and are not reopened here.

- **Justification is an uploaded document**, not a structured form. Students
  already write it in Word, and modelling a dozen sections as form fields would
  be painful on a phone and duplicate the paper trail.
- **One presentation** for the defence, uploaded alongside the candidates — a
  single file presented in the room, not one per title.
- **The Dean records the approved title.** The Coordinator, nominated panel
  members and the Adviser comment; none of them cast a formal vote. The panel
  reaches its decision in the room and the app records the outcome rather than
  discovering it. The cost is a weaker per-person audit trail for the title than
  the Conforme chain gives for the nomination, and that is accepted.
- **Comments are optional.** A member who simply agrees is not made to pad the
  record.
- **The Adviser does not vote**, though they attend and comment.
- **Chapters 1–3 are not part of this defence.** They belong to the pre-oral
  (parent §12).

## 3. Decisions made in this review

- **Comments attach to a specific candidate title**, not to the session as a
  whole, so the student can see why one candidate was chosen over another.
- **Faculty see each other's comments live.** Every panel client holds a
  listener; a remark appears for the rest of the panel as it is written. The
  point is that nobody repeats a remark already made.
- **The student sees comments only after the Dean records the decision**, and
  sees them as bracketed blocks per commenter (§7).
- **A rejected title may be resubmitted verbatim.** The panel rejected a
  proposal, not a string; a revised justification for the same title is
  legitimate. Nothing blocks it.
- **A rejection of the whole set requires the Dean's remark.** The student must
  always know what to fix. This mirrors the decline reason already required in
  the Conforme step.
- **Composing indicators are faculty-only** (§6), consistent with comments being
  hidden from the student during the defence.

---

## 4. Data model

```
theses/{thesisId}
  ... M1a nomination fields ...
  presentationPath      string?   Supabase object path
  presentationUrl       string?   public URL
  titlesSubmittedAt     timestamp?
  titleRound            number    1, then 2 after a rejection, and so on.
                                  Absent on theses created by M1a, which
                                  predate it — read as 0.
  approvedTitleId       string?   set by the Dean
  titleDecidedAt        timestamp?
  titleDecidedBy        string?   the Dean's uid
  titleRejectionRemark  string?   required when the set is rejected

  candidateTitles/{titleId}
    titleText           string
    justificationPath   string    Supabase object path
    justificationUrl    string    public URL
    round               number    matches the thesis's titleRound at submission
    submittedAt         timestamp

  titleComments/{commentId}       append-only
    candidateTitleId    string
    authorUid           string
    authorName          string
    authorRole          string    the position held AT THE TIME
    body                string
    createdAt           timestamp

  titleComposing/{uid}            transient
    name                string
    role                string
    candidateTitleId    string
    updatedAt           timestamp
```

### 4.1 Why comments sit under the thesis, not under each candidate

Comments attach to a candidate, so the obvious shape is
`candidateTitles/{titleId}/comments/{commentId}`. They are one level higher
instead, carrying a `candidateTitleId` field.

The panel's live view wants every comment on the thesis, and nesting would make
that either one listener per candidate or a collection-group query. M1a already
paid for that lesson: a collection-group query needs an index declared with
`COLLECTION_GROUP` scope, which Firestore never creates automatically and which
neither the emulator nor `fake_cloud_firestore` will tell you is missing. One
flat collection under the thesis needs one listener and one `match` block.

Grouping by candidate for display is a client-side `groupBy`.

### 4.2 Why `authorRole` is stored rather than looked up

The bracket header reads `[Dr. Armada — Adviser]`. If that were resolved at
render time from the person's current position, a later change would silently
rewrite history — a panel member who becomes coordinator would appear to have
commented as coordinator on a defence where they sat as a panelist. The record
says what they were when they said it.

### 4.3 Why `titleRound` exists

A rejected set is not deleted. The candidates and their comments stay, tagged
with the round they belonged to, and the next submission increments the round.
The student sees the history of what was rejected and why; the panel sees
whether a resubmission actually changed anything.

---

## 5. States

Extends the M1a chain. New values on `ThesisStatus`:

```
nominationApproved
      |
      |  the leader submits 3+ candidates, each with a justification,
      |  plus one presentation
      v
titlePendingDefence
      |
      |  the panel comments during the defence
      |
      +-- the Dean approves one candidate --> titleApproved
      |                                        approvedTitleId set
      |
      +-- the Dean rejects the set ---------> titleRejected
                                               titleRejectionRemark required
                                                     |
                                                     |  leader resubmits,
                                                     |  titleRound + 1
                                                     v
                                               titlePendingDefence
```

`titleApproved` is this milestone's terminal state. The parent design continues
to `in_progress` with the documents module (M2); that transition is M2's to make,
not M1b's.

### 5.1 Every transition is pinned to its prior status

M1a's final review found that the nomination chain could be replayed or skipped
wherever a rule policed only the incoming value. Each transition here names the
status it may run from:

| From | To | Actor |
|---|---|---|
| `nominationApproved` or `titleRejected` | `titlePendingDefence` | leader |
| `titlePendingDefence` | `titleApproved` | dean |
| `titlePendingDefence` | `titleRejected` | dean |

Nothing may move backwards, and no transition may run from any other state.

---

## 6. Composing indicators

While a panel member has a comment field focused, the rest of the panel sees
"Dr. Diamante is writing on Candidate 2…". This exists because the failure it
prevents is real: two people writing the same remark at once because neither
knew the other was typing.

Three constraints shape it, all from the Spark plan.

**It heartbeats rather than streaming.** Writing on each keystroke is the
natural implementation and the wrong one — Spark allows 20,000 writes a day, and
keystroke-level writes would exhaust that in a few defences. The client
refreshes `updatedAt` about every five seconds while the field is focused. A
three-minute composing session costs roughly 36 writes.

**Stale entries expire on the reader.** There are no Cloud Functions to sweep
them, so a laptop closed mid-comment would otherwise leave an indicator up
forever. Readers ignore any entry older than about fifteen seconds. The leftover
document is harmless and hides itself.

**It is a separate collection from the comment.** Composing is transient and
deletable; comments are append-only and permanent. Separating them lets the
rules permit `delete` on one and forbid it on the other. A draft flag on the
comment document would force both to share a rule.

`titleComposing` is the only collection in this system where `delete` is
permitted, and only of one's own document.

---

## 7. The consolidated bracketed output

Parent design §5.3. Comments are presented to the student grouped per commenter,
under the candidate they were made about:

```
Candidate 2 — "A Web and Mobile-Based Thesis Management System"

  [Dr. Noel A. Armada — Adviser]
    Scope is too broad for one semester.
    Narrow the respondents to one college.

  [Dr. Louella C. Diamante — Panel Member]
    Justify the choice of respondents.

Candidate 3 — "An Automated Records System"

  [Prof. Gerson G. Padojinog — Panel Member]
    This one is defensible as scoped.
```

Grouping is by author within a candidate, in the order the authors first
commented, with each author's remarks in the order written. Comments are
append-only, so this is a faithful record rather than a summary.

This automates Guidelines §4d — the adviser consolidates defence comments and
furnishes a copy to the Research Coordinator. It is built here and reused by M3
for the pre-oral and final defences.

---

## 8. Visibility

| | Leader | Panel (adviser, panelists, coordinator, dean) |
|---|---|---|
| Candidate titles and files | yes | yes |
| Comments | only once `titleDecidedAt` is set | yes, always |
| Composing indicators | never | yes |
| Approve / reject | no | Dean only |

The panel here means the same set M1a's `mayReadThesis` already recognises: the
adviser, anyone in `panelistUids`, and anyone holding a nomination on the
thesis — which covers the ex officio Coordinator and Dean.

---

## 9. Security rules

Extends `firestore.rules`. Rules are the only authorization boundary in this
system: there are no Cloud Functions on Spark, and `fake_cloud_firestore` does
not enforce rules, so every rule below needs an emulator test.

**`candidateTitles`**

- `create` — the leader only, while the thesis is at `nominationApproved` or
  `titleRejected`.
- `read` — leader and panel.
- `update`, `delete` — `false`. A candidate is immutable once submitted: the
  panel must not be reading a title the student is still editing.

  `round` is deliberately **not** validated by the rules. It is a display and
  history field, not a security one, and validating it would be wrong as well
  as pointless: the candidates and the thesis update commit in one batch, and
  Firestore evaluates each write in a batch against the state *before* the
  batch. A rule comparing the candidate's `round` to the thesis's `titleRound`
  would therefore compare against the previous round, not the new one. This is
  the same batch-evaluation behaviour M1a relied on to let `submitNominations`
  create nominations and flip the status together, and it was verified against
  the emulator there rather than assumed.

**`titleComments`**

- `create` — `authorUid == request.auth.uid`, the author must hold a position on
  this thesis, `createdAt == request.time`, and the key set is whitelisted.
- `read` — panel at any time; the leader only when the thesis's `titleDecidedAt`
  is non-null.
- `update`, `delete` — `false`. Append-only, per parent §6.4.

**`titleComposing`**

- `read`, `create`, `update` — panel members only, explicitly not the leader,
  and only one's own document (`{uid} == request.auth.uid`).
- `delete` — one's own only.

**Thesis title fields**

- `approvedTitleId`, `titleDecidedAt`, `titleDecidedBy`,
  `titleRejectionRemark` — the Dean only, from a prior status of
  `titlePendingDefence`, with timestamps pinned to `request.time`.
- `titlesSubmittedAt`, `titleRound`, `presentationPath`, `presentationUrl` — the
  leader only, on the transition into `titlePendingDefence`.

### 9.1 Batch size

A submission commits the candidates and the thesis update in one batch, and
each candidate's `create` rule costs one `get()` on the thesis to establish
that the caller is the leader. M1a measured this ceiling directly: 19 documents
in a batch committed and 20 were denied, and the documented Cloud limit is
stricter than the emulator's.

Three candidates is the floor and the common case. **Cap the count at ten** in
the submit screen, which keeps the batch at eleven writes and well inside the
limit, and say why on screen rather than silently disabling the control — the
same treatment the nominate screen gives its panel cap.

### 9.2 Known limitation

A rule cannot check that `approvedTitleId` names a candidate belonging to this
thesis in the current round without a `get()` per decision, and cannot iterate
the candidates at all. `approvedTitleId` is validated with a single `get()` on
that document — the same technique M1a used for `adviserUid`. The round is not
independently verified. A Dean could approve a candidate from a superseded
round. The mitigation is the audit log, not prevention.

---

## 10. Storage

Reuses `StorageService` and its Supabase implementation, built in the skeleton
and until now unused by any screen.

- **Bucket is public.** Objects are readable by anyone holding the URL; the path
  is an unguessable UUID. This was accepted earlier and is restated because M1b
  is the first time real student documents live there.
- **Upload precedes the write.** The file goes to Supabase, then the Firestore
  document records its path. If the write fails the object is orphaned —
  unreferenced, harmless, and a better failure than a document pointing at a
  file that does not exist.
- **Limits**, validated client-side because a public bucket will not enforce
  them: justification PDF or DOCX, 10 MB; presentation PPTX or PDF, 25 MB.

A file picker is a new dependency — `file_picker`, which supports Android and
Web. It is the first package added since the skeleton.

---

## 11. Screens

Three new, one extended. All use the M1a design foundation: `PageShell`,
`EmptyState`, `ErrorState`, `LoadingState`, `StatusChip`.

**Submit candidate titles** (leader) — three title fields to start with room to
add more up to the ten of §9.1, a justification upload per title, one
presentation upload. Submits and navigates to the thesis status screen, per the
pattern M1a settled after the nominate screen was found sitting on a refusal
message after a successful submission.

**Title defence** (panel) — candidates side by side with download links, a
comment box per candidate, the live comment list, and composing indicators. This
is the screen the defence actually runs on, so it must survive a poor connection
and say plainly when it cannot load.

**Dean's decision** — the defence screen plus approve-one and reject-set. The
remark field is required on reject and the control refuses without it.

**Thesis status** (extended) — shows the title stage through `StatusChip`, and
after the decision, the consolidated bracketed comments of §7.

---

## 12. Testing

- Repository logic and the bracketed consolidation under
  `fake_cloud_firestore` and plain unit tests.
- Every rule in §9 gets emulator tests. Two matter most and are named here so
  they cannot be forgotten: **a student cannot read comments before the
  decision**, and **a student cannot read composing indicators at all**. Each
  needs its allow-control on the same path, or a denial proves nothing.
- Widget tests mount a router. M1a shipped a screen behind a duplicate route and
  another that stayed put after a successful submit; neither was visible to a
  test that pumped the screen alone.
- Any collection-group query added here must have its index declared in
  `firestore.indexes.json` in the same commit. No local test can catch a missing
  one.

---

## 13. Out of scope

- Scheduling the defence — M3.
- Chapters 1–3 and the pre-oral defence — M2 and M3.
- Per-panelist voting on the title — settled: the Dean records the outcome.
- The transition to `in_progress` — M2's to make.
- Attendance. Form 1 records appointment to a panel, not who turned up; the same
  distinction applies here.
